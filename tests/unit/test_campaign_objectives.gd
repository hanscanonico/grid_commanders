extends GutTest
## The objective library: what each condition reads, and the side-awareness that
## is the whole reason it reads it that way.
##
## The side cases are not decoration. Counting a bare *team* is what makes an
## allied mission unwinnable — an ally's property is not capturable, so a target
## your partner takes can never be taken back, and a team-only count would leave
## the objective permanently one short. Every objective here is asked about a
## side through `GameState.allied`, and these tests are what pins that.
##
## Every condition here is asked with a null tally, which is a claim as well as a
## convenience: these four read one board and nothing else. The two that read the
## mission's tally are `test_mission_tallies.gd`'s, and the four that read units
## rather than ground are `test_mission_unit_objectives.gd`'s.

## Two cities and an HQ on one row, so a property can change hands without any
## unit having to walk anywhere.
const ROW := """
[terrain]
CCQ.
[owners]
1 0 0
2 1 0
2 2 0
[units]
1 i 3 0
2 i 1 0
"""

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state(map_text: String = ROW, allies: Array = []) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	for team: int in allies:
		state.sides[team] = 0
	return state


# --- capture a cell ---------------------------------------------------------


func test_capture_cell_is_met_only_while_the_side_holds_the_ground() -> void:
	var state := _state()
	var objective := CaptureCellObjective.new()
	objective.cell = Vector2i(1, 0)
	assert_false(objective.is_met(state, 1, null), "team 2 holds it at the opening")
	state.set_owner(Vector2i(1, 0), 1)
	assert_true(objective.is_met(state, 1, null), "and team 1 has taken it")


func test_capture_cell_counts_an_allys_capture_as_ours() -> void:
	# The Hollow Crown case: a partner takes the objective. Read by team this is
	# a mission that can never be finished, because an ally's property is not a
	# legal capture target and the player can never take it back.
	var state := _state(ROW, [1, 2])
	var objective := CaptureCellObjective.new()
	objective.cell = Vector2i(1, 0)
	assert_true(objective.is_met(state, 1, null), "our side holds it, whichever of us captured it")


func test_capture_cell_is_never_met_by_neutral_ground() -> void:
	var state := _state()
	state.set_owner(Vector2i(1, 0), 0)
	var objective := CaptureCellObjective.new()
	objective.cell = Vector2i(1, 0)
	assert_false(objective.is_met(state, 1, null), "team 0 stands with nobody")


func test_capture_cell_refuses_a_cell_that_is_not_a_property() -> void:
	var map := MapData.parse(ROW, terrain_db)
	var objective := CaptureCellObjective.new()
	objective.cell = Vector2i(3, 0)
	assert_ne(objective.definition_error(map, 1, unit_db), "", "plains is not capturable")
	objective.cell = Vector2i(99, 99)
	assert_ne(objective.definition_error(map, 1, unit_db), "", "and that cell is off the board")
	objective.cell = Vector2i(0, 0)
	assert_eq(objective.definition_error(map, 1, unit_db), "", "a city is fine")


# --- own N properties -------------------------------------------------------


func test_own_properties_counts_the_whole_side() -> void:
	var state := _state(ROW, [1, 2])
	var objective := OwnPropertiesObjective.new()
	objective.count = 3
	assert_true(objective.is_met(state, 1, null), "one of ours plus two of our ally's")


func test_own_properties_counts_only_our_team_when_we_stand_alone() -> void:
	var state := _state()
	var objective := OwnPropertiesObjective.new()
	objective.count = 3
	assert_false(objective.is_met(state, 1, null), "a free-for-all counts team 1's one city")
	objective.count = 1
	assert_true(objective.is_met(state, 1, null))


func test_own_properties_can_ask_for_one_kind_of_ground() -> void:
	var state := _state()
	var objective := OwnPropertiesObjective.new()
	objective.count = 1
	objective.terrain_id = &"hq"
	assert_false(objective.is_met(state, 1, null), "team 1 holds a city, not the HQ")
	state.set_owner(Vector2i(2, 0), 1)
	assert_true(objective.is_met(state, 1, null))


func test_own_properties_refuses_a_count_the_board_cannot_reach() -> void:
	var map := MapData.parse(ROW, terrain_db)
	var objective := OwnPropertiesObjective.new()
	objective.count = 9
	assert_ne(objective.definition_error(map, 1, unit_db), "", "the board has three properties")
	objective.count = 3
	assert_eq(objective.definition_error(map, 1, unit_db), "")


# --- survive / deadline -----------------------------------------------------


func test_survive_until_day_reads_the_calendar_only() -> void:
	var state := _state()
	var objective := SurviveUntilDayObjective.new()
	objective.day = 4
	assert_false(objective.is_met(state, 1, null))
	state.day = 4
	assert_true(objective.is_met(state, 1, null), "the start of day 4 is reaching day 4")


func test_day_deadline_fires_the_day_after_the_last_playable_one() -> void:
	var state := _state()
	var objective := DayDeadlineObjective.new()
	objective.last_day = 6
	state.day = 6
	assert_false(objective.is_met(state, 1, null), "day 6 is still the player's to use")
	state.day = 7
	assert_true(objective.is_met(state, 1, null), "and day 7 is the deadline having passed")


# --- an ally survives -------------------------------------------------------


func test_ally_survives_reads_the_modelled_elimination() -> void:
	var state := _state()
	var objective := AllySurvivesObjective.new()
	objective.team = 2
	assert_true(objective.is_met(state, 1, null))
	state.eliminate(2)
	assert_false(objective.is_met(state, 1, null))


func test_ally_survives_refuses_an_army_the_board_never_seats() -> void:
	var map := MapData.parse(ROW, terrain_db)
	var objective := AllySurvivesObjective.new()
	objective.team = 4
	assert_ne(objective.definition_error(map, 1, unit_db), "")
	objective.team = 2
	assert_eq(objective.definition_error(map, 1, unit_db), "")


# --- the squares the board marks --------------------------------------------


func test_the_cell_objectives_report_the_ground_they_name() -> void:
	# What the board rings is the objective's own authored cell, so the mark and
	# the words can never point at different squares.
	var capture := CaptureCellObjective.new()
	capture.cell = Vector2i(1, 0)
	assert_eq(capture.marker_cells(), [Vector2i(1, 0)], "the capture target")
	var hold := HoldCellObjective.new()
	hold.cell = Vector2i(2, 0)
	assert_eq(hold.marker_cells(), [Vector2i(2, 0)], "the ground to hold")
	var reach := ReachCellObjective.new()
	reach.cells = [Vector2i(0, 0), Vector2i(3, 0)]
	assert_eq(reach.marker_cells(), reach.cells, "every cell of the exit zone")


func test_an_objective_about_a_count_names_no_ground() -> void:
	# A property count, a deadline and a survival clause are about the whole
	# board, so marking a square for them would point the player at nothing.
	for objective: MissionObjective in [
		OwnPropertiesObjective.new(),
		DayDeadlineObjective.new(),
		SurviveUntilDayObjective.new(),
		LossLimitObjective.new(),
	]:
		assert_eq(objective.marker_cells(), [], "%s marks nothing" % objective.get_class())
