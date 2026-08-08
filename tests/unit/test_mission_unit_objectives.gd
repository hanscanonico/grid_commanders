extends GutTest
## The four conditions that read units rather than ground: destroy one, protect
## one, get some of ours onto named cells, break one army.
##
## Split from `test_campaign_objectives.gd` because that suite is at the public
## method ceiling, and split along the line the objectives themselves fall on:
## everything here is answered by one board, while the two tallied conditions are
## `test_mission_tallies.gd`'s.
##
## The side reading is what these pin hardest. `ReachCell` counts the player's
## **side**, so an ally standing in the exit zone has got there for both of you;
## `DefeatTeam` is the one deliberate exception in the whole library and names a
## single army, which is why its own test says so.

## Four cells of open ground under a row of properties, two named units, and a
## third army so an ally has somebody to be.
const BOARD := """
[terrain]
CCQ.
....
[units]
1 i 3 0 relay
2 i 1 0 draeg_gun
3 i 0 1
"""


## A board of ground no move class has a cost for. No shipped terrain is like
## this — every one of them is at least flyable — so the zone guard is checked
## against the case it exists for rather than against a terrain id.
class SealedMap:
	extends MapData

	func _init() -> void:
		width = 4
		height = 2

	func terrain_at(cell: Vector2i) -> TerrainType:
		if not in_bounds(cell):
			return null
		var wall := TerrainType.new()
		wall.id = &"wall"
		return wall


var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _map() -> MapData:
	return MapData.parse(BOARD, terrain_db)


func _state(allies: Array = []) -> GameState:
	var state := GameState.create(_map(), unit_db, chart)
	assert_not_null(state)
	for team: int in allies:
		state.sides[team] = 0
	return state


func _tagged(state: GameState, tag: StringName) -> Unit:
	var unit := MissionObjective.tagged_unit(state, tag)
	assert_not_null(unit, "the fixture names '%s'" % tag)
	return unit


func _zone(cells: Array[Vector2i], count: int) -> ReachCellObjective:
	var objective := ReachCellObjective.new()
	objective.cells = cells
	objective.count = count
	return objective


# --- destroy a named unit ---------------------------------------------------


func test_destroy_unit_is_met_once_the_named_unit_is_off_the_board() -> void:
	var state := _state()
	var objective := DestroyUnitObjective.new()
	objective.tag = &"draeg_gun"
	assert_false(objective.is_met(state, 1, null), "the gun is still standing")
	state.remove_unit(_tagged(state, &"draeg_gun"))
	assert_true(objective.is_met(state, 1, null))


func test_destroy_unit_refuses_a_name_the_board_never_gives() -> void:
	var map := _map()
	var objective := DestroyUnitObjective.new()
	assert_ne(objective.definition_error(map, 1), "", "an unnamed target is no target")
	objective.tag = &"siege_train"
	assert_ne(objective.definition_error(map, 1), "", "and nothing on this board is called that")
	objective.tag = &"draeg_gun"
	assert_eq(objective.definition_error(map, 1), "")


# --- protect a named unit ---------------------------------------------------


func test_protect_unit_fires_when_the_named_unit_falls() -> void:
	# Authored in `failures`, so its truth is the mission being lost.
	var state := _state()
	var objective := ProtectUnitObjective.new()
	objective.tag = &"relay"
	assert_false(objective.is_met(state, 1, null), "nothing has happened to the relay")
	state.remove_unit(_tagged(state, &"relay"))
	assert_true(objective.is_met(state, 1, null))


func test_protect_unit_refuses_a_name_the_board_never_gives() -> void:
	var map := _map()
	var objective := ProtectUnitObjective.new()
	objective.tag = &"the_courier"
	assert_ne(objective.definition_error(map, 1), "")
	objective.tag = &"relay"
	assert_eq(objective.definition_error(map, 1), "")


# --- reach the exit zone ----------------------------------------------------


func test_reach_cell_counts_our_units_standing_on_the_named_ground() -> void:
	var state := _state()
	var objective := _zone([Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i], 1)
	assert_false(objective.is_met(state, 1, null), "nobody is in the zone yet")
	_tagged(state, &"relay").cell = Vector2i(3, 1)
	assert_true(objective.is_met(state, 1, null))


func test_reach_cell_counts_an_allys_arrival_as_ours() -> void:
	# The escort case: the column being evacuated is the ally's. Read by team this
	# is a zone the player can never fill on somebody else's behalf.
	var state := _state([1, 3])
	var objective := _zone([Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i], 2)
	_tagged(state, &"relay").cell = Vector2i(3, 1)
	assert_false(objective.is_met(state, 1, null), "one of the two cells")
	state.units_of(3)[0].cell = Vector2i(2, 1)
	assert_true(objective.is_met(state, 1, null))


func test_reach_cell_never_counts_an_enemy_holding_the_zone() -> void:
	var state := _state()
	var objective := _zone([Vector2i(3, 1)] as Array[Vector2i], 1)
	_tagged(state, &"draeg_gun").cell = Vector2i(3, 1)
	assert_false(objective.is_met(state, 1, null))


func test_reach_cell_refuses_a_zone_that_could_never_be_filled() -> void:
	var map := _map()
	var objective := _zone([Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i], 3)
	assert_ne(objective.definition_error(map, 1), "", "three units onto two cells")
	objective = _zone([Vector2i(2, 1), Vector2i(2, 1)] as Array[Vector2i], 2)
	assert_ne(objective.definition_error(map, 1), "", "one cell named twice is one cell")
	objective = _zone([Vector2i(9, 9)] as Array[Vector2i], 1)
	assert_ne(objective.definition_error(map, 1), "", "and that cell is off the board")
	objective = _zone([Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i], 2)
	assert_eq(objective.definition_error(map, 1), "")


func test_reach_cell_refuses_ground_nothing_could_ever_stand_on() -> void:
	var objective := _zone([Vector2i(1, 1)] as Array[Vector2i], 1)
	assert_ne(objective.definition_error(SealedMap.new(), 1), "", "a zone nothing can enter")
	assert_eq(objective.definition_error(_map(), 1), "", "while open ground is a zone")


# --- break one army ---------------------------------------------------------


func test_defeat_team_reads_one_armys_fall_and_not_its_sides() -> void:
	# The two enemies stand together. Read side-wide this mission would still be
	# running with the army it is about already gone.
	var state := _state([2, 3])
	var objective := DefeatTeamObjective.new()
	objective.team = 2
	assert_false(objective.is_met(state, 1, null))
	state.eliminate(2)
	assert_true(objective.is_met(state, 1, null), "their ally fighting on is not team 2 standing")


func test_defeat_team_refuses_an_army_the_mission_could_not_break() -> void:
	var map := _map()
	var objective := DefeatTeamObjective.new()
	objective.team = 1
	assert_ne(objective.definition_error(map, 1), "", "the player cannot be asked to fall")
	objective.team = 4
	assert_ne(objective.definition_error(map, 1), "", "and this board seats no fourth army")
	objective.team = 2
	assert_eq(objective.definition_error(map, 1), "")
