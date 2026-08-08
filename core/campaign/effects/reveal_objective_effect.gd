class_name RevealObjectiveEffect
extends MissionEffect
## Brings a hidden objective out of hiding — the mission finally says what it is
## about.
##
## It changes no board, so `apply` does nothing: what is revealed is the
## mission's own bookkeeping, and a `Command` is handed a board and nothing else.
## `MissionEventCommand` collects the name and the campaign layer — the one
## writer of the tally — records it, at the same boundary the beat fired on.
##
## The objective is named by `MissionObjective.id` rather than held by reference,
## because the revealed set has to survive a save; a reference does not.

@export var objective_id: StringName = &""


func revealed_objective() -> StringName:
	return objective_id


func definition_error(_map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if objective_id == &"":
		return "reveal names no objective"
	return ""
