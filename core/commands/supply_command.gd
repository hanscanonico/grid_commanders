class_name SupplyCommand
extends Command
## Moves a supply unit (APC), then refills fuel and ammo of every friendly in
## reach. Friendlies in reach are also refilled automatically at turn start;
## this action is for mid-turn top-ups.
##
## Who is in reach is `TurnRules.in_supply_reach`, the one place supply is worked
## out: the turn's automatic top-up runs the same rule from the other end.

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


func validate(state: GameState) -> String:
	var visible := Vision.visible_cells_if_fogged(state, unit.team)
	var moving := MoveCommand.move_error(state, unit, path, visible)
	if moving != "":
		return moving
	if not unit.type.can_resupply:
		return "unit cannot resupply others"
	if friendlies_in_reach(state, path[path.size() - 1]).is_empty():
		return "no one in reach to supply"
	return ""


func apply(state: GameState) -> void:
	ambushed = state.advance_unit(unit, path)
	if ambushed:
		return  # stopped short by a hidden enemy; no top-up this turn
	for friendly in friendlies_in_reach(state, unit.cell):
		friendly.resupply()


## Friendlies this unit could refill standing on `from`. Public so the UI can
## decide whether to offer the Supply action at all.
##
## `friendlies` is a pre-fetched `state.units_of(unit.team)`, for a caller
## scoring many `from` cells against the one roster (the AI planner, sweeping
## every reachable cell) rather than re-scanning the whole board per cell.
## Default empty scans, today's behaviour; either way every `from` runs
## through the one rule, `TurnRules.in_supply_reach`.
func friendlies_in_reach(
	state: GameState, from: Vector2i, friendlies: Array[Unit] = []
) -> Array[Unit]:
	var candidates := friendlies if not friendlies.is_empty() else state.units_of(unit.team)
	var result: Array[Unit] = []
	for other in candidates:
		if TurnRules.in_supply_reach(state, unit, from, other):
			result.append(other)
	return result
