class_name InesCalder
extends CommanderType
## Verdant League. Calder turns production into volume: every purchase is
## cheaper, every ordinary exchange is softer, and Weight of Numbers cashes the
## wider army in for one decisive attacking turn.

@export var unit_cost_pct: int = 80
@export var attack_pct: int = -10
## Total hook value while active. +15 against her ordinary -10 is the +25 swing
## the player-facing power promises.
@export var numbers_attack_pct: int = 15
@export var cheap_cost_ceiling: int = 5000
@export var cheap_build_bias: int = -3


func build_cost_pct(_state: GameState, _team: int, _unit_type: UnitType) -> int:
	return unit_cost_pct


func attack_bonus(state: GameState, fight: Engagement) -> int:
	return numbers_attack_pct if _is_active(state, fight.attacker.team) else attack_pct


func build_bias(_state: GameState, _team: int, unit_type: UnitType) -> int:
	return cheap_build_bias if unit_type.cost <= cheap_cost_ceiling else 0
