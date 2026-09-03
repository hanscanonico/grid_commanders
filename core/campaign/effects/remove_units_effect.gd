class_name RemoveUnitsEffect
extends MissionEffect
## Takes named units off the board — the column is withdrawn, the depot ship
## sails, the saboteurs finish the bridge.
##
## `GameState.remove_units` is the authority, so cargo goes down with its
## transport and every army the beat empties falls exactly as it would have to a
## shot. It is the batch seam rather than `remove_unit` because one beat can
## empty two armies at once (COM-179), and judged one death at a time the winner
## would be whichever army the tag list happened to empty first.
## **Nothing is banked to either meter**: charge is minted inside
## `ChargeLedger.bank_losses` and nowhere else (Hammerfall's D4), and paying a
## side for a scripted withdrawal would hand a mission's own beat to whoever it
## was written against.
##
## The doomed are collected before any is removed, because `state.units` is being
## read and the removal mutates it.

@export var tags: Array[StringName] = []


func apply(state: GameState, _team: int) -> void:
	var doomed: Array[Unit] = []
	for tag: StringName in tags:
		var unit := MissionObjective.tagged_unit(state, tag)
		if unit != null:
			doomed.append(unit)
	state.remove_units(doomed)


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if tags.is_empty():
		return "removal names no units"
	for tag: StringName in tags:
		var unit_error := MissionBoardCheck.named_unit(map, tag, "removal names")
		if unit_error != "":
			return unit_error
	return ""
