extends GutTest
## The mission runtime's verdict, and above all its **precedence**.
##
## Two conditions can be true on the same board — the deadline passes on the
## turn the last relay falls — and without a stated order the mission ends
## differently depending on which list happened to be read first. The ordering
## cases below are the ones that would silently flip; the rest of the file is
## the ordinary readings that make them meaningful.

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
## None of this file's conditions reads the tally; a fresh one stands in for the
## live one every verdict is taken with.
var _tally: MissionProgress


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	_tally = MissionProgress.new()


func _state() -> GameState:
	var map := MapData.parse(ROW, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return state


func _capture(cell: Vector2i, text: String = "Take the relay") -> CaptureCellObjective:
	var objective := CaptureCellObjective.new()
	objective.cell = cell
	objective.text = text
	return objective


func _deadline(last_day: int) -> DayDeadlineObjective:
	var objective := DayDeadlineObjective.new()
	objective.last_day = last_day
	objective.text = "The relay went dark on day %d." % (last_day + 1)
	return objective


func _mission(objectives: Array = [], failures: Array = []) -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.id = &"probe"
	mission.player_team = 1
	mission.ai_teams = [2]
	for objective: MissionObjective in objectives:
		mission.objectives.append(objective)
	for failure: MissionObjective in failures:
		mission.failures.append(failure)
	return mission


# --- the ordinary readings --------------------------------------------------


func test_a_mission_runs_until_something_decides_it() -> void:
	var runtime := MissionRuntime.new(_mission([_capture(Vector2i(1, 0))]))
	var outcome := runtime.evaluate(_state(), _tally)
	assert_eq(outcome.status, MissionRuntime.Status.RUNNING)
	assert_false(outcome.is_over())


func test_meeting_every_objective_wins_it() -> void:
	var state := _state()
	var runtime := MissionRuntime.new(_mission([_capture(Vector2i(1, 0))]))
	state.set_owner(Vector2i(1, 0), 1)
	assert_eq(runtime.evaluate(state, _tally).status, MissionRuntime.Status.SUCCESS)


func test_every_objective_must_be_met_at_once() -> void:
	var state := _state()
	var runtime := MissionRuntime.new(
		_mission([_capture(Vector2i(1, 0)), _capture(Vector2i(2, 0))])
	)
	state.set_owner(Vector2i(1, 0), 1)
	assert_eq(runtime.evaluate(state, _tally).status, MissionRuntime.Status.RUNNING, "one of two")
	state.set_owner(Vector2i(2, 0), 1)
	assert_eq(runtime.evaluate(state, _tally).status, MissionRuntime.Status.SUCCESS)


func test_routing_the_enemy_wins_a_mission_whose_objectives_are_unmet() -> void:
	var state := _state()
	var runtime := MissionRuntime.new(_mission([_capture(Vector2i(1, 0))]))
	state.winner = 1
	var outcome := runtime.evaluate(state, _tally)
	assert_eq(outcome.status, MissionRuntime.Status.SUCCESS)
	assert_eq(outcome.reason, "The enemy army was broken.")


func test_a_mission_with_no_objectives_is_not_won_by_vacuous_truth() -> void:
	# "All of nothing is true" would end such a mission on its first command.
	var runtime := MissionRuntime.new(_mission([], [_deadline(6)]))
	assert_eq(runtime.evaluate(_state(), _tally).status, MissionRuntime.Status.RUNNING)


func test_losing_tactically_fails_it() -> void:
	var state := _state()
	var runtime := MissionRuntime.new(_mission([_capture(Vector2i(1, 0))]))
	state.winner = 2
	assert_eq(runtime.evaluate(state, _tally).status, MissionRuntime.Status.FAILURE)


func test_a_failure_condition_fails_it() -> void:
	var state := _state()
	var runtime := MissionRuntime.new(_mission([_capture(Vector2i(1, 0))], [_deadline(6)]))
	state.day = 7
	var outcome := runtime.evaluate(state, _tally)
	assert_eq(outcome.status, MissionRuntime.Status.FAILURE)
	assert_eq(
		outcome.reason, "The relay went dark on day 7.", "the debrief says which clock ran out"
	)


# --- precedence: the cases that would silently flip --------------------------


func test_the_deadline_outranks_the_objectives_met_on_the_same_board() -> void:
	# Both true at once. Losing has to win, or a mission is completed on the turn
	# it expired and the deadline means nothing.
	var state := _state()
	var runtime := MissionRuntime.new(_mission([_capture(Vector2i(1, 0))], [_deadline(6)]))
	state.set_owner(Vector2i(1, 0), 1)
	state.day = 7
	assert_eq(runtime.evaluate(state, _tally).status, MissionRuntime.Status.FAILURE)


func test_being_beaten_outranks_everything() -> void:
	var state := _state()
	var runtime := MissionRuntime.new(_mission([_capture(Vector2i(1, 0))]))
	state.set_owner(Vector2i(1, 0), 1)
	state.winner = 2
	assert_eq(runtime.evaluate(state, _tally).status, MissionRuntime.Status.FAILURE)


func test_an_eliminated_player_has_lost_even_with_no_winner_declared() -> void:
	var state := _state()
	var runtime := MissionRuntime.new(_mission([_capture(Vector2i(1, 0))]))
	state.set_owner(Vector2i(1, 0), 1)
	state.eliminated[1] = true
	assert_eq(runtime.evaluate(state, _tally).status, MissionRuntime.Status.FAILURE)


func test_an_allys_victory_is_ours() -> void:
	var state := _state()
	state.sides[1] = 0
	state.sides[2] = 0
	var runtime := MissionRuntime.new(_mission([_capture(Vector2i(1, 0))]))
	state.winner = 2
	assert_eq(
		runtime.evaluate(state, _tally).status,
		MissionRuntime.Status.SUCCESS,
		"team 2 stands with us, so its victory is not our defeat"
	)


# --- stars ------------------------------------------------------------------


func test_one_star_for_finishing() -> void:
	var state := _state()
	var runtime := MissionRuntime.new(_mission([_capture(Vector2i(1, 0))]))
	state.set_owner(Vector2i(1, 0), 1)
	assert_eq(runtime.evaluate(state, _tally).stars, 1)


func test_a_second_star_for_finishing_inside_par() -> void:
	var state := _state()
	var mission := _mission([_capture(Vector2i(1, 0))])
	mission.par_day = 4
	var runtime := MissionRuntime.new(mission)
	state.set_owner(Vector2i(1, 0), 1)
	state.day = 4
	assert_eq(runtime.evaluate(state, _tally).stars, 2, "day 4 is inside par 4")
	state.day = 5
	assert_eq(runtime.evaluate(state, _tally).stars, 1)


func test_a_star_for_each_bonus_objective_standing_at_the_end() -> void:
	var state := _state()
	var mission := _mission([_capture(Vector2i(1, 0))])
	mission.bonus_objectives.append(_capture(Vector2i(2, 0)))
	var runtime := MissionRuntime.new(mission)
	assert_eq(runtime.max_stars(), 2, "one to finish, one for the bonus")
	state.set_owner(Vector2i(1, 0), 1)
	assert_eq(runtime.evaluate(state, _tally).stars, 1)
	state.set_owner(Vector2i(2, 0), 1)
	assert_eq(runtime.evaluate(state, _tally).stars, 2)


func test_a_failed_mission_earns_nothing() -> void:
	var state := _state()
	var mission := _mission([_capture(Vector2i(1, 0))], [_deadline(6)])
	mission.par_day = 9
	var runtime := MissionRuntime.new(mission)
	state.set_owner(Vector2i(1, 0), 1)
	state.day = 7
	var outcome := runtime.evaluate(state, _tally)
	assert_eq(outcome.stars, 0)
	assert_eq(outcome.awards.size(), 0, "a failure names no star")


func _award_texts(outcome: MissionRuntime.Outcome) -> Array[String]:
	var texts: Array[String] = []
	for award: MissionRuntime.Award in outcome.awards:
		texts.append(award.text)
	return texts


func test_each_star_is_named_and_says_whether_it_was_earned() -> void:
	var state := _state()
	var mission := _mission([_capture(Vector2i(1, 0))])
	mission.par_day = 4
	var runtime := MissionRuntime.new(mission)
	state.set_owner(Vector2i(1, 0), 1)
	state.day = 4
	var inside := runtime.evaluate(state, _tally)
	assert_eq(_award_texts(inside), ["Mission complete", "Finish by day 4"])
	assert_true(inside.awards[1].earned, "day 4 is inside par 4")
	assert_eq(inside.stars, 2)
	assert_eq(inside.day, 4, "the debrief's scoreboard reads the day off the outcome")
	state.day = 5
	var late := runtime.evaluate(state, _tally)
	assert_false(late.awards[1].earned)
	assert_eq(late.stars, 1, "the missed star is still named")
	assert_eq(_award_texts(late), ["Mission complete", "Finish by day 4"])


func test_every_star_a_mission_offers_is_named() -> void:
	var state := _state()
	var mission := _mission([_capture(Vector2i(1, 0))])
	mission.par_day = 4
	mission.bonus_objectives.append(_capture(Vector2i(2, 0), "Hold the depot"))
	var runtime := MissionRuntime.new(mission)
	state.set_owner(Vector2i(1, 0), 1)
	var outcome := runtime.evaluate(state, _tally)
	assert_eq(outcome.awards.size(), runtime.max_stars())
	assert_eq(outcome.awards[2].text, "Hold the depot")
