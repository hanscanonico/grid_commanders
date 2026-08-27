extends GutTest
## The `--seats=1,3,4` grammar (COM-126, open-seats plan D2): which of a board's
## seats this match fills, stated on the command line and carried by the request.
##
## Kept apart from test_match_request.gd because that file sits at the gdlintrc
## max-public-methods ceiling — the same split, for the same reason, as its sibling
## test_sides_flag.gd. Same subject, same shape: a pure answer over a flag list,
## checked without a scene.
##
## The seating is read in two places and this covers both, because neither half
## means anything alone: `MatchRequest` reads the words and hands them on, and
## `GameState.create` — reached through `BattleSetup.build` — is where a seating
## meets the seats a board actually deals and is refused if it names none of them.

## Most shipped boards seat two; Compass is the four-army board, so it is the one
## that has seats to close at all.
const DUEL_BOARD := "res://maps/scrimmage.txt"
const FOUR_ARMY_BOARD := "res://maps/compass.txt"
const QUARTET := "res://maps/fixtures/quartet.txt"


## The match a set of flags stages on `map_path`, built the way a boot builds it.
## Null when the build was refused, which is a result these cases assert on.
func _staged(map_path: String, flags: Array) -> BattleSetup.BuiltMatch:
	var request := MatchRequest.new()
	request.map_path = map_path
	request.apply_cmdline(Fixture.args(flags))
	return BattleSetup.build(
		request, Fixture.terrain_db(), Fixture.unit_db(), Fixture.commander_db()
	)


# --- the words ----------------------------------------------------------------


func test_naming_no_seats_fills_every_one_of_them() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--fog"]))
	assert_eq(request.seats, [] as Array[int], "empty is the whole board, as it always was")


func test_seats_names_which_armies_play() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--seats=1,3,4"]))
	assert_eq(request.seats, [1, 3, 4] as Array[int], "in the order written, never renumbered")


## An empty flag is not an absent one, the same as `--co=` and `--seed=`: it says
## "every seat", which is how a capture undoes a seating a rematch put there.
func test_an_empty_seats_flag_reopens_every_seat() -> void:
	var request := MatchRequest.new()
	request.seats = [1, 3] as Array[int]
	request.apply_cmdline(Fixture.args(["--seats="]))
	assert_eq(request.seats, [] as Array[int], "cleared, not left standing")


func test_omitting_seats_leaves_the_seating_alone() -> void:
	var request := MatchRequest.new()
	request.seats = [1, 3] as Array[int]
	request.apply_cmdline(Fixture.args(["--fog"]))
	assert_eq(request.seats, [1, 3] as Array[int], "untouched")


func test_a_seating_that_is_not_one_is_refused_out_loud() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--seats=1,north"]))
	assert_push_error("--seats=1,north is not a seating")
	assert_eq(
		request.seats, [] as Array[int], "and the whole board plays, said rather than assumed"
	)


## Commanders are positional over the seats that *play*: on `--seats=1,3` the
## second id is seat 3's general, not a pick for a chair nobody is in. Which is why
## `--seats` is read first — the list has to be dealt over the right table.
func test_co_is_dealt_over_the_filled_seats() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--seats=1,3", "--co=alina_ward,viktor_draeg"]))
	assert_eq(request.commanders[1], &"alina_ward")
	assert_eq(request.commanders[3], &"viktor_draeg", "the second id went to the second army")
	assert_false(request.commanders.has(2), "and nobody was seated in the closed chair")


func test_co_is_dealt_over_the_whole_board_when_no_seat_is_closed() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--co=alina_ward,viktor_draeg"]))
	assert_eq(request.commanders[1], &"alina_ward")
	assert_eq(request.commanders[2], &"viktor_draeg")


# --- the adapters -------------------------------------------------------------


func test_the_menu_adapter_carries_the_seating_the_strip_set() -> void:
	var seats: Array[int] = [1, 3]
	var request := MatchRequest.from_menu(
		"res://maps/x.txt", [3] as Array[int], false, &"normal", {}, false, {}, seats
	)
	seats.append(4)
	assert_eq(request.seats, [1, 3] as Array[int], "copied, so a later edit does not leak in")


