class_name DestroyUnitObjective
extends MissionObjective
## A named unit must be off the board — "Draeg's siege gun is the mission", not
## the ground it is parked on.
##
## The board is the whole answer: a unit that is gone is gone, whoever took it
## and however — shot, sunk with the transport it rode, or crashed dry. The name
## is `Unit.tag`, which is why this objective could not be written before a board
## could give one (campaign-depth D4); a unit identified by the cell it started
## on stops being identifiable the moment it moves.

## The name the board gave it, on the `[units]` row's fifth column.
@export var tag: StringName = &""


func is_met(state: GameState, _team: int, _progress: MissionProgress) -> bool:
	return tagged_unit(state, tag) == null


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	return MissionBoardCheck.named_unit(map, tag, "destroy objective names")
