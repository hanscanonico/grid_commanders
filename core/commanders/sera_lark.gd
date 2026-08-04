class_name SeraLark
extends CommanderType
## Aurora Compact. Distance is the whole doctrine: every unit she fields moves a
## tile further than it should, in every domain and on every turn, and Forced
## March adds another tile for a turn.
##
## No combat modifier, no terrain rule and no economy — the passive is what she
## is picked for, and her power is deliberately the smallest on the roster.

@export var road_move_bonus: int = 1
@export var march_move_bonus: int = 1


func move_bonus(state: GameState, unit: Unit) -> int:
	var bonus := road_move_bonus
	if _is_active(state, unit.team):
		bonus += march_move_bonus
	return bonus


## Forced March buys ground rather than damage, so a property her capture units
## can reach counts as much as an enemy they can — otherwise a doctrine measured
## only in fights banks a full meter while walking across an empty map. The
## ground is measured with the march's own movement, because a property one step
## beyond reach is exactly what firing fixes.
func wants_power(state: GameState, team: int) -> bool:
	return super(state, team) or _can_reach_capture(state, team, march_move_bonus)
