extends GutTest
## What a reduced match and a home HQ cost the save format (COM-125, open-seats
## plan OS1/D3): version 7, and one new field the two validators both answer for.
##
## Kept apart from test_open_seats.gd because that file sits at the gdlintrc
## max-public-methods ceiling, and because these cases are about the *envelope*
## rather than about the rules: what a save carries, what it is refused for, and
## what an older one is given instead of being rejected.
##
## The field is derivable — the map plus the roster give the same answer, and a save
## written before version 7 is decoded exactly that way. Carrying it is what pins
## each army's home against a later edit of the map file: the board's answer and the
## save's are compared, so a save whose board has moved is refused rather than
## quietly re-homed.

const QUARTET := "res://maps/fixtures/quartet.txt"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _quartet(seats: Array[int] = []) -> GameState:
	var map := MapData.load_from_file(QUARTET, terrain_db)
	assert_not_null(map)
	var state := GameState.create(map, unit_db, chart, {}, seats)
	assert_not_null(state)
	state.map_path = QUARTET
	return state


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
	assert_eq(SaveCodec.validate(data), "a version 8 save is missing 'home_hq'")


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


## The same harm reached by deleting instead of editing: no entry at all is an army
## no capture can behead, and every other check waves it through. The board is what
## says one was owed, which is why this half needs the map.
func test_a_home_hq_the_board_deals_but_the_save_omits_is_refused() -> void:
	var map := MapData.load_from_file(QUARTET, terrain_db)
	var data := SaveCodec.encode(_quartet(), [] as Array[int])
	(data["home_hq"] as Array).remove_at(0)
	assert_eq(SaveCodec.validate(data), "", "the list is still well formed, which is the point")
	assert_eq(
		SaveCodec.board_error(data, map),
		"the save gives team 1 no home HQ, but its board starts it on one"
	)


## The pin the field is carried for, doing its job: an entry pointing at a real HQ
## that is somebody else's is the same wrong-cell harm as a missing one, and it is
## also what a map edit that moved a home would look like from here.
func test_a_home_hq_pinned_to_another_armys_hq_is_refused() -> void:
	var map := MapData.load_from_file(QUARTET, terrain_db)
	var data := SaveCodec.encode(_quartet(), [] as Array[int])
	data["home_hq"][0] = {"team": 1, "x": 14, "y": 7}
	assert_eq(SaveCodec.validate(data), "", "one entry per army, each an army that plays")
	assert_eq(
		SaveCodec.board_error(data, map),
		"the save homes team 1 at (14, 7), but its board starts it at (1, 1)"
	)


## And the allowance that survives it: a board is free to deal a seat no HQ, so an
## army the map never homed is owed no entry and the save is clean without one.
func test_an_army_the_board_never_homed_is_owed_no_entry() -> void:
	var map := MapData.parse("[terrain]\n..\n[units]\n1 i 0 0\n2 i 1 0", terrain_db)
	assert_not_null(map)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	assert_eq(state.home_hq, {}, "a board with no HQ on it homes nobody")
	var data := SaveCodec.encode(state, [] as Array[int])
	assert_eq(SaveCodec.validate(data), "")
	assert_eq(SaveCodec.board_error(data, map), "")


func test_a_home_hq_off_the_board_is_refused() -> void:
	var map := MapData.load_from_file(QUARTET, terrain_db)
	var data := SaveCodec.encode(_quartet(), [] as Array[int])
	data["home_hq"][0] = {"team": 1, "x": 99, "y": 99}
	assert_eq(SaveCodec.board_error(data, map), "home HQ at (99, 99) is off a 16x9 board")
