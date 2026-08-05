class_name LoadCommand
extends Command
## Moves a unit onto a friendly transport and boards it.
##
## What a transport accepts is its own data (UnitType.cargo_classes) rather than
## one list shared by every carrier: an APC and a T-Copter take infantry, a
## Lander takes what drives, and the difference between them is a .tres field.

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


func validate(state: GameState) -> String:
	var visible := Vision.visible_cells_if_fogged(state, unit.team)
	var steps := MoveCommand.validate_path_steps(state, unit, path, visible)
	if steps != "":
		return steps
	var transport := state.unit_at(path[path.size() - 1])
	if transport == null:
		return "no friendly transport at the destination"
	return carriage_error(state, transport, unit)


## Whether `rider` may be *inside* `transport` at all: everything about the pairing
## that holds however the two came to be together, and nothing about getting there.
## "" when the carriage is legal, else the reason it is not.
##
## The single authority on that question, in the tradition of `AttackRange.can_engage`
## and for the same reason it was split out. Boarding is not the only way a rider ends
## up in a transport — a save file arrives at the arrangement without walking a path —
## so `SaveCodec` asks this per carrier link rather than keeping its own opinion.
## While it did keep one, a hand-edited save could load a battleship into an infantry
## (COM-53).
##
## Capacity counts everything aboard *except the rider*, which is what lets the same
## rule answer for both callers: the command asks before the rider has boarded and
## the codec asks after the link is already wired, and neither has to know that the
## other exists.
static func carriage_error(state: GameState, transport: Unit, rider: Unit) -> String:
	if transport == rider:
		return "a unit cannot carry itself"
	# `!= rider.team`, deliberately not `allied` (four-players plan D2): a transport
	# is infrastructure, and allies share sight and purpose rather than hulls.
	if transport.team != rider.team:
		return "no friendly transport for this unit"
	if transport.type.transport_capacity <= 0:
		return "unit is not a transport"
	if not transport.type.can_carry(rider.type.move_class):
		return "unit cannot be transported"
	var aboard := 0
	for passenger in state.cargo_of(transport):
		if passenger != rider:
			aboard += 1
	if aboard >= transport.type.transport_capacity:
		return "transport is full"
	# The sim nests transports one level deep only: a loaded carrier's cargo would
	# freeze at its boarding cell and its capture-progress erase the wrong cell on
	# a sinking. Refuse the second level outright.
	if not state.cargo_of(rider).is_empty():
		return "unit is carrying cargo"
	return ""


func apply(state: GameState) -> void:
	var transport := state.unit_at(path[path.size() - 1])
	ambushed = state.advance_unit(unit, path)
	if ambushed:
		return  # stopped short of the transport; it does not board
	unit.carrier = transport
