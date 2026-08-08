extends GutTest
## The four effects that change no board — the two grants, the reveal and the
## ending — and what the runtime does with the last two.
##
## A grant goes through the authority that already owns the number: a purse can
## never go below zero, and charge is `GameState.add_charge`'s to cap. The other
## two are facts rather than mutations, which is the whole of their design: a
## `Command` is handed a board, so a hidden objective coming out of hiding and a
## mission ending are declared and collected rather than written.

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


func _state(commanders: Dictionary = {}) -> GameState:
	return Fixture.state(FIELD, commanders)


func _map() -> MapData:
	return MapData.parse(FIELD, Fixture.terrain_db())


## A mission on this board, with whatever conditions a case is about.
func _mission(objectives: Array[MissionObjective]) -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.id = &"fixture"
	mission.map_path = "res://maps/fixtures/ridge.txt"
	mission.player_team = 1
	mission.objectives = objectives
	return mission


func _capture(cell: Vector2i, objective_id: StringName = &"") -> CaptureCellObjective:
	var objective := CaptureCellObjective.new()
	objective.cell = cell
	objective.id = objective_id
	objective.hidden = objective_id != &""
	return objective


# --- funds and charge -------------------------------------------------------


func test_funds_grant_adds_to_the_purse_and_a_levy_floors_at_nothing() -> void:
	var state := _state()
	state.funds[2] = 500
	var effect := GrantFundsEffect.new()
	effect.team = 2
	effect.amount = 1500
	effect.apply(state, 1)
	assert_eq(state.funds[2] as int, 2000)
	effect.amount = -9000
	effect.apply(state, 1)
	assert_eq(state.funds[2] as int, 0, "a purse has never gone below nothing")


func test_funds_grant_refuses_a_seat_nobody_is_playing() -> void:
	var effect := GrantFundsEffect.new()
	effect.team = 3
	assert_ne(effect.definition_error(_map(), 1, Fixture.unit_db()), "", "the board seats two")
	effect.team = 2
	effect.amount = 0
	assert_ne(effect.definition_error(_map(), 1, Fixture.unit_db()), "", "and this moves nothing")
	effect.amount = 500
	assert_eq(effect.definition_error(_map(), 1, Fixture.unit_db()), "")
	assert_eq(effect.board_error(_state(), 1), "")


func test_charge_grant_banks_through_the_meters_own_authority() -> void:
	var state := _state({1: &"alina_ward"})
	var effect := GrantChargeEffect.new()
	effect.team = 1
	effect.points = 5000
	effect.apply(state, 1)
	assert_eq(state.commander_state(1).charge, 5000)
	effect.points = 99999
	effect.apply(state, 1)
	var cost := state.commander_of(1).power_cost
	assert_eq(state.commander_state(1).charge, cost, "capped at what the power costs")


func test_charge_grant_banks_nothing_for_a_commander_with_no_power() -> void:
	var state := _state()
	var effect := GrantChargeEffect.new()
	effect.team = 1
	effect.points = 5000
	effect.apply(state, 1)
	assert_eq(state.commander_state(1).charge, 0, "a neutral seat has no meter to fill")


func test_charge_grant_refuses_banking_nothing() -> void:
	var effect := GrantChargeEffect.new()
	effect.team = 1
	effect.points = 0
	assert_ne(effect.definition_error(_map(), 1, Fixture.unit_db()), "")
	effect.points = 500
	assert_eq(effect.definition_error(_map(), 1, Fixture.unit_db()), "")


# --- the two facts ----------------------------------------------------------


func test_reveal_declares_an_objective_and_touches_no_board() -> void:
	var state := _state()
	var before := state.units.size()
	var effect := RevealObjectiveEffect.new()
	effect.objective_id = &"the_real_target"
	effect.apply(state, 1)
	assert_eq(effect.revealed_objective(), &"the_real_target")
	assert_eq(state.units.size(), before, "an effect that reveals moves nothing")
	assert_null(effect.mission_end())


func test_reveal_refuses_naming_nothing() -> void:
	var effect := RevealObjectiveEffect.new()
	assert_ne(effect.definition_error(_map(), 1, Fixture.unit_db()), "")
	effect.objective_id = &"the_real_target"
	assert_eq(effect.definition_error(_map(), 1, Fixture.unit_db()), "")


func test_ending_declares_itself_and_says_why() -> void:
	var effect := EndMissionEffect.new()
	effect.success = true
	effect.reason = "The relief column reached the pass."
	assert_eq(effect.mission_end(), effect, "the fact the runtime reads is the effect itself")
	assert_eq(effect.revealed_objective(), &"")
	effect.reason = ""
	assert_ne(effect.definition_error(_map(), 1, Fixture.unit_db()), "", "an ending says why")


