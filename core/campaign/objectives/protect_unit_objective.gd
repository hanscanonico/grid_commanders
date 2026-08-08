class_name ProtectUnitObjective
extends MissionObjective
## A named unit must still be standing — "the marshal must survive" — and, like
## the deadline, it is authored in `failures`: `is_met` answers "has it fallen",
## so it is the one kind of objective whose truth is bad news.
##
## It reads the same board fact `DestroyUnit` does, from the other list, and is a
## class of its own for the reason `DayDeadline` is one beside `SurviveUntilDay`:
## the runtime never negates a condition, so which list an objective sits in is
## what it means. One class read both ways would be one the author has to negate
## in their head, on the half of the vocabulary where a mistake is silent.

## The name the board gave it, on the `[units]` row's fifth column.
@export var tag: StringName = &""


func is_met(state: GameState, _team: int, _progress: MissionProgress) -> bool:
	return tagged_unit(state, tag) == null


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if tag == &"":
		return "protect objective names no unit"
	if not board_names(map, tag):
		return "protect objective names '%s', which no unit on this board carries" % tag
	return ""
