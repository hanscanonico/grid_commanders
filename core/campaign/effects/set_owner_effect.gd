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
	if team != MapData.NEUTRAL:
		var seat_error := MissionBoardCheck.absent_team(state, team, "ownership is handed to")
		if seat_error != "":
			return seat_error
	for cell: Vector2i in cells:
		if not state.map.in_bounds(cell):
			return "ownership is set on %s, off the board" % cell
	return ""


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if team != MapData.NEUTRAL:
		var seat_error := MissionBoardCheck.unseated_team(map, team, "ownership is handed to")
		if seat_error != "":
			return seat_error
	if cells.is_empty():
		return "ownership is set on no ground"
	for cell: Vector2i in cells:
		var bounds_error := MissionBoardCheck.off_board(map, cell, "ownership is set on")
		if bounds_error != "":
			return bounds_error
		var property_error := MissionBoardCheck.property_cell(map, cell, "ownership is set on")
		if property_error != "":
			return property_error
	return ""
