class_name SeraLark
extends CommanderType
## Aurora Compact. Distance is the whole doctrine: every unit she fields moves a
## tile further than it should, in every domain and on every turn, and Forced
## March adds another tile for a turn.
##
## No combat modifier, no terrain rule and no economy — the passive is what she
## is picked for, and her power is deliberately the smallest on the roster.

@export var move_bonus_points: int = 1
@export var march_move_bonus: int = 1


func move_bonus(state: GameState, unit: Unit) -> int:
	var bonus := move_bonus_points
	if _is_active(state, unit.team):
		bonus += march_move_bonus
	return bonus


## Forced March buys a tile and no damage at all, so it fires for ground alone,
## like Cassian Rook's Redeployment: the offensive default reads "a shot is
## already reachable", and a shot already reachable is the one turn the extra
## tile changes nothing about. The ground is measured with the march's own
## movement, because a property one step beyond reach is exactly what firing
## fixes.
func wants_power(state: GameState, team: int) -> bool:
	return _can_reach_capture(state, team, march_move_bonus)
