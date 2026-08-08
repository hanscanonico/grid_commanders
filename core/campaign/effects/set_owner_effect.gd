class_name SetOwnerEffect
extends MissionEffect
## Flips property ownership — the town opens its gates, the depot is scuttled
## back to nobody, the garrison runs up another flag.
##
## Ground changing hands resets any capture standing on it, which is the rule
## `CaptureCommand` and `GameState.eliminate` already follow: the points were
## spent against the owner it had, and the square starts again under the new one.

## The army the ground goes to; 0 is neutral, the ground anybody may take.
@export var team: int = 1
@export var cells: Array[Vector2i] = []


func apply(state: GameState, _team: int) -> void:
	for cell: Vector2i in cells:
		state.set_owner(cell, team)
		state.capture_progress.erase(cell)


func board_error(state: GameState, _team: int) -> String:
	if team != MapData.NEUTRAL and not state.teams.has(team):
		return "ownership is handed to army %d, which is not at this table" % team
	for cell: Vector2i in cells:
		if not state.map.in_bounds(cell):
			return "ownership is set on %s, off the board" % cell
	return ""


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if team != MapData.NEUTRAL and not map.teams().has(team):
		return "ownership is handed to army %d, which this board does not seat" % team
	if cells.is_empty():
		return "ownership is set on no ground"
	for cell: Vector2i in cells:
		if not map.in_bounds(cell):
			return "ownership is set on %s, off a %dx%d board" % [cell, map.width, map.height]
		if not map.terrain_at(cell).is_property:
			return (
				"ownership is set on %s, which is %s and belongs to nobody"
				% [cell, map.terrain_at(cell).id]
			)
	return ""
