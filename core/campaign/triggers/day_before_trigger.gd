class_name DayBeforeTrigger
extends MissionTrigger
## The calendar has not passed a day yet — the clock half of "and you were
## quick about it".
##
## **Only ever meaningful in conjunction.** On its own it is true on day one and
## stays true until it is not, so an event carrying it alone fires at the first
## boundary of the mission and says nothing. It exists because an event's
## triggers are an `and`: `ObjectiveMet` plus this one is "did it, and did it
## fast", which is the shape a bonus beat is written in and is unsayable without
## a condition that can expire.

@export var day: int = 5


func is_met(
	state: GameState, _team: int, _progress: MissionProgress, _ledger: CampaignState = null
) -> bool:
	return state.day <= day


func definition_error(_map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if day < 1:
		return "day-before trigger expires on day %d, before the match begins" % day
	return ""
