extends GutTest
## Version 8's one additive fact: whether an acted unit may be refreshed. It is
## separate from the crowded codec suites so their public-method ceiling holds.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


func _state() -> GameState:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = "res://maps/first_steps.txt"
	return state


func test_refreshable_round_trips() -> void:
	var state := _state()
	state.units[0].acted = true
	state.units[0].refreshable = true
	var loaded := SaveCodec.decode(
		SaveCodec.encode(state, [] as Array[int]), terrain_db, unit_db, chart
	)
	assert_not_null(loaded)
	assert_true(loaded.state.units[0].acted)
	assert_true(loaded.state.units[0].refreshable)


func test_a_current_save_without_refreshable_is_refused() -> void:
	var data := SaveCodec.encode(_state(), [] as Array[int])
	(data["units"] as Array)[0].erase("refreshable")
	assert_string_contains(SaveCodec.validate(data), "refreshable")


func test_a_malformed_refreshable_flag_is_refused() -> void:
	var data := SaveCodec.encode(_state(), [] as Array[int])
	(data["units"] as Array)[0]["refreshable"] = "yes"
	assert_string_contains(SaveCodec.validate(data), "refreshable")


func test_a_version_7_save_defaults_to_not_refreshable() -> void:
	var data := SaveCodec.encode(_state(), [] as Array[int])
	data["version"] = 7
	for entry: Dictionary in data["units"] as Array:
		entry.erase("refreshable")
	assert_eq(SaveCodec.validate(data), "", "version 7 knew no refresh flag")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_false(loaded.state.units[0].refreshable)
