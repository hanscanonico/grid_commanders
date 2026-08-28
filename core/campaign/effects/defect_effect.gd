class_name DefectEffect
extends MissionEffect
## Moves named units from one army to another — the wardens remember Greenwater,
## the garrison opens the gate, the mercenaries are outbid.
##
## Three things move with the unit and each has a reason:
##
## **Its cargo.** `LoadCommand.carriage_error` is the authority on what may be
## inside a transport and it refuses a rider of another army — a check `SaveCodec`
## runs per carrier link — so a transport that changed sides alone would be a
## board no save could carry. A rider named on its own while its carrier stays
## put is skipped for the same reason: it cannot change army while it is aboard.
##
## **Its capture.** Points spent on a property were spent by the army that owned
## the unit, so the square starts again under its new one — the rule ownership
## changes and deaths already follow.
##
## **Its turn.** A defector arrives exhausted like a built or landed unit, so a
## beat cannot hand the receiving army a free action it had not earned.
##
## What does *not* follow is a rout. An army whose last unit defects is still an
## army — `GameState` models an empty one as standing, and elimination is
## `remove_unit`'s to reach — so a mission that wants the seat gone says so with
## an objective or an `EndMission`, and does not get it as a side effect.

@export var from_team: int = 2
@export var to_team: int = 1
@export var tags: Array[StringName] = []


func apply(state: GameState, _team: int) -> void:
	for tag: StringName in tags:
		var unit := MissionObjective.tagged_unit(state, tag)
		if unit == null or unit.team != from_team or unit.carrier != null:
			continue
		_change_army(state, unit)
		for passenger in state.cargo_of(unit):
			_change_army(state, passenger)


func board_error(state: GameState, _team: int) -> String:
	var from_error := MissionBoardCheck.absent_team(state, from_team, "defection takes units from")
	if from_error != "":
		return from_error
	var to_error := MissionBoardCheck.absent_team(state, to_team, "defection gives units to")
	if to_error != "":
		return to_error
	if state.is_eliminated(to_team):
		return "defection gives units to army %d, which has already fallen" % to_team
	return ""


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if from_team == to_team:
		return "defection moves units from army %d to itself" % from_team
	var from_error := MissionBoardCheck.unseated_team(map, from_team, "defection takes units from")
	if from_error != "":
		return from_error
	var to_error := MissionBoardCheck.unseated_team(map, to_team, "defection gives units to")
	if to_error != "":
		return to_error
	if tags.is_empty():
		return "defection names no units"
	for tag: StringName in tags:
		var unit_error := MissionBoardCheck.named_unit(map, tag, "defection names")
		if unit_error != "":
			return unit_error
	return ""


## A passenger holds no cell of its own — its stored one is stale from wherever
## it boarded — so only a unit on the board can be holding a capture.
func _change_army(state: GameState, unit: Unit) -> void:
	if unit.carrier == null:
		state.capture_progress.erase(unit.cell)
	unit.team = to_team
	unit.acted = true
