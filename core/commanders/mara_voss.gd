class_name MaraVoss
extends CommanderType
## Meridian Coalition. A defensive doctrine: her direct units punish being
## attacked and are mediocre at starting fights, so she wants the opponent to
## come to her. Hold the Line is the only ROUND power on the
## roster — it has to survive her own end of turn to cover the turn it exists to
## defend against.
##
## The first doctrine to read Engagement.is_counter, which is why the flag is on
## the exchange rather than inferred by the resolver.

@export var counter_attack_pct: int = 20
## Negative on purpose: she is paid to receive attacks, not to open them.
@export var initiate_attack_pct: int = -10
@export var hold_defense_pct: int = 30
@export var hold_counter_pct: int = 40
## Tiles of progress a quiet move gives up per defence star of the ground it
## ends on, while an enemy can actually come to her.
@export var hold_stand_tiles_per_star: int = 1


## Indirect units never counter at all, so neither half applies to them.
func attack_bonus(state: GameState, fight: Engagement) -> int:
	if AttackRange.is_indirect(fight.attacker):
		return 0
	if not fight.is_counter:
		return initiate_attack_pct
	var bonus := counter_attack_pct
	if _is_active(state, fight.attacker.team):
		bonus += hold_counter_pct
	return bonus


func defense_bonus(state: GameState, fight: Engagement) -> int:
	return hold_defense_pct if _is_active(state, fight.defender.team) else 0


## Gated on the opponent's reach rather than her own, which is the whole point
## of her: Hold the Line fires when an enemy can get to her, not when she can
## get to an enemy. The default offensive read leaves a commander built to be
## attacked banking a meter she never spends, because the turn she wants to
## spend it on is the one she is not playing.
func wants_power(state: GameState, team: int) -> bool:
	return _opponents_can_strike(state, team, false)


## Ground advice: when an enemy can reach the cell — and only then — a direct
## unit receives the fight on the best-covered ground available. Out of contact
## she marches like anyone else: a defensive doctrine is not a refusal to
## advance. Indirect units sit it out, like both halves of her combat doctrine.
func stand_value(state: GameState, unit: Unit, cell: Vector2i) -> int:
	if unit.type.max_range <= 0 or AttackRange.is_indirect(unit):
		return 0
	var terrain := state.map.terrain_at(cell)
	if terrain == null or terrain.defense_stars <= 0:
		return 0
	if not _enemy_can_reach(state, unit.team, cell):
		return 0
	return hold_stand_tiles_per_star * terrain.defense_stars


## True when any enemy this team can see could bring `cell` under fire next
## turn. `stand_value` asks this once per candidate cell an advancing unit is
## weighing, so the whole opponent set is graded in one pass over `state.units`:
## asking army by army was rescanning the board once per rival for an answer
## that only cares whether *any* of them reaches. Who counts as a shooter is
## `_is_striker`'s, so this and the powers' own gate read one skip list.
func _enemy_can_reach(state: GameState, team: int, cell: Vector2i) -> bool:
	var opponents := _opponents_of(state, team)
	for unit in state.units:
		if not _is_striker(state, team, unit, opponents, false):
			continue
		if Grid.manhattan(unit.cell, cell) <= AttackRange.strike_reach(state, unit):
			return true
	return false
