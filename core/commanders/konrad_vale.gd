class_name KonradVale
extends CommanderType
## Iron Dominion. Vale buys fewer units and expects each one to win its trade.
## The price surcharge is visible from the first infantry; the stats and power
## make the army behind it increasingly difficult to dislodge.

@export var unit_cost_pct: int = 120
@export var elite_attack_pct: int = 10
@export var elite_defense_pct: int = 10
@export var overwhelming_attack_pct: int = 25
@export var overwhelming_star_pierce: int = 1
@export var cheap_cost_ceiling: int = 5000
@export var cheap_build_bias: int = 3


func build_cost_pct(_state: GameState, _team: int, _unit_type: UnitType) -> int:
	return unit_cost_pct


func attack_bonus(state: GameState, fight: Engagement) -> int:
	var bonus := elite_attack_pct
	if _is_active(state, fight.attacker.team):
		bonus += overwhelming_attack_pct
	return bonus


func defense_bonus(_state: GameState, _fight: Engagement) -> int:
	return elite_defense_pct


func star_pierce(state: GameState, fight: Engagement) -> int:
	return overwhelming_star_pierce if _is_active(state, fight.attacker.team) else 0


func build_bias(_state: GameState, _team: int, unit_type: UnitType) -> int:
	return cheap_build_bias if unit_type.cost <= cheap_cost_ceiling else 0
