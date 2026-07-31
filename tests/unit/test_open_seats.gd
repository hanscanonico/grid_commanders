extends GutTest
## A seat may stay empty, and only a home HQ fells an army (COM-125, open-seats
## plan OS1/D1/D3).
##
## The map is still the roster authority — it says how many seats exist and where
## they sit. What is new is that the authority bends downward: a match fills any
## two or more of those seats, and the seats it leaves out never enter the state at
## all. The invariant every case below is really testing is one sentence: **a
## reduced match on a big board produces exactly the state a small board would have
## produced.**
##
## The home HQ is the same milestone's other half. "Capturing an HQ eliminates its
## owner" is exact only while every HQ has a living owner and no army holds two —
## and open seats break the first while a conqueror already broke the second.

const QUARTET := "res://maps/fixtures/quartet.txt"
## Three armies in a row of HQs, each on its own, with room below to stand. Seat 3
## is the one closed when a vacant seat is wanted, and its HQ at (2, 0) is then the
## unowned one anybody may walk onto.
const THREE_SEATS := """
[terrain]
QQQ
...
[owners]
1 0 0
2 1 0
3 2 0
[units]
1 i 2 0
2 i 0 1
3 i 2 1
"""
## Team 2's soldier stands on team 3's home HQ, team 1's waits below it. One
## capture fells team 3 and leaves team 2 holding two HQs — the shape the behead-
## through-the-outpost case needs.
const TWO_HQ_CONQUEROR := """
[terrain]
QQ.Q
....
[owners]
1 0 0
2 1 0
3 3 0
[units]
2 i 3 0
1 i 3 1
3 i 0 1
"""

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state(map_text: String, seats: Array[int] = []) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	assert_not_null(map)
	return GameState.create(map, unit_db, chart, {}, seats)


func _quartet(seats: Array[int] = []) -> GameState:
	var map := MapData.load_from_file(QUARTET, terrain_db)
	assert_not_null(map)
	var state := GameState.create(map, unit_db, chart, {}, seats)
	assert_not_null(state)
	state.map_path = QUARTET
	return state


