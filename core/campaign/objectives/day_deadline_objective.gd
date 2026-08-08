class_name DayDeadlineObjective
extends MissionObjective
## The clock a mission runs out of — a **failure** condition, not a goal.
##
## `is_met` answers "has the deadline passed", so the runtime reads it in its
## failure list rather than its success list. It is the one objective whose
## truth is bad news, which is why it is never mixed into `objectives` on a
## MissionDefinition: it lives in `failures`, and the split is what keeps the
## runtime's precedence readable.
##
## "By the end of day 6" means both sides get their whole day-6 turn and the
## mission is lost when the rotation reaches day 7. So the field is the last day
## the player may still be playing on, and the check is strictly greater — the
## briefing copy and this comparison have to agree, so they are stated together.

@export var last_day: int = 6


func is_met(state: GameState, _team: int, _progress: MissionProgress) -> bool:
	return state.day > last_day


func readout(state: GameState, _team: int, _progress: MissionProgress) -> String:
	return "DAY %d/%d" % [state.day, last_day]


func definition_error(_map: MapData, _team: int) -> String:
	if last_day < 1:
		return "deadline ends on day %d, before the match begins" % last_day
	return ""
