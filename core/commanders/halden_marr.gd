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
## Tiles of march the gate lets a land unit spend beyond its budget to reach the
## coast: the shore bonuses are worth firing for ground the army can actually
## stand on this turn.
@export var shore_reach_move: int = 0
## Tiles of progress a quiet move gives up to stand on the coast — the everyday
## preference, and the stronger one once Make for the Shore is banked or running.
@export var shore_stand_tiles: int = 1
@export var shore_ready_stand_tiles: int = 2


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


## Every effect of Make for the Shore is keyed on a hull or on shore ground, so
## an army with neither fires a full meter for exactly nothing — forever, on a
## land-only board. The offensive default still has to hold: the power is
## OWNER_TURN and each of its bonuses lands inside this turn's exchanges.
func wants_power(state: GameState, team: int) -> bool:
	return _can_use_the_shore(state, team) and super(state, team)


## Ground advice: his army defends better on the coast, so a quiet move prefers
## to end there — mildly while the meter fills, more strongly once Make for the
## Shore is banked or up. The strong case is the other half of the gate above:
## with no hull and nobody near the coast it refuses to fire, and without this
## the planner had no reason to walk anyone onto a beach. Preference only, never
## priced off the shore star — the forecasts already carry that.
func stand_value(state: GameState, unit: Unit, cell: Vector2i) -> int:
	if not _is_shore(state, cell):
		return 0
	var co_state := state.commander_state(unit.team)
	if co_state.power_active or co_state.is_ready():
		return shore_ready_stand_tiles
	return shore_stand_tiles


## A hull to speed up, a unit already standing on the coast, or one that can be
## standing on it before the turn ends. The walk goes through MovementResolver
## like _can_reach_capture does, so the movement budget keeps one owner and fuel
## still caps it.
func _can_use_the_shore(state: GameState, team: int) -> bool:
	for unit in state.units_of(team):
		if unit.carrier != null:
			continue
		if unit.type.domain == UnitType.SEA or _is_shore(state, unit.cell):
			return true
		if unit.acted:
			continue
		var reach := MovementResolver.reachable(state, unit, shore_reach_move)
		for cell in reach.cells():
			if reach.can_stop_at(cell) and _is_shore(state, cell):
				return true
	return false


func _is_shore(state: GameState, cell: Vector2i) -> bool:
	var terrain := state.map.terrain_at(cell)
	return terrain != null and terrain.id in shore_terrain
