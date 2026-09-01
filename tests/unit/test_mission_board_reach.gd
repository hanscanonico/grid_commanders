extends GutTest
## `MissionBoardReach`: an objective's ground has to be somewhere a unit the
## player can field could get to, read off terrain alone.
##
## The fixtures are the rejection cases the shipped content cannot hold, and the
## last test walks every shipped mission — the board redraws this check exists
## for are real content, and a fixture cannot have a wall drawn in the wrong
## place.

## A tank west of a mountain wall, the enemy's city east of it. Treads cannot
## cross a mountain, so the city is out of reach until something flies.
const WALLED := """
[terrain]
.MC
.M.
[owners]
2 2 0
[units]
1 t 0 0
"""

const WALLED_WITH_COPTER := WALLED + "1 h 0 1\n"

## The same wall, with the player's own airport on the near side: it builds air,
## and what a property builds counts as fieldable.
const WALLED_WITH_AIRPORT := """
[terrain]
.MC
AM.
[owners]
1 0 1
2 2 0
[units]
1 t 0 0
"""

## The same wall, the player's property a city — it builds nothing, so it
## contributes no class and the wall still holds.
const WALLED_WITH_CITY := """
[terrain]
.MC
CM.
[owners]
1 0 1
2 2 0
[units]
1 t 0 0
"""

const CITY := Vector2i(2, 0)

var terrain_db: TerrainDB
var unit_db: UnitDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()


func _map(text: String) -> MapData:
	var map := MapData.parse(text, terrain_db)
	assert_not_null(map)
	return map


func _capture(cell: Vector2i, hidden: bool = false) -> CaptureCellObjective:
	var objective := CaptureCellObjective.new()
	objective.text = "Capture the city"
	objective.cell = cell
	objective.hidden = hidden
	return objective


func _refusal(text: String, cell: Vector2i) -> String:
	return (
		"mission 'walled': '%s' at %s cannot be reached by any unit the player can field"
		% [text, cell]
	)


func _mission(
	objectives: Array[MissionObjective], bonus: Array[MissionObjective] = []
) -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.id = &"walled"
	mission.player_team = 1
	mission.objectives = objectives
	mission.bonus_objectives = bonus
	return mission


func test_ground_behind_a_wall_is_refused_for_an_army_that_cannot_cross_it() -> void:
	var mission := _mission([_capture(CITY)])
	assert_eq(
		MissionBoardReach.error(mission, _map(WALLED), unit_db), _refusal("Capture the city", CITY)
	)


func test_a_dealt_unit_that_flies_reaches_over_the_wall() -> void:
	var mission := _mission([_capture(CITY)])
	assert_eq(MissionBoardReach.error(mission, _map(WALLED_WITH_COPTER), unit_db), "")


func test_a_property_that_builds_contributes_what_it_builds() -> void:
	var mission := _mission([_capture(CITY)])
	assert_eq(MissionBoardReach.error(mission, _map(WALLED_WITH_AIRPORT), unit_db), "")


func test_a_property_that_builds_nothing_contributes_no_class() -> void:
	var mission := _mission([_capture(CITY)])
	assert_ne(MissionBoardReach.error(mission, _map(WALLED_WITH_CITY), unit_db), "")


func test_a_zone_passes_on_one_reachable_cell() -> void:
	var zone := ReachCellObjective.new()
	zone.text = "Move 1 unit to the pass"
	zone.cells = [CITY, Vector2i(0, 1)]
	var mission := _mission([zone])
	assert_eq(MissionBoardReach.error(mission, _map(WALLED), unit_db), "")


func test_a_zone_with_no_reachable_cell_is_refused() -> void:
	var zone := ReachCellObjective.new()
	zone.text = "Move 1 unit to the pass"
	zone.cells = [CITY, Vector2i(2, 1)]
	var mission := _mission([zone])
	assert_eq(
		MissionBoardReach.error(mission, _map(WALLED), unit_db),
		_refusal("Move 1 unit to the pass", CITY)
	)


func test_a_bonus_objective_is_asked_too() -> void:
	var mission := _mission([_capture(Vector2i(0, 1))], [_capture(CITY)])
	assert_ne(MissionBoardReach.error(mission, _map(WALLED), unit_db), "")


func test_a_hidden_objective_is_not_asked() -> void:
	var mission := _mission([_capture(Vector2i(0, 1))], [_capture(CITY, true)])
	assert_eq(MissionBoardReach.error(mission, _map(WALLED), unit_db), "")


func test_only_the_player_army_counts_as_a_source() -> void:
	var mission := _mission([_capture(CITY)])
	assert_ne(MissionBoardReach.error(mission, _map(WALLED + "2 h 2 1\n"), unit_db), "")


func test_every_shipped_mission_can_reach_its_own_objectives() -> void:
	var db := CampaignDB.load_default()
	assert_gt(db.size(), 0, "data/campaigns/ holds no campaign")
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			var map := MapData.parse(FileAccess.get_file_as_string(mission.map_path), terrain_db)
			assert_not_null(map, "%s/%s: board does not parse" % [campaign.id, mission.id])
			if map == null:
				continue
			assert_eq(
				MissionBoardReach.error(mission, map, unit_db),
				"",
				"%s/%s" % [campaign.id, mission.id]
			)
