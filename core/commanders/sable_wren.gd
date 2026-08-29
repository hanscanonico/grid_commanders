class_name SableWren
extends CommanderType
## Verdant League. Ambush doctrine: her army is worth more in cover than in the
## open — cover hardens it and sharpens its shots, with no matching punishment
## for standing anywhere else. Vanish makes that cover absolute for a round.
##
## Vanish is the reworked version (decision D4). As originally written — "units
## in Woods can only be revealed from an adjacent tile" — it was a no-op, because
## Vision already hides *everyone's* woods units from non-adjacent viewers. So it
## became true invisibility: while the power runs her units in cover are hidden
## even from an adjacent enemy, and the only thing that finds one is trying to
## move into its cell, which the movement rules already refuse.
##
## ROUND duration, unlike every other wave-2 power. An ambush that expired at the
## end of her own turn would never be there when the opponent walked into it.

@export var woods_star_bonus: int = 1
## What an everyday shot out of cover gains, power or no power.
@export var cover_attack_pct: int = 20
@export var ambush_attack_pct: int = 40
## Tiles of progress a quiet move gives up to stand in cover — the everyday
## preference, and the strong one once Vanish is banked or running.
@export var cover_stand_tiles: int = 1
@export var vanish_stand_tiles: int = 4


func star_bonus(state: GameState, fight: Engagement) -> int:
	return woods_star_bonus if _is_cover(state, fight.defender_cell) else 0


## Shooting out of cover, and the ambush on top of it. "First attack from cover"
## and "an attack from cover" are the same thing in practice — a unit acts once
## per turn — so this does not carry per-unit state it would then have to save
## and restore. The two stack additively, like every other bonus the formula
## reads.
func attack_bonus(state: GameState, fight: Engagement) -> int:
	if not _is_cover(state, fight.attacker_cell):
		return 0
	if _is_active(state, fight.attacker.team):
		return cover_attack_pct + ambush_attack_pct
	return cover_attack_pct


func hides_unit(state: GameState, unit: Unit) -> bool:
	return _is_active(state, unit.team) and _is_cover(state, unit.cell)


## An ambush is spent on the opponent's turn, so it is gated on theirs: it fires
## when an enemy can reach her line, not when she can reach one. It also needs
## somewhere to hide — with nobody in cover both halves of Vanish are no-ops, and
## a banked meter is worth more than a power that does nothing.
func wants_power(state: GameState, team: int) -> bool:
	if not _has_unit_in_cover(state, team):
		return false
	return _opponents_can_strike(state, team, false)


## Ground advice: her army is worth more in cover, so a quiet move prefers to
## end there — mildly while the meter fills, strongly once Vanish is banked or
## up. The strong case is what breaks the Vanish stall: wants_power above
## refuses to fire with nobody in cover, and without this the planner never put
## anyone there, so an open-map Wren sat on a full meter all match. Preference
## only, never priced off the ambush damage — the forecasts already carry that.
func stand_value(state: GameState, unit: Unit, cell: Vector2i) -> int:
	if not _is_cover(state, cell):
		return 0
	if _power_banked(state, unit.team):
		return vanish_stand_tiles
	return cover_stand_tiles


func _has_unit_in_cover(state: GameState, team: int) -> bool:
	for unit in _fielded_units(state, team):
		if _is_cover(state, unit.cell):
			return true
	return false


## Her whole identity rides the same rule Vision hides a unit under, so cover is
## asked of the terrain's own `conceals` flag rather than a woods id — a reef is
## exactly as much cover to her as a wood, on any board that has one and not the
## other.
func _is_cover(state: GameState, cell: Vector2i) -> bool:
	var terrain := state.map.terrain_at(cell)
	return terrain != null and terrain.conceals
