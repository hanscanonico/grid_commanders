class_name ReachCellObjective
extends MissionObjective
## Get this many of our units onto named ground — the exit zone, and the shape an
## evacuation or a breakout is written in.
##
## Counted across the player's **side**, like every other objective: an ally's
## column that reaches the pass has reached it for both of you, and a team-only
## count would leave an allied mission one unit short of a zone somebody friendly
## is standing in.
##
## Who stands on a cell is `GameState.unit_at`'s answer, which is also what keeps
## a passenger out of the count: a carried unit's stored cell is stale from
## wherever it boarded, and it has arrived nowhere until its transport sets it
## down.

## The zone, as the cells that count. A list rather than one cell because a
## square holds one unit, so any `count` above 1 would otherwise be unreachable.
@export var cells: Array[Vector2i] = []
@export var count: int = 1


func is_met(state: GameState, team: int, _progress: MissionProgress) -> bool:
	return _arrived(state, team) >= count


func readout(state: GameState, team: int, _progress: MissionProgress) -> String:
	return "%d/%d" % [_arrived(state, team), count]


func definition_error(map: MapData, _team: int) -> String:
	if count <= 0:
		return "reach objective asks for %d units" % count
	var fieldable := _fieldable_classes(map)
	var named: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		if not map.in_bounds(cell):
			return "reach objective names %s, off a %dx%d board" % [cell, map.width, map.height]
		if named.has(cell):
			return "reach objective names %s twice" % cell
		if not _enterable(map.terrain_at(cell), fieldable):
			return "reach objective names %s, which nothing this board fields can enter" % cell
		named[cell] = true
	if cells.size() < count:
		return "reach objective asks %d units onto %d cells" % [count, cells.size()]
	return ""


## Every move class this board could put on a square: what its `[units]` section
## seats, plus what its properties build — `TerrainType.builds` being the one
## authority on that, so no terrain is named here. It answers what the *board*
## could field rather than what this mission's seating will, the tighter question
## belonging to the content gate, which holds the mission as well as the board.
func _fieldable_classes(map: MapData) -> Dictionary[StringName, bool]:
	var classes: Dictionary[StringName, bool] = {}
	var unit_db := UnitDB.load_default()
	for entry: Dictionary in map.starting_units:
		var unit_type := unit_db.by_symbol(entry["symbol"])
		if unit_type != null:
			classes[unit_type.move_class] = true
	for cell: Vector2i in map.property_cells():
		for move_class: StringName in map.terrain_at(cell).builds:
			classes[move_class] = true
	return classes


static func _enterable(terrain: TerrainType, classes: Dictionary[StringName, bool]) -> bool:
	for move_class: StringName in classes:
		if terrain.is_passable(move_class):
			return true
	return false


func _arrived(state: GameState, team: int) -> int:
	var total := 0
	for cell: Vector2i in cells:
		var unit := state.unit_at(cell)
		if unit != null and state.allied(unit.team, team):
			total += 1
	return total
