class_name MissionRuntime
extends RefCounted
## Asks a committed board whether the mission is over, and how.
##
## Pure and Node-free: it observes, it never instruments. Nothing under `core/`
## or `ai/` gained a hook for this — `evaluate` is handed a `GameState` that a
## command has already been applied to, and everything it reads is an authority
## that already existed (`winner`, `winners`, `day`, `owner_at`, `allied`,
## `is_eliminated`). It is called from the one seam the live scene already has,
## `BattleCommandPipeline`, rather than from the dozen places a command lands.
##
## **The precedence is the whole class.** Two conditions can be true on the same
## board — the deadline passes on the turn the last relay falls — and without a
## stated order that mission ends differently depending on which list happened
## to be checked first. Losing outranks winning throughout, because a mission
## the player survived by a hair should not also be a mission they lost by one.

enum Status { RUNNING, SUCCESS, FAILURE }


## The verdict on one board, with the reason kept so the debrief can say it.
class Outcome:
	extends RefCounted

	var status: MissionRuntime.Status = MissionRuntime.Status.RUNNING
	## Which condition decided it, for the debrief line. Empty while running.
	var reason: String = ""
	## Stars earned, once the mission is over. Always 0 on a failure.
	var stars: int = 0

	func _init(
		p_status: MissionRuntime.Status = MissionRuntime.Status.RUNNING,
		p_reason: String = "",
		p_stars: int = 0
	) -> void:
		status = p_status
		reason = p_reason
		stars = p_stars

	func is_over() -> bool:
		return status != MissionRuntime.Status.RUNNING


var _mission: MissionDefinition


func _init(mission: MissionDefinition) -> void:
	_mission = mission


## The verdict on the board as it now stands, plus the mission's tally for the
## two conditions a board cannot answer alone. Read-only in both: this class
## decides, and `MissionProgress` is advanced by its one writer before we are
## asked.
##
## Order, and why each step outranks the next:
##   1. The player was beaten — routed, or their HQ taken. A tactical defeat is
##      final whatever else is true, and it is the only step that can fire while
##      the objectives are already satisfied.
##   2. A failure condition fired — the deadline, a lost ally. Explicit defeat
##      before any success, so a mission cannot be won on the turn it was lost.
##   3. The player won tactically. Routing the enemy ends a mission whose
##      objectives are still unmet, because there is nobody left to contest them.
##   4. Every objective is satisfied.
##   5. Otherwise it is still being played.
func evaluate(state: GameState, progress: MissionProgress) -> Outcome:
	var team := _mission.player_team
	if state.winner != 0 and not state.allied(state.winner, team):
		return Outcome.new(Status.FAILURE, "Your army was destroyed.")
	if state.is_eliminated(team):
		return Outcome.new(Status.FAILURE, "Your army was destroyed.")
	for failure: MissionObjective in _mission.failures:
		if failure != null and failure.is_met(state, team, progress):
			return Outcome.new(Status.FAILURE, failure.text)
	if state.winner != 0 and state.allied(state.winner, team):
		return Outcome.new(Status.SUCCESS, "The enemy army was broken.", _stars(state, progress))
	if _objectives_met(state, progress):
		return Outcome.new(Status.SUCCESS, _mission_summary(), _stars(state, progress))
	return Outcome.new()


## Whether every required objective is satisfied. A mission with no objectives
## is never won this way — it is won tactically, which step 3 already covers, so
## an empty list must not read as "all of nothing is true".
func _objectives_met(state: GameState, progress: MissionProgress) -> bool:
	if _mission.objectives.is_empty():
		return false
	for objective: MissionObjective in _mission.objectives:
		if objective == null or not objective.is_met(state, _mission.player_team, progress):
			return false
	return true


## One star for finishing, one for finishing inside par, one for every bonus
## objective standing at the end. Deliberately countable by the player: no
## hidden score, and each star names the thing it was for.
func _stars(state: GameState, progress: MissionProgress) -> int:
	var stars := 1
	if _mission.par_day > 0 and state.day <= _mission.par_day:
		stars += 1
	for bonus: MissionObjective in _mission.bonus_objectives:
		if bonus != null and bonus.is_met(state, _mission.player_team, progress):
			stars += 1
	return stars


## The most specific thing we can say about why the mission was won, which is
## the last objective's own words when there is exactly one of them.
func _mission_summary() -> String:
	if _mission.objectives.size() == 1 and _mission.objectives[0] != null:
		return _mission.objectives[0].text
	return "Every objective is complete."


## The stars this mission could award at most, for the hub's "2 / 3" line.
func max_stars() -> int:
	return 1 + (1 if _mission.par_day > 0 else 0) + _mission.bonus_objectives.size()