func _path(cells: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for cell: Vector2i in cells:
		typed.append(cell)
	return typed


## One capture that finishes this turn, wherever the unit already stands.
func _capture(state: GameState, unit: Unit, cell: Vector2i) -> void:
	state.capture_progress[cell] = 1
	CaptureCommand.new(unit, _path([cell])).apply(state)


# --- the seating -------------------------------------------------------------


## The default, and the whole of the regression guarantee: a match that names no
## seats is the match the board deals, exactly as before this parameter existed.
func test_naming_no_seats_plays_the_board_the_map_deals() -> void:
	var state := _quartet()
	assert_eq(state.teams, [1, 2, 3, 4] as Array[int])
	assert_eq(state.units.size(), 4, "every seat fields what the map gave it")
	assert_eq(state.owner_at(Vector2i(14, 7)), 2, "and owns what the map gave it")


func test_a_closed_seat_leaves_the_roster_without_renumbering() -> void:
	var state := _quartet([1, 3] as Array[int])
	assert_eq(state.teams, [1, 3] as Array[int], "seat 3 is still seat 3")
	assert_eq(state.current_team, 1, "and the match opens on the first of them")
	assert_eq(state.funds.keys(), [1, 3], "only the armies at the table have a purse")


func test_a_vacant_seat_fields_nothing_and_its_ground_opens_neutral() -> void:
	var state := _quartet([1, 3] as Array[int])
	assert_eq(state.units.size(), 2, "the closed seats' starting units never appear")
	assert_true(state.units_of(2).is_empty())
	assert_true(state.units_of(4).is_empty())
	assert_eq(state.owner_at(Vector2i(14, 7)), MapData.NEUTRAL, "seat 2's HQ is loose ground")
	assert_eq(state.owner_at(Vector2i(1, 7)), MapData.NEUTRAL, "so is seat 4's")
	assert_eq(state.owner_at(Vector2i(1, 1)), 1, "the filled seats keep theirs")
	assert_eq(state.owner_at(Vector2i(14, 1)), 3)


## The invariant the whole milestone rests on, stated as an assertion: the reduced
## match is not *like* a smaller board's state, it is that state.
func test_a_reduced_match_is_the_state_a_smaller_board_would_have_produced() -> void:
	var reduced := _quartet([1, 2] as Array[int])
	var authored := _state(
		(
			"[terrain]\n"
			+ "................\n.Q.B........B.Q.\n................\n"
			+ ".....F....F.....\n.......CC.......\n.....F....F.....\n"
			+ "................\n.Q.B........B.Q.\n................\n"
			+ "[owners]\n1 1 1\n1 3 1\n2 12 7\n2 14 7\n"
			+ "[units]\n1 i 2 2\n2 i 13 6\n"
		)
	)
	assert_not_null(authored)
	assert_eq(reduced.teams, authored.teams)
	assert_eq(reduced.funds, authored.funds)
	assert_eq(reduced.property_owners, authored.property_owners)
	assert_eq(reduced.home_hq, authored.home_hq)
	assert_eq(reduced.units.size(), authored.units.size())


func test_the_turn_rolls_over_a_closed_seat_and_the_day_wraps_on_the_last_one() -> void:
	var state := _quartet([1, 3, 4] as Array[int])
	assert_eq(state.teams, [1, 3, 4] as Array[int])
	EndTurnCommand.new().apply(state)
	assert_eq(state.current_team, 3, "seat 2 was never at the table to be skipped")
	assert_eq(state.day, 1)
	EndTurnCommand.new().apply(state)
	assert_eq(state.current_team, 4)
	assert_eq(state.day, 1)
	EndTurnCommand.new().apply(state)
	assert_eq(state.current_team, 1, "the hand rolls back past the last filled seat")
	assert_eq(state.day, 2, "which is where the day turns")


func test_seats_the_board_never_dealt_are_simply_not_at_the_table() -> void:
	var state := _quartet([1, 2, 3, 4] as Array[int])
	assert_eq(state.teams, [1, 2, 3, 4] as Array[int])
	var duel := _state("[terrain]\n....\n[units]\n1 i 0 0\n2 i 3 0", [1, 2, 3] as Array[int])
	assert_eq(duel.teams, [1, 2] as Array[int], "a duel board has no third seat to fill")


## Refused rather than guessed at: one army is not a match, and `create` is where
## every route in — the menu, a rematch, `--seats=` — has to pass.
func test_a_seating_that_leaves_fewer_than_two_armies_is_refused() -> void:
	var map := MapData.load_from_file(QUARTET, terrain_db)
	assert_null(
		GameState.create(map, unit_db, chart, {}, [1] as Array[int]), "one filled seat is no match"
	)
	assert_push_error("seats [1] leave 1 of the board's")
	assert_null(
		GameState.create(map, unit_db, chart, {}, [9] as Array[int]),
		"and neither is a seating naming nobody the board deals"
	)
	assert_push_error("seats [9] leave 0 of the board's")


# --- the home HQ -------------------------------------------------------------


func test_every_filled_seat_starts_on_a_home_hq() -> void:
	var state := _quartet()
	assert_eq(state.home_hq[1], Vector2i(1, 1))
	assert_eq(state.home_hq[3], Vector2i(14, 1))
	assert_eq(state.home_hq[4], Vector2i(1, 7))
	assert_eq(state.home_hq[2], Vector2i(14, 7))


func test_a_closed_seat_has_no_home_to_lose() -> void:
	var state := _quartet([1, 3] as Array[int])
	assert_eq(state.home_hq.keys(), [1, 3])


## The duel parity clause: on a board where a team's home HQ is the only HQ it
## could ever lose, D3 is today's rule spelled differently.
func test_taking_an_armys_home_hq_still_fells_it() -> void:
	var state := _state("[terrain]\nQ.\n[owners]\n2 0 0\n[units]\n1 i 0 0\n2 i 1 0")
	_capture(state, state.units[0], Vector2i(0, 0))
	assert_true(state.is_eliminated(2), "its home was taken")
	assert_eq(state.winner, 1)


func test_a_vacant_seats_hq_is_taken_like_any_other_property() -> void:
	var state := _state(THREE_SEATS, [1, 2] as Array[int])
	assert_eq(state.owner_at(Vector2i(2, 0)), MapData.NEUTRAL, "seat 3 left its HQ behind")
	_capture(state, state.units_of(1)[0], Vector2i(2, 0))
	assert_eq(state.owner_at(Vector2i(2, 0)), 1, "and anybody may walk onto it")
	assert_eq(state.eliminated, {}, "there is no army behind it to fall")
	assert_eq(state.winner, 0, "so the match runs on")


## The case that is latent with or without open seats: a survivor who conquers an
## HQ owns two, and "eliminate the HQ's owner" would let a rival behead them
## through the one they took.
func test_a_conquered_hq_cannot_behead_the_army_that_took_it() -> void:
	var state := _state(TWO_HQ_CONQUEROR)
	_capture(state, state.units_of(2)[0], Vector2i(3, 0))
	assert_true(state.is_eliminated(3), "team 3 lost its home")
	assert_eq(state.winner, 0, "two armies are still fighting")
	assert_eq(state.owner_at(Vector2i(3, 0)), 2, "team 2 holds the HQ it conquered")
	assert_eq(state.owner_at(Vector2i(1, 0)), 2, "as well as its own")

	# The conqueror walks off the outpost; team 1 takes it back.
	state.units_of(2)[0].cell = Vector2i(2, 0)
	_capture(state, state.units_of(1)[0], Vector2i(3, 0))
	assert_eq(state.owner_at(Vector2i(3, 0)), 1, "team 1 now holds it")
	assert_false(state.is_eliminated(2), "which is a property, not team 2's head")
	assert_eq(state.winner, 0)


func test_the_home_hq_is_where_an_army_began_not_where_it_stands() -> void:
	var state := _state(TWO_HQ_CONQUEROR)
	_capture(state, state.units_of(2)[0], Vector2i(3, 0))
	assert_eq(state.home_hq[2], Vector2i(1, 0), "conquest does not move a home")
	assert_eq(state.home_hq[3], Vector2i(3, 0), "nor does losing one")


# --- the save carries it -----------------------------------------------------


func test_a_reduced_match_round_trips_mid_capture() -> void:
	var state := _quartet([1, 3] as Array[int])
	state.capture_progress[Vector2i(14, 7)] = 8  # a vacant seat's HQ, half taken
	state.funds[3] = 4200
	var data := SaveCodec.encode(state, [3] as Array[int])
	assert_eq(SaveCodec.validate(data), "")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_eq(loaded.state.teams, [1, 3] as Array[int], "the reduced roster resumes reduced")
	assert_eq(loaded.state.funds, state.funds)
	assert_eq(loaded.state.home_hq, state.home_hq)
	assert_eq(loaded.state.capture_progress[Vector2i(14, 7)], 8)
	assert_eq(loaded.state.owner_at(Vector2i(14, 7)), MapData.NEUTRAL, "and so does the loose HQ")


## Exact rather than a guess: a save written before the field existed always seated
## the board's full roster, so every army it names began on the HQ its map gave it.
func test_a_save_written_before_home_hqs_takes_them_from_its_map() -> void:
	var state := _quartet()
	var data := SaveCodec.encode(state, [] as Array[int])
	data.erase("home_hq")
	data["version"] = 6
	assert_eq(SaveCodec.validate(data), "", "version 6 knew no home HQs to demand")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_eq(loaded.state.home_hq, state.home_hq)


func test_a_current_save_without_home_hqs_is_refused() -> void:
	var data := SaveCodec.encode(_quartet(), [] as Array[int])
	data.erase("home_hq")
	assert_eq(SaveCodec.validate(data), "a version 7 save is missing 'home_hq'")


func test_a_home_hq_for_an_army_that_does_not_play_is_refused() -> void:
	var data := SaveCodec.encode(_quartet([1, 3] as Array[int]), [] as Array[int])
	data["home_hq"].append({"team": 2, "x": 14, "y": 7})
	assert_eq(SaveCodec.validate(data), "the save gives a home HQ to team 2, which does not play")


func test_two_home_hqs_for_one_army_are_refused() -> void:
	var data := SaveCodec.encode(_quartet(), [] as Array[int])
	data["home_hq"].append({"team": 1, "x": 14, "y": 7})
	assert_eq(SaveCodec.validate(data), "the save gives team 1 two home HQs")


## The board's half of the same field. A home HQ that is not an HQ is an army no
## capture can ever take out of the match — a save that loads clean and plays a
## rule short.
func test_a_home_hq_that_is_not_an_hq_is_refused() -> void:
	var map := MapData.load_from_file(QUARTET, terrain_db)
	var data := SaveCodec.encode(_quartet(), [] as Array[int])
	data["home_hq"][0] = {"team": 1, "x": 0, "y": 0}
	assert_eq(SaveCodec.board_error(data, map), "team 1's home HQ at (0, 0) is not an HQ")


func test_a_home_hq_off_the_board_is_refused() -> void:
	var map := MapData.load_from_file(QUARTET, terrain_db)
	var data := SaveCodec.encode(_quartet(), [] as Array[int])
	data["home_hq"][0] = {"team": 1, "x": 99, "y": 99}
	assert_eq(SaveCodec.board_error(data, map), "home HQ at (99, 99) is off a 16x9 board")
