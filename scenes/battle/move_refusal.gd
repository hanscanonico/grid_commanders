class_name MoveRefusal
extends RefCounted
## The words a refused move shows the player. The reason is
## `MovementResolver.destination_error`'s and the carriage half is
## `LoadCommand.carriage_error`'s; this only says them in the board's voice.

const OUT_OF_REACH := "Out of reach."
const ENEMY_THERE := "An enemy is standing there."


## `reach` is the fill the selection painted, so the answer is about the cells the
## player was shown and never about anything the mover cannot see.
static func words(
	state: GameState, unit: Unit, reach: MovementResolver.MoveRange, cell: Vector2i
) -> String:
	match MovementResolver.destination_error(state, unit, reach, cell):
		"destination is held by an enemy":
			return ENEMY_THERE
		"path crosses impassable terrain":
			return _impassable(state, unit, cell)
	return OUT_OF_REACH


## Ground the unit cannot enter. When a transport that could carry it waits there,
## the rule worth saying is where that transport takes riders on board.
static func _impassable(state: GameState, unit: Unit, cell: Vector2i) -> String:
	var ground := state.map.terrain_at(cell).display_name.to_lower()
	var transport := state.unit_at(cell)
	if transport == null or LoadCommand.carriage_error(state, transport, unit) != "":
		return "%s cannot enter %s." % [unit.type.display_name, ground]
	var docks := transport.type.unload_terrain
	if docks.is_empty():
		return "%s cannot board on %s." % [unit.type.display_name, ground]
	var names: PackedStringArray = []
	for id in docks:
		names.append(String(id).replace("_", " "))
	return "A %s can only load on a %s." % [transport.type.display_name, " or ".join(names)]
