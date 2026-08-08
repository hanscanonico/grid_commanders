class_name DayReachedTrigger
extends MissionTrigger
## The calendar has reached a day — the trigger a reinforcement wave, a
## bombardment or a countdown line is written on.
##
## True from the **start** of that day onward, which is the reading
## `SurviveUntilDay` already uses, so a briefing that says "on day 5" means the
## same thing in both places.

@export var day: int = 5


func is_met(state: GameState, _team: int, _progress: MissionProgress) -> bool:
	return state.day >= day


func definition_error(_map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if day < 1:
		return "day-reached trigger waits for day %d, before the match begins" % day
	return ""