# --- what the runtime does with them ----------------------------------------


func test_a_scripted_ending_wins_the_mission_in_its_own_words() -> void:
	var state := _state()
	var runtime := MissionRuntime.new(_mission([_capture(Vector2i(1, 0))]))
	var progress := MissionProgress.new()
	assert_false(runtime.evaluate(state, progress).is_over(), "nothing has happened yet")
	var ending := EndMissionEffect.new()
	ending.success = true
	ending.reason = "The garrison opened the gate."
	var outcome := runtime.evaluate(state, progress, ending)
	assert_eq(outcome.status, MissionRuntime.Status.SUCCESS)
	assert_eq(outcome.reason, "The garrison opened the gate.")


func test_losing_still_outranks_a_scripted_win() -> void:
	var state := _state()
	state.day = 9
	var deadline := DayDeadlineObjective.new()
	deadline.last_day = 6
	deadline.text = "The deadline passed."
	var mission := _mission([_capture(Vector2i(1, 0))])
	mission.failures = [deadline]
	var ending := EndMissionEffect.new()
	ending.reason = "The garrison opened the gate."
	var outcome := MissionRuntime.new(mission).evaluate(state, MissionProgress.new(), ending)
	assert_eq(outcome.status, MissionRuntime.Status.FAILURE, "the deadline was already gone")
	assert_eq(outcome.reason, "The deadline passed.")


func test_a_hidden_objective_is_not_required_until_it_is_revealed() -> void:
	var state := _state()
	state.set_owner(Vector2i(1, 0), 1)
	var mission := _mission([_capture(Vector2i(1, 0)), _capture(Vector2i(2, 0), &"the_hq")])
	var runtime := MissionRuntime.new(mission)
	var progress := MissionProgress.new()
	var outcome := runtime.evaluate(state, progress)
	assert_eq(outcome.status, MissionRuntime.Status.SUCCESS, "only the live objective is asked")
	progress.reveal(&"the_hq")
	assert_false(runtime.evaluate(state, progress).is_over(), "and now the HQ is the mission")


func test_a_mission_whose_objectives_are_all_hidden_is_not_won_by_default() -> void:
	var state := _state()
	var mission := _mission([_capture(Vector2i(1, 0), &"the_hq")])
	var outcome := MissionRuntime.new(mission).evaluate(state, MissionProgress.new())
	assert_false(outcome.is_over(), "all of nothing must not read as satisfied")


func test_a_hidden_failure_cannot_fire_before_it_is_revealed() -> void:
	var state := _state()
	state.day = 9
	var deadline := DayDeadlineObjective.new()
	deadline.last_day = 6
	deadline.id = &"the_clock"
	deadline.hidden = true
	deadline.text = "The deadline passed."
	var mission := _mission([_capture(Vector2i(1, 0))])
	mission.failures = [deadline]
	var runtime := MissionRuntime.new(mission)
	var progress := MissionProgress.new()
	assert_false(runtime.evaluate(state, progress).is_over(), "nobody has been told about a clock")
	progress.reveal(&"the_clock")
	assert_eq(runtime.evaluate(state, progress).status, MissionRuntime.Status.FAILURE)


func test_a_hidden_bonus_earns_no_star_until_it_is_revealed() -> void:
	var state := _state()
	state.set_owner(Vector2i(1, 0), 1)
	var mission := _mission([_capture(Vector2i(1, 0))])
	mission.bonus_objectives = [_capture(Vector2i(1, 0), &"the_extra")]
	var runtime := MissionRuntime.new(mission)
	var progress := MissionProgress.new()
	assert_eq(runtime.evaluate(state, progress).stars, 1, "one star, for finishing")
	progress.reveal(&"the_extra")
	assert_eq(runtime.evaluate(state, progress).stars, 2)


func test_a_mission_with_nothing_hidden_is_judged_exactly_as_before() -> void:
	var state := _state()
	var mission := _mission([_capture(Vector2i(1, 0))])
	var runtime := MissionRuntime.new(mission)
	assert_false(runtime.evaluate(state, MissionProgress.new()).is_over())
	state.set_owner(Vector2i(1, 0), 1)
	var outcome := runtime.evaluate(state, MissionProgress.new())
	assert_eq(outcome.status, MissionRuntime.Status.SUCCESS)
	assert_eq(outcome.stars, 1)
