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
##
## **Tactical victory outranks the objective list, which is what an author has to
## know**: an objective whose own completion ends the match — the last hostile
## army's home headquarters, or that army itself — is answered at step 4, before
## a single objective is read, so every objective standing beside it is
## decorative. A mission about the enemy's headquarters has exactly one primary
## and states the rest as bonuses. `MissionDefinition.board_error` refuses the
## other shape, because it has no symptom: the mission simply ends with its own
## card half unticked.

enum Status { RUNNING, SUCCESS, FAILURE }
## Which way a mission was lost. `Status` alone reads a rout and a captured
## headquarters the same, and a defeat line wants to say which.
enum Cause { NONE, ROUTED, HQ_TAKEN, FAILURE, SCRIPTED }

## What the star sheet calls a bonus the mission never revealed.
const HIDDEN_AWARD := "Hidden objective"


## One star, named — so the debrief can say what it was for and what was missed.
class Award:
	extends RefCounted

	var text: String = ""
	var earned: bool = false

	func _init(p_text: String = "", p_earned: bool = false) -> void:
		text = p_text
		earned = p_earned


## The verdict on one board, with the reason kept so the debrief can say it.
class Outcome:
	extends RefCounted

	var status: MissionRuntime.Status = MissionRuntime.Status.RUNNING
	## Which condition decided it, for the debrief line. Empty while running.
	var reason: String = ""
	## Stars earned, once the mission is over. Always 0 on a failure.
	var stars: int = 0
	## What each star was for, earned or missed. Empty on a failure.
	var awards: Array[MissionRuntime.Award] = []
	## The day the mission ended on, for the debrief's scoreboard. 0 unless won.
	var day: int = 0
	## How it was lost. NONE while running and on every win.
	var cause: MissionRuntime.Cause = MissionRuntime.Cause.NONE
	## Which failure condition fired, 1-based into the mission's `failures`; 0
	## for every other ending.
	var failure_index: int = 0

	func _init(
		p_status: MissionRuntime.Status = MissionRuntime.Status.RUNNING,
		p_reason: String = "",
		p_stars: int = 0,
		p_awards: Array[MissionRuntime.Award] = [],
		p_day: int = 0
	) -> void:
		status = p_status
		reason = p_reason
		stars = p_stars
		awards = p_awards
		day = p_day

	func is_over() -> bool:
		return status != MissionRuntime.Status.RUNNING


var _mission: MissionDefinition


func _init(mission: MissionDefinition) -> void:
	_mission = mission


## The verdict on the board as it now stands, plus the mission's tally for the
## conditions a board cannot answer alone. Read-only in both: this class decides,
## and `MissionProgress` is advanced by its one writer before we are asked.
##
## `ended` is an `EndMission` effect a scripted beat declared at this same
## boundary, or null on every other board. It is a **fact**, never a second
## verdict authority (campaign-depth D3): it takes its place in the order below
## rather than short-circuiting it, so a scripted victory on the turn the
## deadline expired is still a mission lost.
##
## Order, and why each step outranks the next:
##   1. The player was beaten — routed, or their HQ taken. A tactical defeat is
##      final whatever else is true, and it is the only step that can fire while
##      the objectives are already satisfied.
##   2. A failure condition fired — the deadline, a lost ally. Explicit defeat
##      before any success, so a mission cannot be won on the turn it was lost.
##   3. An event ended it badly, which is a failure condition an author wrote in
##      a different place.
##   4. The player won tactically. Routing the enemy ends a mission whose
##      objectives are still unmet, because there is nobody left to contest them.
##   5. An event ended it well.
##   6. Every objective is satisfied.
##   7. Otherwise it is still being played.
func evaluate(
	state: GameState, progress: MissionProgress, ended: EndMissionEffect = null
) -> Outcome:
	var team := _mission.player_team
	var beaten := state.winner != 0 and not state.allied(state.winner, team)
	if beaten or state.is_eliminated(team):
		return _beaten(state, team)
	for failure: MissionObjective in _live(_mission.failures, progress):
		if failure.is_met(state, team, progress):
			return _lost(failure.text, Cause.FAILURE, _mission.failures.find(failure) + 1)
	if ended != null and not ended.success:
		return _lost(ended.reason, Cause.SCRIPTED)
	if state.winner != 0 and state.allied(state.winner, team):
		return _won("The enemy army was broken.", state, progress)
	if ended != null and ended.success:
		return _won(ended.reason, state, progress)
	if _objectives_met(state, progress):
		return _won(_mission_summary(), state, progress)
	return Outcome.new()


