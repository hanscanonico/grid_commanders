class_name NiaRowan
extends CommanderType
## Verdant League. Terrain doctrine: her foot units treat the difficult ground
## everyone else avoids as ordinary, so woods and mountains become her road
## network rather than an obstacle. Ghost March adds sight to that mobility for
## a turn, and lifts the rule that woods hide what is more than a tile away.
##
## No combat modifier at all — everything she does is positional.

@export var discount_classes: Array[StringName] = [TerrainType.FOOT, TerrainType.BOOT]
## Deliberately id-keyed: this is a flavour list, "rough going", and no terrain
## flag states that — inventing one for a single doctrine would be a flag with
## one reader. Unlike Sable Wren's cover, this is not the concealment rule.
@export var discount_terrain: Array[StringName] = [&"woods", &"mountain"]
## Movement points taken off a discounted step. MovementResolver floors the
## result at 1, so this can never make a step free.
@export var terrain_discount: int = 1
@export var march_classes: Array[StringName] = [TerrainType.FOOT, TerrainType.BOOT]
## Recon is not foot, but scouting is the point of Ghost March.
@export var march_ids: Array[StringName] = [&"recon"]
@export var march_move_bonus: int = 1
@export var march_vision_bonus: int = 1


func terrain_cost(_state: GameState, unit: Unit, terrain: TerrainType, base: int) -> int:
	if unit.type.move_class not in discount_classes or terrain.id not in discount_terrain:
		return base
	return base - terrain_discount


func move_bonus(state: GameState, unit: Unit) -> int:
	return march_move_bonus if _marching(state, unit) else 0


func vision_bonus(state: GameState, unit: Unit) -> int:
	return march_vision_bonus if _marching(state, unit) else 0


func sees_into_cover(state: GameState, unit: Unit) -> bool:
	return _marching(state, unit)


## Ghost March buys ground and sight and no damage, so — like Cassian Rook's
## Redeployment — the offensive default is the wrong read: a shot already in
## reach is the one turn none of the three effects changes. Ground first,
## measured with the march's own movement, which is the point of it.
##
## The other two effects are worth exactly nothing with the lights on, so a clear
## match leaves only the tile and the ground branch above has already answered
## for that. With fog up, closing on an enemy is a scouting reason to fire, asked
## over her whole army rather than only the units still to act: sight lasts the
## turn and a unit that has already shot still sees.
func wants_power(state: GameState, team: int) -> bool:
	if _can_reach_capture(state, team, march_move_bonus):
		return true
	if not state.fog_enabled:
		return false
	return _can_strike_an_opponent(state, team, false)


func _marching(state: GameState, unit: Unit) -> bool:
	if not _is_active(state, unit.team):
		return false
	return unit.type.move_class in march_classes or unit.type.id in march_ids
