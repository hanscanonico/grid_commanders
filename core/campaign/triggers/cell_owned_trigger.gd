class_name CellOwnedTrigger
extends MissionTrigger
## Named ground is in given hands — the relay falls, the depot is retaken, the
## crossing goes loose.
##
## Who holds it is named as one of three states rather than as a team number, for
## the reason every objective reads a side: "the enemy took it" is the question a
## mission asks, and a bare team int cannot ask it on a board where an ally holds
## ground of their own.

enum Holder {
	## The player's side holds it, whichever of the allies captured it.
	OURS,
	## Somebody hostile to the player's side holds it.
	ENEMY,
	## Nobody holds it — neutral, or the ground a fallen army left loose.
	NEUTRAL,
}

@export var cell: Vector2i = Vector2i.ZERO
@export var holder: Holder = Holder.ENEMY


func is_met(
	state: GameState, team: int, _progress: MissionProgress, _ledger: CampaignState = null
) -> bool:
	var owner := state.owner_at(cell)
	match holder:
		Holder.OURS:
			return owner != 0 and state.allied(owner, team)
		Holder.ENEMY:
			return owner != 0 and not state.allied(owner, team)
		_:
			return owner == 0


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if not map.in_bounds(cell):
		return "cell-owned trigger names %s, off a %dx%d board" % [cell, map.width, map.height]
	if not map.terrain_at(cell).is_property:
		return (
			"cell-owned trigger names %s, which is %s and cannot change hands"
			% [cell, map.terrain_at(cell).id]
		)
	return ""
