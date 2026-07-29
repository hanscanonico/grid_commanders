extends GutTest
## The `--sides=1+3v2+4` grammar (COM-48, four-players plan D6): who stands with
## whom, stated on the command line.
##
## Kept apart from test_match_request.gd because that file sits at the gdlintrc
## max-public-methods ceiling. Same subject, same shape: a pure answer over a flag
## list, checked without a scene.


func _args(list: Array) -> PackedStringArray:
	var args := PackedStringArray()
	for item: String in list:
		args.append(item)
	return args


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
## carried before groupings existed.
func test_a_free_for_all_is_the_empty_grouping() -> void:
	assert_true(MatchRequest.parse_sides_flag("1v2v3v4").is_empty())
	assert_true(MatchRequest.parse_sides_flag("").is_empty())
	assert_true(MatchRequest.parse_sides_flag("1+2+3+4").is_empty(), "one side is nobody to fight")


func test_an_unparseable_grouping_is_refused_rather_than_half_applied() -> void:
	assert_true(MatchRequest.parse_sides_flag("1+xv2").is_empty())
	assert_push_error("is not a grouping")


func test_the_sides_flag_reaches_the_request() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(_args(["--sides=1+3v2+4"]))
	assert_eq(request.sides[1], request.sides[3])
	assert_ne(request.sides[1], request.sides[2])
