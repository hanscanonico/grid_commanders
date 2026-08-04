class_name IrisColt
extends CommanderType
## Meridian Coalition. Colt's army gives up raw combat power for tempo. Second
## Wind refreshes only units whose committed action did not attack; builds and
## attackers remain exhausted.

@export var combat_pct: int = -10


func attack_bonus(_state: GameState, _fight: Engagement) -> int:
	return combat_pct


func defense_bonus(_state: GameState, _fight: Engagement) -> int:
	return combat_pct


func on_power_activated(state: GameState, team: int, _target: Vector2i = Vector2i.ZERO) -> void:
	for unit in state.units_of(team):
		if unit.carrier == null and unit.acted and unit.refreshable:
			unit.acted = false
			unit.refreshable = false


func wants_power(state: GameState, team: int) -> bool:
	for unit in state.units_of(team):
		if unit.carrier == null and unit.acted and unit.refreshable:
			return true
	return false
