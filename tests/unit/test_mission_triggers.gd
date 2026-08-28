extends GutTest
## The trigger library: what each condition reads off a committed board, and the
## side-awareness it reads it with.
##
## A trigger is `MissionObjective.is_met`'s contract in a second place
## (campaign-depth D2) — a pure read, through authorities that already exist —
## so these pin the same two things the objective suite does: the answer, and
## that ground and armies are counted by **side** rather than by team.
##
## The conjunction the triggers are combined under is `MissionEvent`'s, and so is
## `test_mission_events.gd`'s.
##
## Every rejection asserts the exact reason string: a bare `assert_ne(error, "")`
## passes on any refusal, so a branch that started answering with its neighbour's
## message would have kept the suite green.

## Two cities, an HQ, a base and four named units, so every trigger here has
## something on the board to name.
const FIELD := """
[terrain]
CCQ...
....BF
[owners]
1 0 0
2 1 0
2 2 0
1 4 1
[units]
1 i 3 0 courier
2 t 4 0 siege_gun
2 i 5 0 garrison
1 p 3 1 truck
"""


func _state(allies: Array = []) -> GameState:
	var state := Fixture.state(FIELD)
	for team: int in allies:
		state.sides[team] = 0
	return state


func _map() -> MapData:
	return MapData.parse(FIELD, Fixture.terrain_db())


# --- the calendar -----------------------------------------------------------


func test_day_reached_is_true_from_the_start_of_that_day() -> void:
	var state := _state()
	var trigger := DayReachedTrigger.new()
	trigger.day = 3
	assert_false(trigger.is_met(state, 1, null), "day 1 has not reached day 3")
	state.day = 3
	assert_true(trigger.is_met(state, 1, null), "the start of day 3 is reaching day 3")
	state.day = 4
	assert_true(trigger.is_met(state, 1, null), "and it stays true afterwards")


func test_day_before_expires_and_is_only_useful_in_conjunction() -> void:
	var state := _state()
	var trigger := DayBeforeTrigger.new()
	trigger.day = 3
	assert_true(trigger.is_met(state, 1, null), "true on day 1, which is why it is never alone")
	state.day = 3
	assert_true(trigger.is_met(state, 1, null), "day 3 is still inside 'by day 3'")
	state.day = 4
	assert_false(trigger.is_met(state, 1, null), "and day 4 is it having expired")


func test_the_calendar_triggers_refuse_a_day_before_the_match() -> void:
	var reached := DayReachedTrigger.new()
	reached.day = 0
	assert_eq(
		reached.definition_error(_map(), 1, Fixture.unit_db()),
		"day-reached trigger waits for day 0, before the match begins"
	)
	var before := DayBeforeTrigger.new()
	before.day = 0
	assert_eq(
		before.definition_error(_map(), 1, Fixture.unit_db()),
		"day-before trigger expires on day 0, before the match begins"
	)


# --- ground -----------------------------------------------------------------


func test_cell_owned_reads_the_three_states_by_side() -> void:
	var state := _state()
	var trigger := CellOwnedTrigger.new()
	trigger.cell = Vector2i(1, 0)
	trigger.holder = CellOwnedTrigger.Holder.ENEMY
	assert_true(trigger.is_met(state, 1, null), "team 2 holds it")
	trigger.holder = CellOwnedTrigger.Holder.OURS
	assert_false(trigger.is_met(state, 1, null))
	state.set_owner(Vector2i(1, 0), 1)
	assert_true(trigger.is_met(state, 1, null), "and now we do")
	trigger.holder = CellOwnedTrigger.Holder.NEUTRAL
	state.set_owner(Vector2i(1, 0), 0)
	assert_true(trigger.is_met(state, 1, null), "team 0 stands with nobody")


func test_cell_owned_counts_an_allys_ground_as_ours() -> void:
	var state := _state([1, 2])
	var trigger := CellOwnedTrigger.new()
	trigger.cell = Vector2i(1, 0)
	trigger.holder = CellOwnedTrigger.Holder.OURS
	assert_true(trigger.is_met(state, 1, null), "our side holds it, whichever of us took it")
	trigger.holder = CellOwnedTrigger.Holder.ENEMY
	assert_false(trigger.is_met(state, 1, null), "an ally is not an enemy")


func test_cell_owned_refuses_ground_that_cannot_change_hands() -> void:
	var trigger := CellOwnedTrigger.new()
	trigger.cell = Vector2i(3, 0)
	assert_ne(trigger.definition_error(_map(), 1, Fixture.unit_db()), "", "plains has no owner")
	trigger.cell = Vector2i(99, 99)
	assert_ne(
		trigger.definition_error(_map(), 1, Fixture.unit_db()), "", "and that is off the board"
	)
	trigger.cell = Vector2i(0, 0)
	assert_eq(trigger.definition_error(_map(), 1, Fixture.unit_db()), "", "a city is fine")


# --- named units ------------------------------------------------------------


func test_unit_destroyed_fires_once_the_tag_has_left_the_board() -> void:
	var state := _state()
	var trigger := UnitDestroyedTrigger.new()
	trigger.tag = &"siege_gun"
	assert_false(trigger.is_met(state, 1, null))
	state.remove_unit(MissionObjective.tagged_unit(state, &"siege_gun"))
	assert_true(trigger.is_met(state, 1, null))