## A rematch of a *reduced* match is that match again — the same corner of the same
## board, not the full roster the file could have seated.
func test_the_rematch_adapter_replays_the_seating_it_was_played_at() -> void:
	var chart: DamageChart = Fixture.chart()
	var map := MapData.load_from_file(QUARTET, Fixture.terrain_db())
	var game := GameState.create(map, Fixture.unit_db(), chart, {}, [1, 3] as Array[int])
	assert_not_null(game)
	var request := MatchRequest.from_match(game, [3] as Array[int], &"normal")
	assert_eq(request.seats, [1, 3] as Array[int], "the table it was actually played at")


# --- where a seating meets a board --------------------------------------------


func test_a_seating_plays_the_board_it_names_a_corner_of() -> void:
	var built := _staged(FOUR_ARMY_BOARD, ["--seats=1,3"])
	assert_not_null(built, "a two-army match on a four-seat board is a match")
	assert_eq(built.game.teams, [1, 3] as Array[int], "seat 3 is still seat 3")
	assert_eq(built.game.funds.keys(), [1, 3], "and only they have a purse")


## Refused, not guessed at, and refused where the board is known. `Battle` disables
## itself on a null build rather than inventing a match to play.
func test_a_seating_with_nobody_to_fight_fails_the_build() -> void:
	assert_null(_staged(FOUR_ARMY_BOARD, ["--seats=1"]), "one army is no match")
	assert_push_error("which is no match")
	assert_push_error("failed to build game state")


func test_a_seating_naming_a_seat_the_board_never_dealt_fails_the_build() -> void:
	assert_null(_staged(DUEL_BOARD, ["--seats=1,3"]), "a duel board has no third seat to fill")
	assert_push_error("does not deal")
	assert_push_error("failed to build game state")


## A grouping may only name a seat this match fills. Seat 2 closed and then allied
## is two statements in one launch that contradict each other, so the grouping
## described a different match — refused out loud and dropped to the free-for-all
## rather than half-applied.
func test_a_grouping_that_allies_a_closed_seat_is_refused() -> void:
	var built := _staged(FOUR_ARMY_BOARD, ["--seats=1,3,4", "--sides=1+2v3+4"])
	assert_not_null(built)
	assert_true(built.game.sides.is_empty(), "the free-for-all is played instead")
	assert_push_error("does not seat")


## The other shape, which stays tolerated, and the line between them: a grouping
## reaching past the *board's own* roster is one written for a wider map, and
## degenerates to what the board seats. Nothing there contradicts anything — no
## seating closed those seats, the file simply never had them.
func test_a_grouping_reaching_past_the_boards_roster_is_still_honoured() -> void:
	var built := _staged(DUEL_BOARD, ["--sides=1+3v2+4"])
	assert_not_null(built)
	assert_false(built.game.sides.is_empty(), "the grouping survives")
	assert_false(built.game.allied(1, 2), "and the two armies it seats are opposed")
	assert_push_error_count(0)


## The computer is narrowed to the table too, and silently — nothing a player types
## reaches that list, so it is the request's own default (seat 2, the opponent every
## launch has had) being narrowed to a fact stated later, not somebody's instruction
## being discarded. Closing seat 2 leaves a table of people, which is what closing
## it said.
func test_a_computer_on_a_closed_seat_simply_is_not_at_the_table() -> void:
	var built := _staged(FOUR_ARMY_BOARD, ["--seats=1,3"])
	assert_not_null(built)
	assert_eq(built.ai_teams, [] as Array[int], "seat 2 is not at this table")
	assert_push_error_count(0)


## Watch mode seats a planner on exactly the filled roster — the reduced soak
## grammar the board milestones are launched with.
func test_watch_seats_the_computer_on_every_filled_seat() -> void:
	var built := _staged(FOUR_ARMY_BOARD, ["--watch", "--seats=1,3,4"])
	assert_not_null(built)
	assert_eq(built.ai_teams, [1, 3, 4] as Array[int], "every army at the table plans")
	assert_eq(built.game.teams, built.ai_teams, "and the table is the seating")
