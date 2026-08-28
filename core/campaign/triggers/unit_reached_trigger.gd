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
	var unit_error := MissionBoardCheck.named_unit(map, tag, "unit-reached trigger names")
	if unit_error != "":
		return unit_error
	if cells.is_empty():
		return "unit-reached trigger names no ground for '%s' to reach" % tag
	for cell: Vector2i in cells:
		var bounds_error := MissionBoardCheck.off_board(map, cell, "unit-reached trigger names")
		if bounds_error != "":
			return bounds_error
	return ""