func test_unit_destroyed_refuses_a_name_the_board_never_gave() -> void:
	var trigger := UnitDestroyedTrigger.new()
	assert_eq(
		trigger.definition_error(_map(), 1, Fixture.unit_db()),
		"unit-destroyed trigger names no unit"
	)
	trigger.tag = &"nobody"
	assert_eq(
		trigger.definition_error(_map(), 1, Fixture.unit_db()),
		"unit-destroyed trigger names 'nobody', which no unit on this board carries"
	)
	trigger.tag = &"siege_gun"
	assert_eq(trigger.definition_error(_map(), 1, Fixture.unit_db()), "")


func test_unit_reached_fires_only_on_the_named_ground() -> void:
	var state := _state()
	var trigger := UnitReachedTrigger.new()
	trigger.tag = &"courier"
	trigger.cells = [Vector2i(5, 1), Vector2i(0, 1)]
	assert_false(trigger.is_met(state, 1, null), "the courier is standing at 3,0")
	MissionObjective.tagged_unit(state, &"courier").cell = Vector2i(0, 1)
	assert_true(trigger.is_met(state, 1, null))


func test_unit_reached_says_a_passenger_has_arrived_nowhere() -> void:
	var state := _state()
	var courier := MissionObjective.tagged_unit(state, &"courier")
	courier.cell = Vector2i(3, 1)
	courier.carrier = MissionObjective.tagged_unit(state, &"truck")
	var trigger := UnitReachedTrigger.new()
	trigger.tag = &"courier"
	trigger.cells = [Vector2i(3, 1)]
	assert_false(trigger.is_met(state, 1, null), "it rides until the truck sets it down")


func test_unit_reached_refuses_a_trigger_that_names_no_unit() -> void:
	var trigger := UnitReachedTrigger.new()
	trigger.cells = [Vector2i(0, 1)]
	assert_eq(
		trigger.definition_error(_map(), 1, Fixture.unit_db()), "unit-reached trigger names no unit"
	)


func test_unit_reached_refuses_a_name_the_board_never_gave() -> void:
	var trigger := UnitReachedTrigger.new()
	trigger.tag = &"nobody"
	trigger.cells = [Vector2i(0, 1)]
	assert_eq(
		trigger.definition_error(_map(), 1, Fixture.unit_db()),
		"unit-reached trigger names 'nobody', which no unit on this board carries"
	)


func test_unit_reached_refuses_ground_the_board_does_not_hold() -> void:
	var trigger := UnitReachedTrigger.new()
	trigger.tag = &"courier"
	assert_eq(
		trigger.definition_error(_map(), 1, Fixture.unit_db()),
		"unit-reached trigger names no ground for 'courier' to reach"
	)
	trigger.cells = [Vector2i(99, 0)]
	assert_eq(
		trigger.definition_error(_map(), 1, Fixture.unit_db()),
		"unit-reached trigger names (99, 0), off a 6x2 board"
	)
	trigger.cells = [Vector2i(0, 1)]
	assert_eq(trigger.definition_error(_map(), 1, Fixture.unit_db()), "")


# --- force ------------------------------------------------------------------


func test_force_strength_counts_the_whole_side() -> void:
	var trigger := ForceStrengthTrigger.new()
	trigger.team = 2
	trigger.bound = ForceStrengthTrigger.Bound.AT_MOST
	trigger.count = 2
	assert_true(trigger.is_met(_state(), 1, null), "army 2 fields exactly two")
	trigger.count = 1
	assert_false(trigger.is_met(_state(), 1, null))
	trigger.count = 2
	assert_false(trigger.is_met(_state([1, 2]), 1, null), "the alliance fields four, not two")


func test_force_strength_answers_upward_as_well() -> void:
	var state := _state()
	var trigger := ForceStrengthTrigger.new()
	trigger.team = 2
	trigger.bound = ForceStrengthTrigger.Bound.AT_LEAST
	trigger.count = 3
	assert_false(trigger.is_met(state, 1, null))
	state.units.append(Unit.create(Fixture.unit_db().by_symbol("i"), 2, Vector2i(0, 1)))
	assert_true(trigger.is_met(state, 1, null), "a third unit reaches the mark")


func test_force_strength_refuses_an_army_the_board_never_seats() -> void:
	var trigger := ForceStrengthTrigger.new()
	trigger.team = 4
	assert_eq(
		trigger.definition_error(_map(), 1, Fixture.unit_db()),
		"force-strength trigger names army 4, which this board does not seat"
	)
	trigger.team = 2
	assert_eq(trigger.definition_error(_map(), 1, Fixture.unit_db()), "")


# --- the bridge to the objective library ------------------------------------


func test_objective_met_asks_the_condition_it_watches() -> void:
	var state := _state()
	var objective := CaptureCellObjective.new()
	objective.cell = Vector2i(1, 0)
	var trigger := ObjectiveMetTrigger.new()
	trigger.objective = objective
	assert_false(trigger.is_met(state, 1, null), "team 2 holds it")
	state.set_owner(Vector2i(1, 0), 1)
	assert_true(trigger.is_met(state, 1, null), "the condition is the trigger")


func test_objective_met_refuses_watching_nothing_or_the_impossible() -> void:
	var trigger := ObjectiveMetTrigger.new()
	assert_ne(trigger.definition_error(_map(), 1, Fixture.unit_db()), "", "it watches nothing")
	var objective := CaptureCellObjective.new()
	objective.cell = Vector2i(3, 0)
	trigger.objective = objective
	assert_ne(
		trigger.definition_error(_map(), 1, Fixture.unit_db()), "", "plains is not a property"
	)
	objective.cell = Vector2i(0, 0)
	assert_eq(trigger.definition_error(_map(), 1, Fixture.unit_db()), "")
