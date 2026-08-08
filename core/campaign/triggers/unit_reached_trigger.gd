class_name UnitReachedTrigger
extends MissionTrigger
## A named unit is standing on named ground — the courier makes the pass, the
## marshal reaches the ford.
##
## A carried unit has arrived nowhere: its stored cell is stale from wherever it
## boarded, which is why `ReachCell` counts through `GameState.unit_at` and why
## this one asks for a unit with no carrier. It rides until its transport sets it
## down, and only then has it got anywhere.

@export var tag: StringName = &""
## The ground that counts. A list, because an arrival is a zone rather than a
## square — the pass is three cells wide and any of them is out.
@export var cells: Array[Vector2i] = []


func is_met(
	state: GameState, _team: int, _progress: MissionProgress, _ledger: CampaignState = null
) -> bool:
	var unit := MissionObjective.tagged_unit(state, tag)
	if unit == null or unit.carrier != null:
		return false
	return cells.has(unit.cell)


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if tag == &"":
		return "unit-reached trigger names no unit"
	if not MissionObjective.board_names(map, tag):
		return "unit-reached trigger names '%s', which no unit on this board carries" % tag
	if cells.is_empty():
		return "unit-reached trigger names no ground for '%s' to reach" % tag
	for cell: Vector2i in cells:
		if not map.in_bounds(cell):
			return (
				"unit-reached trigger names %s, off a %dx%d board" % [cell, map.width, map.height]
			)
	return ""
