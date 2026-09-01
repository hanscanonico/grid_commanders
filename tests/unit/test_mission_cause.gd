extends GutTest
## Which way a mission was lost. `MissionRuntime.Status` reads a rout and a
## captured headquarters the same; `Outcome.cause` is what lets a defeat line
## say which, and `failure_index` which of the mission's own conditions fired.
##
## The precedence itself is `test_mission_runtime.gd`'s. This file only asks
## that each ending names itself.

## Both armies keep a headquarters, so a capture can fell team 1 through its
## home square and a rout can fell it with the square untouched.
const ROW := """
[terrain]
QCQ.
[owners]
1 0 0
2 2 0
[units]
1 i 3 0
2 i 1 0
"""

var _tally: MissionProgress


func before_each() -> void:
	_tally = MissionProgress.new()


func _state() -> GameState:
	var state := Fixture.state(ROW)
	assert_not_null(state)
	return state


func _capture(cell: Vector2i) -> CaptureCellObjective:
	var objective := CaptureCellObjective.new()
	objective.cell = cell
	objective.text = "Take the city"
	return objective


func _deadline(last_day: int) -> DayDeadlineObjective:
	var objective := DayDeadlineObjective.new()
	objective.last_day = last_day
	objective.text = "The relay went dark on day %d." % (last_day + 1)
	return objective


func _mission(failures: Array = []) -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.id = &"probe"
	mission.player_team = 1
	mission.ai_teams = [2]
	mission.objectives.append(_capture(Vector2i(1, 0)))
	for failure: MissionObjective in failures:
		mission.failures.append(failure)
	return mission


## The enemy infantry walks onto team 1's headquarters and finishes the capture
## the way the live game does it: the square changes hands, then the seat falls.
func test_a_captured_headquarters_names_itself() -> void:
	var state := _state()
	var hq: Vector2i = state.home_hq[1]
	state.capture_progress[hq] = 1
	state.current_team = 2
	var path := Fixture.path([Vector2i(1, 0), Vector2i(0, 0)])
	var command := CaptureCommand.new(state.unit_at(Vector2i(1, 0)), path)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(state.is_eliminated(1), "the fixture really fells the seat")
	var outcome := MissionRuntime.new(_mission()).evaluate(state, _tally)
	assert_eq(outcome.status, MissionRuntime.Status.FAILURE)
	assert_eq(outcome.cause, MissionRuntime.Cause.HQ_TAKEN)
	assert_eq(outcome.reason, "Your headquarters fell.")
	assert_eq(outcome.failure_index, 0)


func test_a_routed_army_names_itself() -> void:
	var state := _state()
	state.eliminate(1)
	var outcome := MissionRuntime.new(_mission()).evaluate(state, _tally)
	assert_eq(outcome.status, MissionRuntime.Status.FAILURE)
	assert_eq(outcome.cause, MissionRuntime.Cause.ROUTED)
	assert_eq(outcome.reason, "Your army was destroyed.")


## A rout leaves the fallen army's ground neutral, and neutral is not a captor.
func test_a_rout_that_neutralised_the_headquarters_is_still_a_rout() -> void:
	var state := _state()
	state.eliminate(1)
	assert_eq(state.owner_at(state.home_hq[1]), MapData.NEUTRAL, "the fixture's premise")
	assert_eq(
		MissionRuntime.new(_mission()).evaluate(state, _tally).cause, MissionRuntime.Cause.ROUTED
	)


func test_a_failure_condition_says_which_one_fired() -> void:
	var state := _state()
	var runtime := MissionRuntime.new(_mission([_deadline(9), _deadline(6)]))
	state.day = 7
	var outcome := runtime.evaluate(state, _tally)
	assert_eq(outcome.status, MissionRuntime.Status.FAILURE)
	assert_eq(outcome.cause, MissionRuntime.Cause.FAILURE)
	assert_eq(outcome.failure_index, 2, "1-based into `failures`: the day-6 deadline is second")
	assert_eq(outcome.reason, "The relay went dark on day 7.")


func test_the_first_failure_listed_is_index_one() -> void:
	var state := _state()
	state.day = 7
	var outcome := MissionRuntime.new(_mission([_deadline(6)])).evaluate(state, _tally)
	assert_eq(outcome.failure_index, 1)


func test_a_scripted_bad_ending_names_itself() -> void:
	var ending := EndMissionEffect.new()
	ending.success = false
	ending.reason = "The ruse was discovered."
	var outcome := MissionRuntime.new(_mission()).evaluate(_state(), _tally, ending)
	assert_eq(outcome.status, MissionRuntime.Status.FAILURE)
	assert_eq(outcome.cause, MissionRuntime.Cause.SCRIPTED)
	assert_eq(outcome.failure_index, 0)
	assert_eq(outcome.reason, "The ruse was discovered.")


func test_a_win_and_a_running_mission_have_no_cause() -> void:
	var state := _state()
	var runtime := MissionRuntime.new(_mission())
	assert_eq(runtime.evaluate(state, _tally).cause, MissionRuntime.Cause.NONE, "still running")
	state.set_owner(Vector2i(1, 0), 1)
	var won := runtime.evaluate(state, _tally)
	assert_eq(won.status, MissionRuntime.Status.SUCCESS)
	assert_eq(won.cause, MissionRuntime.Cause.NONE)
	assert_eq(won.failure_index, 0)
