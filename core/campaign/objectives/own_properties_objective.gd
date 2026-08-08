class_name OwnPropertiesObjective
extends MissionObjective
## Hold this many properties at once — the economy objective, and the shape most
## of a supply or occupation mission is written in.
##
## Counted across the player's **side**, not their team. A duel reads exactly as
## a team count because a side of one is a team; an allied mission reads as the
## alliance's holdings, which is what stops an ally's capture from making the
## objective unreachable (an ally's property is not capturable, so a team-only
## count could be driven permanently below target by your own partner).

@export var count: int = 5
## Optional: only properties of this terrain kind are counted (`city`, `base`,
## `airport`, `port`). Empty counts every property, headquarters included.
@export var terrain_id: StringName = &""


func is_met(state: GameState, team: int, _progress: MissionProgress) -> bool:
	return _held(state, team) >= count


func readout(state: GameState, team: int, _progress: MissionProgress) -> String:
	return "%d/%d" % [_held(state, team), count]


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if count <= 0:
		return "property objective asks for %d properties" % count
	var available := 0
	for cell in map.property_cells():
		if terrain_id == &"" or map.terrain_at(cell).id == terrain_id:
			available += 1
	if available < count:
		var kind := "properties" if terrain_id == &"" else "'%s' properties" % terrain_id
		return "property objective asks for %d %s; the board has %d" % [count, kind, available]
	return ""


func _held(state: GameState, team: int) -> int:
	var total := 0
	for cell: Vector2i in state.property_owners:
		var owner: int = state.property_owners[cell]
		if owner == 0 or not state.allied(owner, team):
			continue
		if terrain_id != &"" and state.map.terrain_at(cell).id != terrain_id:
			continue
		total += 1
	return total
