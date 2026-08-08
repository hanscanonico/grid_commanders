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
	var named: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		if not map.in_bounds(cell):
			return "reach objective names %s, off a %dx%d board" % [cell, map.width, map.height]
		if named.has(cell):
			return "reach objective names %s twice" % cell
		var terrain := map.terrain_at(cell)
		if terrain.move_costs.is_empty():
			return (
				"reach objective names %s, which is %s and nothing can enter" % [cell, terrain.id]
			)
		named[cell] = true
	if cells.size() < count:
		return "reach objective asks %d units onto %d cells" % [count, cells.size()]
	return ""


func _arrived(state: GameState, team: int) -> int:
	var total := 0
	for cell: Vector2i in cells:
		var unit := state.unit_at(cell)
		if unit != null and state.allied(unit.team, team):
			total += 1
	return total
