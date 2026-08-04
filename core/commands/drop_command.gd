class_name DropCommand
extends Command
## Moves a transport, then unloads its passenger onto an adjacent cell.
## The passenger comes out exhausted, like Advance Wars.
##
## Two terrain rules, and they are different questions. The cargo has to be able
## to *stand* where it lands, which every transport shares; and the transport has
## to be somewhere it can unload *from*, which is only the Lander's problem — a
## landing craft beaches on a shoal or ties up at a port, and cannot tip a tank
## over the side mid-ocean. Both come from data, so neither is a special case.

var unit: Unit  # the transport
var path: Array[Vector2i]
var drop_cell: Vector2i
## Which passenger to unload. Left null it means the first loaded, which is what a
## single-slot transport always drops; a Lander holds two, and either might be the
## one that can stand where the other cannot, so the caller names it explicitly.
var passenger: Unit
## Set by apply() when the transport arrived but the drop cell turned out
## occupied — a hidden enemy standing on it, or the transport's own arrival
## filling it. The passenger stays aboard, and the move itself completed, so this
## is a blockage rather than the `ambushed` trap.
var drop_blocked: bool = false


func _init(
	p_unit: Unit, p_path: Array[Vector2i], p_drop_cell: Vector2i, p_passenger: Unit = null
) -> void:
	unit = p_unit
	path = p_path
	drop_cell = p_drop_cell
	passenger = p_passenger


func validate(state: GameState) -> String:
	# The transport's own sight, for the whole check: the move's path and, below,
	# whether anything it can see is standing on the drop cell.
	var visible := Vision.visible_cells_if_fogged(state, unit.team)
	var moving := MoveCommand.move_error(state, unit, path, visible)
	if moving != "":
		return moving
	var cargo := state.cargo_of(unit)
	if cargo.is_empty():
		return "nothing to drop"
	var rider := _rider(cargo)
	if rider == null:
		return "unit is not aboard"
	var dest: Vector2i = path[path.size() - 1]
	if not unit.type.can_unload_from(state.map.terrain_at(dest).id):
		return "cannot unload here"
	var dist := Grid.manhattan(drop_cell, dest)
	if dist != 1:
		return "drop cell must be adjacent"
	var terrain := state.map.terrain_at(drop_cell)
	if terrain == null or not terrain.is_passable(rider.type.move_class):
		return "cargo cannot stand there"
	var occupant := state.unit_at(drop_cell)
	if occupant != null and occupant != unit:
		# The transport's own vacated cell is fine, and a hidden enemy is left to
		# foil the drop on apply rather than refused, which would reveal it; a
		# friendly or a visible enemy still blocks.
		if (
			state.allied(occupant.team, unit.team)
			or Vision.can_see_unit(state, unit.team, occupant, visible)
		):
			return "drop cell is occupied"
	return ""


func apply(state: GameState) -> void:
	var rider := _rider(state.cargo_of(unit))
	ambushed = state.advance_unit(unit, path)
	if ambushed:
		return
	if state.unit_at(drop_cell) != null:
		drop_blocked = true
		return
	rider.carrier = null
	rider.cell = drop_cell
	rider.acted = true
	# Stated, not inherited, like the unit a Join exhausts: the transport committed
	# this action, so the rider's own earlier flag cannot decide a refresh.
	rider.refreshable = false


## The passenger this drop unloads: the one named when it is genuinely aboard,
## else the first loaded when none was named. Null when a passenger was named that
## this transport is not carrying, which `validate` refuses.
func _rider(cargo: Array[Unit]) -> Unit:
	if passenger == null:
		return cargo[0]
	return passenger if cargo.has(passenger) else null