## Beaten on the board, told two ways by who holds the home square: a capture
## hands the headquarters to its captor before the seat falls, and a rout leaves
## a fallen army's ground neutral.
func _beaten(state: GameState, team: int) -> Outcome:
	if state.home_hq.has(team):
		var holder := state.owner_at(state.home_hq[team])
		if holder != team and holder != MapData.NEUTRAL:
			return _lost("Your headquarters fell.", Cause.HQ_TAKEN)
	return _lost("Your army was destroyed.", Cause.ROUTED)


func _lost(reason: String, cause: Cause, failure_index: int = 0) -> Outcome:
	var outcome := Outcome.new(Status.FAILURE, reason)
	outcome.cause = cause
	outcome.failure_index = failure_index
	return outcome


## A mission won, with its stars named and counted.
func _won(reason: String, state: GameState, progress: MissionProgress) -> Outcome:
	var awards := _awards(state, progress)
	var stars := 0
	for award: Award in awards:
		if award.earned:
			stars += 1
	return Outcome.new(Status.SUCCESS, reason, stars, awards, state.day)


## Whether every required objective is satisfied. A mission with no objectives
## is never won this way — it is won tactically, which step 4 already covers, so
## an empty list must not read as "all of nothing is true". A mission whose
## objectives are all still hidden reads the same way, and for the same reason.
func _objectives_met(state: GameState, progress: MissionProgress) -> bool:
	var live := _live(_mission.objectives, progress)
	if live.is_empty():
		return false
	for objective: MissionObjective in live:
		if not objective.is_met(state, _mission.player_team, progress):
			return false
	return true


## The conditions in a list that are actually being judged: an empty slot is not
## one, and neither is a hidden objective no event has revealed yet.
static func _live(
	objectives: Array[MissionObjective], progress: MissionProgress
) -> Array[MissionObjective]:
	var live: Array[MissionObjective] = []
	for objective: MissionObjective in objectives:
		if objective != null and objective.is_live(progress):
			live.append(objective)
	return live


## One star for finishing, one for finishing inside par, one for every bonus
## objective — each of them named, earned or missed, so the debrief can say what
## it scored and what it did not. A bonus no event revealed is still a star
## `max_stars` counts, so it is named as the hidden one it stayed rather than
## left as a nameless gap: `awards.size()` always equals `max_stars()`.
func _awards(state: GameState, progress: MissionProgress) -> Array[Award]:
	var awards: Array[Award] = [Award.new("Mission complete", true)]
	if _mission.par_day > 0:
		awards.append(
			Award.new("Finish by day %d" % _mission.par_day, state.day <= _mission.par_day)
		)
	for bonus: MissionObjective in _live(_mission.bonus_objectives, progress):
		awards.append(Award.new(bonus.text, bonus.is_met(state, _mission.player_team, progress)))
	for bonus: MissionObjective in _mission.bonus_objectives:
		if bonus != null and not bonus.is_live(progress):
			awards.append(Award.new(HIDDEN_AWARD, false))
	return awards


## The most specific thing we can say about why the mission was won, which is
## the last objective's own words when there is exactly one of them.
func _mission_summary() -> String:
	if _mission.objectives.size() == 1 and _mission.objectives[0] != null:
		return _mission.objectives[0].text
	return "Every objective is complete."


## The stars this mission could award at most, for the hub's "2 / 3" line.
func max_stars() -> int:
	return 1 + (1 if _mission.par_day > 0 else 0) + _mission.bonus_objectives.size()
