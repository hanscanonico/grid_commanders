class_name HaldenMarr
extends CommanderType
## Meridian Coalition. Marr turns the coast into a front: hulls move and strike
## better, while every unit can make a stronger stand on a beach, reef or port.

@export var sea_attack_pct: int = 10
@export var sea_move_bonus: int = 1
## Deliberately id-keyed: this is a flavour list, "the coast", and no terrain
## flag states that — inventing one for a single doctrine would be a flag with
## one reader. Unlike Sable Wren's cover, this is not the concealment rule.
@export var shore_terrain: Array[StringName] = [&"shoal", &"reef", &"port"]
@export var shore_star_bonus: int = 1
@export var shore_power_attack_pct: int = 10
@export var shore_power_star_bonus: int = 1
@export var shore_power_move_bonus: int = 2


func attack_bonus(state: GameState, fight: Engagement) -> int:
	var bonus := sea_attack_pct if fight.attacker.type.domain == UnitType.SEA else 0
	if _is_active(state, fight.attacker.team) and _is_shore(state, fight.attacker_cell):
		bonus += shore_power_attack_pct
	return bonus


func move_bonus(state: GameState, unit: Unit) -> int:
	if unit.type.domain != UnitType.SEA:
		return 0
	var bonus := sea_move_bonus
	if _is_active(state, unit.team):
		bonus += shore_power_move_bonus
	return bonus


func star_bonus(state: GameState, fight: Engagement) -> int:
	if not _is_shore(state, fight.defender_cell):
		return 0
	var bonus := shore_star_bonus
	if _is_active(state, fight.defender.team):
		bonus += shore_power_star_bonus
	return bonus


func _is_shore(state: GameState, cell: Vector2i) -> bool:
	var terrain := state.map.terrain_at(cell)
	return terrain != null and terrain.id in shore_terrain
