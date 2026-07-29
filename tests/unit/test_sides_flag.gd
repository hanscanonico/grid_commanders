extends GutTest
## The `--sides=1+3v2+4` grammar (COM-48, four-players plan D6): who stands with
## whom, stated on the command line.
##
## Kept apart from test_match_request.gd because that file sits at the gdlintrc
## max-public-methods ceiling. Same subject, same shape: a pure answer over a flag
## list, checked without a scene.
##
## The flag is read in two places and this covers both, because neither half means
## anything alone: `MatchRequest.parse_sides_flag` reads the words, and
## `BattleSetup.build` is where a grouping meets the seats a board actually deals.

## Every shipped board but one seats two; Compass is the four-army board FP5 ships.
const DUEL_BOARD := "res://maps/scrimmage.txt"
const FOUR_ARMY_BOARD := "res://maps/compass.txt"


func _args(list: Array) -> PackedStringArray:
	var args := PackedStringArray()
	for item: String in list:
		args.append(item)
	return args


## The match `--sides=<spec>` stages on `map_path`, built the way a boot builds it.
func _staged(map_path: String, spec: String) -> GameState:
	var request := MatchRequest.new()
	request.map_path = map_path
	request.apply_cmdline(_args(["--sides=" + spec]))
	var built := BattleSetup.build(
		request, TerrainDB.load_default(), UnitDB.load_default(), CommanderDB.load_default()
	)
	assert_not_null(built, "the board builds")
	return built.game if built != null else null


## Groups joined by `+`, separated by `v`. The dictionary is what
## `GameState.allied` reads, so what matters is which seats share a value.
func test_sides_groups_the_seats_it_names() -> void:
	var grouped := MatchRequest.parse_sides_flag("1+3v2+4")
	assert_eq(grouped[1], grouped[3], "1 and 3 stand together")
	assert_eq(grouped[2], grouped[4], "so do 2 and 4")
	assert_ne(grouped[1], grouped[2], "and the pairs are opposed")


func test_sides_leaves_a_seat_it_never_names_on_its_own() -> void:
	var grouped := MatchRequest.parse_sides_flag("1+2v3")
	assert_eq(grouped[1], grouped[2])
	assert_ne(grouped[3], grouped[1])
	assert_false(grouped.has(4), "a seat the flag skips keeps its own side")


## Both spellings of a free-for-all produce the empty dictionary — the value the
## hostility authority reads as "every army its own side", and the one every match
## carried before groupings existed. Neither is a mistake, so neither is reported.
func test_a_free_for_all_is_the_empty_grouping() -> void:
	assert_true(MatchRequest.parse_sides_flag("1v2v3v4").is_empty())
	assert_true(MatchRequest.parse_sides_flag("").is_empty())
	assert_push_error_count(0)


## One group naming a seat that a board might not deal is the documented
## pair-against-loners, and is honoured: the seats it skips have no entry, which
## is exactly what `GameState.allied` reads as standing alone.
func test_a_group_that_names_only_some_seats_is_honoured() -> void:
	var grouped := MatchRequest.parse_sides_flag("1+2")
	assert_eq(grouped[1], grouped[2], "the pair the flag names stands together")
	assert_false(grouped.has(3), "and a seat it skips keeps its own side")
	assert_false(grouped.has(4))
	assert_push_error_count(0)


## One group naming every seat is read, not second-guessed: whether it leaves
## anybody to fight depends on the board's roster, and no board is loaded here.
func test_one_group_is_parsed_rather_than_second_guessed() -> void:
	var grouped := MatchRequest.parse_sides_flag("1+2+3+4")
	assert_eq(grouped[1], grouped[4], "every seat it names stands together")
	assert_push_error_count(0)


func test_an_unparseable_grouping_is_refused_rather_than_half_applied() -> void:
	assert_true(MatchRequest.parse_sides_flag("1+xv2").is_empty())
	assert_push_error("is not a grouping")


func test_the_sides_flag_reaches_the_request() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(_args(["--sides=1+3v2+4"]))
	assert_eq(request.sides[1], request.sides[3])
	assert_ne(request.sides[1], request.sides[2])


## A grouping only means something against the seats a board deals, so the board
## is where it is checked. On a two-army board `--sides=1+2` allies everybody: no
## attack or capture would validate, so no army could ever fall and the match could
## never end. It is said out loud and dropped to the free-for-all instead.
func test_a_grouping_that_allies_the_whole_board_is_refused() -> void:
	var game := _staged(DUEL_BOARD, "1+2")
	assert_true(game.sides.is_empty(), "the free-for-all is played instead")
	assert_false(game.allied(1, 2), "so the two armies are hostile again")
	assert_push_error("allies every army")


## The same flag on a board that seats four is the documented pair against two
## loners, and is honoured untouched.
func test_the_same_grouping_is_honoured_where_the_board_seats_more() -> void:
	var game := _staged(FOUR_ARMY_BOARD, "1+2")
	assert_true(game.allied(1, 2), "the pair the flag names stands together")
	assert_false(game.allied(1, 3), "and the seats it skips stand alone")
	assert_false(game.allied(3, 4))
	assert_push_error_count(0)


## A grouping with two sides in it leaves somebody hostile on any roster, so it
## reaches the board whatever the board seats.
func test_a_two_sided_grouping_reaches_every_board() -> void:
	for board in [DUEL_BOARD, FOUR_ARMY_BOARD]:
		var game := _staged(board, "1+3v2+4")
		assert_false(game.sides.is_empty(), "the grouping survives on %s" % board)
		assert_false(game.allied(1, 2), "1 and 2 are opposed on %s" % board)
	var four := _staged(FOUR_ARMY_BOARD, "1+3v2+4")
	assert_true(four.allied(1, 3), "and where the board seats them, 1 and 3 stand together")
	assert_push_error_count(0)
