extends GutTest
## The name a board gives a unit: how it is authored, how it is refused, and
## version 9's carrying of it. Separate from the map and codec suites so their
## public-method ceilings hold, the way version 8's refresh flag is.
##
## The journey is the thing being pinned, because a tag is worth nothing at any
## single point of it: the board names a unit, `GameState.create` carries the name
## onto the live one, and the save brings it back — a mission that is about one
## unit has to find that unit again after a resume.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state() -> GameState:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = "res://maps/first_steps.txt"
	return state


## A board with one named unit and one unnamed, so the default is pinned beside
## the feature rather than assumed.
func _named_state() -> GameState:
	var map := MapData.parse("[terrain]\n....\n[units]\n1 i 0 0 courier\n2 t 3 0", terrain_db)
	return GameState.create(map, unit_db, chart)


## The optional fifth column, which every board that shipped before it omits.
func test_a_unit_line_may_name_its_unit() -> void:
	var map := MapData.parse("[terrain]\n....\n[units]\n1 i 0 0 courier\n2 t 3 0", terrain_db)
	assert_not_null(map)
	assert_eq(map.starting_units[0]["tag"], &"courier")
	assert_eq(map.starting_units[1]["tag"], &"", "a unit nobody named stays unnamed")


## A tag naming two units names neither: an objective asking whether it still
## stands would have two answers, so the board refuses it before one is picked.
func test_a_duplicate_tag_is_rejected() -> void:
	assert_null(MapData.parse("[terrain]\n....\n[units]\n1 i 0 0 relay\n2 t 3 0 relay", terrain_db))
	assert_push_error("names two units")


func test_a_tag_that_is_not_an_identifier_is_rejected() -> void:
	assert_null(MapData.parse("[terrain]\n....\n[units]\n1 i 0 0 not-a-name", terrain_db))
	assert_push_error("is not an identifier")


func test_a_named_unit_reaches_the_board_named() -> void:
	var state := _named_state()
	assert_eq(state.units[0].tag, &"courier")
	assert_eq(state.units[1].tag, &"", "a unit the board did not name has no name")


func test_tags_round_trip() -> void:
	var state := _state()
	state.units[0].tag = &"draeg_gun"
	var loaded := SaveCodec.decode(
		SaveCodec.encode(state, [] as Array[int]), terrain_db, unit_db, chart
	)
	assert_not_null(loaded)
	assert_eq(loaded.state.units[0].tag, &"draeg_gun")
	assert_eq(loaded.state.units[1].tag, &"", "and an unnamed unit comes back unnamed")


func test_a_current_save_without_a_tag_is_refused() -> void:
	var data := SaveCodec.encode(_state(), [] as Array[int])
	(data["units"] as Array)[0].erase("tag")
	assert_string_contains(SaveCodec.validate(data), "tag")


func test_a_malformed_tag_is_refused() -> void:
	var data := SaveCodec.encode(_state(), [] as Array[int])
	(data["units"] as Array)[0]["tag"] = 7
	assert_string_contains(SaveCodec.validate(data), "tag")


## The compatibility half: a save written before this milestone names nothing, and
## must load as the match it was rather than being refused for a field its writer
## had never heard of.
func test_a_version_8_save_loads_with_every_unit_unnamed() -> void:
	var data := SaveCodec.encode(_state(), [] as Array[int])
	data["version"] = 8
	for entry: Dictionary in data["units"] as Array:
		entry.erase("tag")
	assert_eq(SaveCodec.validate(data), "", "version 8 knew no tags")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_eq(loaded.state.units[0].tag, &"")
