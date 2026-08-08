class_name LossLimitObjective
extends MissionObjective
## The butcher's bill a mission may be finished with — a **failure** condition,
## authored in `failures` the way the deadline is, so `is_met` answers "has the
## bill been paid" and its truth is bad news.
##
## `max_losses` is the most the player's side may lose and still be playing, so
## the comparison is strictly greater; the briefing copy and it have to agree, so
## they are stated together.
##
## The count is the mission's tally's (`MissionProgress.losses`), which is the
## only place it can come from: a board says what is standing on it, and a unit
## built after a unit died leaves that number where it was.

@export var max_losses: int = 2


func is_met(_state: GameState, _team: int, progress: MissionProgress) -> bool:
	return progress.losses() > max_losses


func readout(_state: GameState, _team: int, progress: MissionProgress) -> String:
	return "%d/%d LOST" % [progress.losses(), max_losses]


func definition_error(_map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if max_losses < 0:
		return "loss limit allows %d losses" % max_losses
	return ""
