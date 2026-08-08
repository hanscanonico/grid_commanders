class_name RemoveUnitsEffect
extends MissionEffect
## Takes named units off the board — the column is withdrawn, the depot ship
## sails, the saboteurs finish the bridge.
##
## `GameState.remove_unit` is the authority, so cargo goes down with its
## transport and an army that loses its last unit falls exactly as it would have
## to a shot. **Nothing is banked to either meter**: charge is minted inside
## `ChargeLedger.bank_losses` and nowhere else (Hammerfall's D4), and paying a
## side for a scripted withdrawal would hand a mission's own beat to whoever it
## was written against.
##
## The doomed are collected before any is removed, because `state.units` is being
## read and `remove_unit` mutates it.

@export var tags: Array[StringName] = []


func apply(state: GameState, _team: int) -> void:
	var doomed: Array[Unit] = []
	for tag: StringName in tags:
		var unit := MissionObjective.tagged_unit(state, tag)
		if unit != null:
			doomed.append(unit)
	for unit in doomed:
		state.remove_unit(unit)


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if tags.is_empty():
		return "removal names no units"
	for tag: StringName in tags:
		if tag == &"":
			return "removal names an empty tag"
		if not MissionObjective.board_names(map, tag):
			return "removal names '%s', which no unit on this board carries" % tag
	return ""
