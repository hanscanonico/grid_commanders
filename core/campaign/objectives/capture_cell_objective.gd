class_name CaptureCellObjective
extends MissionObjective
## Hold a named square of ground. The campaign's most common objective: a relay,
## a depot, a headquarters the mission is named after.
##
## Satisfied while the cell is owned by the player's **side**, so an ally who
## takes it has taken it for both of you.

@export var cell: Vector2i = Vector2i.ZERO


func is_met(state: GameState, team: int, _progress: MissionProgress) -> bool:
	var owner := state.owner_at(cell)
	return owner != 0 and state.allied(owner, team)


func named_cells() -> Array[Vector2i]:
	return [cell]


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if not map.in_bounds(cell):
		return "capture objective names %s, off a %dx%d board" % [cell, map.width, map.height]
	if not map.terrain_at(cell).is_property:
		return (
			"capture objective names %s, which is %s and not a property"
			% [cell, map.terrain_at(cell).id]
		)
	return ""
