extends GutTest
## The roster in the save envelope: version 4's whole reason for existing (COM-44,
## four-players plan FP1).
##
## Which armies a match seats stopped being a constant, so a save has to carry it.
## That makes the roster unlike every other field here — it is not a fact the codec
## checks, it is the list every per-side check is derived from: whose purse must be
## present, whose commander, which side may be taking the turn. These cases pin both
## halves of that: an absent roster is age rather than damage, and a roster no board
## could have dealt is refused before anything is asked about anyone.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _encoded() -> Dictionary:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = "res://maps/first_steps.txt"
	return SaveCodec.encode(state, [2] as Array[int])


## A save at `version` with `key` taken off it.
func _without(key: String, version: int) -> Dictionary:
	var data := _encoded()
	data["version"] = version
	data.erase(key)
	return data


## The roster arrived at version 4, because a match stopped being a duel by
## definition. Every save on a disk today was written before that, and every one of
## them recorded a two-army match — so the absent field is age, not damage, and a
## version 3 save resumes as the duel it was.
func test_a_version_3_save_with_no_roster_loads_as_a_duel() -> void:
	var data := _without("teams", 3)
	assert_eq(SaveCodec.validate(data), "", "version 3 knew no roster")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_eq(loaded.state.teams, MapData.DEFAULT_TEAMS)
	for team in MapData.DEFAULT_TEAMS:
		assert_true(loaded.state.funds.has(team), "team %d keeps its purse" % team)
	assert_eq(
		int(SaveCodec.encode(loaded.state, loaded.ai_teams)["version"]),
		SaveCodec.VERSION,
		"and re-saves at the current version"
	)


## The one format rule that is about a side rather than a field: every per-side
## check in the codec is derived from the roster, so a roster no board could have
## dealt has to be refused before it is asked about anyone's purse or commander.
func test_a_save_seating_teams_no_board_could_deal_is_refused() -> void:
	for roster: Array in [[1, 9], [2, 3], [], [1, 2, 3, 4, 5]]:
		var data := _encoded()
		data["teams"] = roster
		assert_string_contains(SaveCodec.validate(data), "no board could have dealt")


func test_a_current_save_without_the_roster_is_refused() -> void:
	var data := _without("teams", SaveCodec.VERSION)
	assert_string_contains(SaveCodec.validate(data), "teams")
