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


## The roster is read from the version that writes it and no earlier one. A save
## claiming version 3 recorded a duel whatever a `teams` key on it says — hand-edited,
## or merged in from a newer slot — and nothing vetted that key, so reading it would
## point every per-side check at armies the save has no purse for and report the
## missing purse as the damage instead of the cause.
func test_a_version_3_save_carrying_a_roster_still_loads_as_the_duel_it_recorded() -> void:
	var data := _encoded()
	data["version"] = 3
	data["teams"] = [1, 2, 3, 4]
	assert_eq(SaveCodec.validate(data), "", "version 3 knew no roster, so it has none to be wrong")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_eq(loaded.state.teams, MapData.DEFAULT_TEAMS, "the duel it actually recorded")
	assert_eq(loaded.state.funds.size(), MapData.DEFAULT_TEAMS.size(), "a purse per army, no more")


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


## The grouping arrived at version 5, because a roster stopped implying who was
## fighting whom. Every save written before it recorded a free-for-all — that is
## what a match was — so the absent field is age, not damage.
func test_a_version_4_save_with_no_grouping_loads_as_a_free_for_all() -> void:
	var data := _without("sides", 4)
	assert_eq(SaveCodec.validate(data), "", "version 4 knew no grouping")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_true(loaded.state.sides.is_empty())
	assert_false(loaded.state.allied(1, 2), "which is every army standing alone")


## A real 2v2, on the one board that seats four: the grouping has to come back
## naming the same pairs, and side ids are opaque so they travel as written.
func test_a_grouping_survives_a_round_trip() -> void:
	const BOARD := "res://maps/fixtures/quartet.txt"
	var map := MapData.load_from_file(BOARD, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = BOARD
	state.sides = {1: 7, 3: 7, 2: 9, 4: 9}
	var data := SaveCodec.encode(state, [] as Array[int])
	assert_eq(SaveCodec.validate(data), "")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_true(loaded.state.allied(1, 3), "the pair resumes standing together")
	assert_true(loaded.state.allied(2, 4), "and so does the pair across the board")
	assert_false(loaded.state.allied(1, 2), "the two sides resume hostile")
	assert_eq(loaded.state.sides, {1: 7, 3: 7, 2: 9, 4: 9}, "side ids travel as written")


## A grouping naming an army the roster does not is a save describing a match no
## board could produce — and it would silently allow or forbid a shot.
func test_a_save_allying_a_team_that_does_not_play_is_refused() -> void:
	var data := _encoded()
	data["sides"] = {"3": 0}
	assert_string_contains(SaveCodec.validate(data), "which does not play")
	data["sides"] = {"1": "friendly"}
	assert_string_contains(SaveCodec.validate(data), "malformed")


func test_a_current_save_without_the_grouping_is_refused() -> void:
	assert_string_contains(SaveCodec.validate(_without("sides", SaveCodec.VERSION)), "sides")
