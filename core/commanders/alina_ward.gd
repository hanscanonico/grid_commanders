class_name AlinaWard
extends CommanderType
## Meridian Coalition. Combined arms: her units hit harder when they fight
## alongside a different kind of unit, so her strength is a mixed, coordinated
## line rather than a stack of the same thing. Coordinated Push then moves that
## whole line at once.

## Percentage points added when a friendly of another movement class stands next
## to the firing unit.
@export var combined_arms_pct: int = 10
@export var push_attack_pct: int = 10
@export var push_defense_pct: int = 10
@export var push_move_bonus: int = 1
## Tiles of progress a quiet move gives up to end beside a friendly of another
## movement class, so the mixed line the passive pays for forms on purpose.
@export var line_stand_tiles: int = 1


func attack_bonus(state: GameState, fight: Engagement) -> int:
	var bonus := 0
	if _has_mixed_neighbour(state, fight.attacker, fight.attacker_cell):
		bonus += combined_arms_pct
	if _is_active(state, fight.attacker.team):
		bonus += push_attack_pct
	return bonus


func defense_bonus(state: GameState, fight: Engagement) -> int:
	return push_defense_pct if _is_active(state, fight.defender.team) else 0


func move_bonus(state: GameState, unit: Unit) -> int:
	return push_move_bonus if _is_active(state, unit.team) else 0


## Ground advice: a quiet move worth nothing else ends beside a different-class
## friendly when one is in reach — the same neighbour test the attack bonus
## reads, asked of a cell the unit is only thinking about standing on.
func stand_value(state: GameState, unit: Unit, cell: Vector2i) -> int:
	return line_stand_tiles if _has_mixed_neighbour(state, unit, cell) else 0


## A friendly of a *different* movement class on one of the four cells around
## `from`, which is where the shot is fired from — during a damage preview that
## is where the unit is about to stand, not where it is. The unit itself is
## therefore skipped: it is still sitting on its old cell, and finding itself
## there would never count anyway (same team, same class).
##
## One pass over her fielded army rather than four `unit_at` scans (each itself a
## walk of every unit): `stand_value` asks this once per candidate cell an
## advancing unit is weighing, so the four-scan shape was quartering the board's
## unit list on every cell of every sweep for no answer `unit_at` gives that a
## single pass testing the four offsets does not.
func _has_mixed_neighbour(state: GameState, unit: Unit, from: Vector2i) -> bool:
	# `unit.team`, deliberately not the side (four-players plan D2): combined arms
	# is what *her* army fields beside itself, not what stands nearby.
	for other in _fielded_units(state, unit.team):
		if other == unit:
			continue
		if other.type.move_class == unit.type.move_class:
			continue
		if MovementResolver.DIRECTIONS.has(other.cell - from):
			return true
	return false
