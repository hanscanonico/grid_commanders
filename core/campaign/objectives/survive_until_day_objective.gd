class_name SurviveUntilDayObjective
extends MissionObjective
## Still standing when the given day begins — the hold objective, and the shape
## every fighting retreat is written in.
##
## Deliberately asks only about the calendar. Being routed is not this
## objective's business: a rout is already a tactical defeat and the runtime's
## precedence resolves it first, so an objective that also re-checked for units
## would be a second opinion about losing.
##
## "Survive until day 8" means the player must reach the **start** of day 8,
## which gives the opponent their full day-7 turn. That reading is the one the
## briefing copy has to match, so it is stated here rather than in the copy.

@export var day: int = 7


func is_met(state: GameState, _team: int) -> bool:
	return state.day >= day


func definition_error(_map: MapData, _team: int) -> String:
	if day <= 1:
		return "survival objective ends on day %d, which is already true at the opening" % day
	return ""
