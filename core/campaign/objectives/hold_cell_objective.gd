class_name HoldCellObjective
extends MissionObjective
## Hold named ground for a run of days — the depot, the crossing, the ridge that
## has to stay ours rather than merely be taken once.
##
## `CaptureCell` asks the board; this one asks the mission's tally, because no
## single board remembers how long a square has been ours (campaign-depth D2).
## `MissionProgress` counts a day at each rollover and drops the count the moment
## the ground changes hands, so `days` is whole days held and several turns inside
## one day cannot finish a hold: take the depot on day 2 and keep it, and
## `days = 3` completes at the start of day 5.
##
## Held by the player's **side**, as everywhere else — the tally counts the ground
## through `GameState.allied`, so an ally who takes the ridge is holding it for
## both of you.

@export var cell: Vector2i = Vector2i.ZERO
@export var days: int = 3


func is_met(_state: GameState, _team: int, progress: MissionProgress) -> bool:
	return progress.days_held(cell) >= days


func readout(_state: GameState, _team: int, progress: MissionProgress) -> String:
	return "%d/%d DAYS" % [progress.days_held(cell), days]


func marker_cells() -> Array[Vector2i]:
	return [cell]


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if days <= 0:
		return "hold objective asks for %d days" % days
	var bounds_error := MissionBoardCheck.off_board(map, cell, "hold objective names")
	if bounds_error != "":
		return bounds_error
	if not map.terrain_at(cell).is_property:
		return (
			"hold objective names %s, which is %s and not a property"
			% [cell, map.terrain_at(cell).id]
		)
	return ""
