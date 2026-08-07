class_name CombatResolver
extends RefCounted
## Resolves combat. The formula, normative — every general is balance-tested
## against exactly this chain, in exactly this order, with exactly one rounding
## at the end:
##
##   stars  = clamp(cover(defender) + def_co.star_bonus - att_co.star_pierce, 0, 5)
##   att    = 100 + att_co.attack_bonus
##   def    = 100 + def_co.defense_bonus
##   raw    = base(attacker, defender)
##            x att / 100
##            x attacker_displayed_hp / 10
##            x (1 - 0.1 x stars x defender_displayed_hp / 10)
##            x (200 - def) / 100
##   damage = max(0, round(raw))     + luck   [resolve only; forecast omits it]
##
## The (200 - def) / 100 term is the Advance Wars defence shape: +10 defence is
## x0.9 damage taken, -10 is x1.1. With the neutral commander both att and def
## are 100 and the two new terms are exactly 1.0, so a match with no CO resolves
## bit-for-bit as it did before commanders existed.
##
## `cover` is the defender's terrain stars, except that a unit in the air is not
## standing on the tile under it and gets none — see cover_stars. Ground and sea
## units read the terrain exactly as they always did.
##
## Damage% subtracts internal HP (0-100) directly. Luck comes from the
## GameState's seeded RNG, and its bounds come from the attacking commander, so
## matches stay deterministic and replayable either way.
##
## Both forecast() and resolve() go through _damage_pct, which is what keeps the
## damage preview honest about doctrines for free.

const LUCK_MAX := CommanderType.LUCK_MAX


## Luck-free prediction for the damage preview. `attacker_cell` is the planned
## firing position (the move is usually not committed yet). The counter uses
## the defender's projected post-attack HP, like Advance Wars shows it — the
## luck-free one, so the counter's own HP spread is its roll and not the
## opening shot's compounded into it.
static func forecast(
	state: GameState, attacker: Unit, attacker_cell: Vector2i, defender: Unit
) -> CombatSnapshot.Forecast:
	return forecast_at(state, attacker, attacker_cell, defender, defender.cell)


## The same prediction with the defender's position given explicitly, for a
## caller asking about a cell the defender has not moved to — the AI's threat
## map scoring "how hard am I hit if I stop here?".
##
## Both positions are effective values carried by Engagement, exactly like the
## attacker's planned firing cell, so asking the question moves nothing on the
## board: this is a pure query whatever cell it is asked about.
static func forecast_at(
	state: GameState,
	attacker: Unit,
	attacker_cell: Vector2i,
	defender: Unit,
	defender_cell: Vector2i
) -> CombatSnapshot.Forecast:
	var result := CombatSnapshot.Forecast.new()
	var selected := _select_shot(state, attacker, defender)
	if selected == null:
		return result
	var shot := Engagement.create(
		attacker,
		attacker_cell,
		attacker.displayed_hp(),
		defender,
		defender_cell,
		defender.displayed_hp()
	)
	var damage := _damage_pct(state, shot, selected.base_damage)
	var shot_luck := _luck_bounds(state, shot)
	result.can_attack = true
	result.attack_damage = damage
	result.attacker_hp_before = attacker.displayed_hp()
	result.defender_hp_before = defender.displayed_hp()
	# The luckiest roll takes the most off, so it is the *low* end of the HP the
	# defender is left standing at.
	result.defender_hp_after_min = _hp_after(defender.hp, damage + shot_luck.y)
	result.defender_hp_after_max = _hp_after(defender.hp, damage + shot_luck.x)
	result.attacker_hp_after_min = result.attacker_hp_before
	result.attacker_hp_after_max = result.attacker_hp_before
	var hp_after := maxi(0, defender.hp - damage)
	if hp_after > 0:
		var selected_counter := _counter_shot(
			state, defender, defender_cell, attacker, attacker_cell
		)
		if selected_counter == null:
			return result
		var counter := Engagement.create(
			defender,
			defender_cell,
			ceili(hp_after / 10.0),
			attacker,
			attacker_cell,
			attacker.displayed_hp(),
			true
		)
		var counter_damage := _damage_pct(state, counter, selected_counter.base_damage)
		result.counter_damage = counter_damage
		# Worst case: the unluckiest shot leaves the defender the strongest
		# band it can answer from, which is the luck-free one the percentage
		# above is already projected off.
		result.attacker_hp_after_min = _hp_after(
			attacker.hp, counter_damage + _luck_bounds(state, counter).y
		)
		result.attacker_hp_after_max = _counter_best_case(
			state,
			counter,
			selected_counter.base_damage,
			counter_damage,
			defender.hp - damage - shot_luck.y
		)
	return result


## The HP the attacker walks away with when the opening roll goes its way: the
## luckiest shot leaves `defender_left` internal HP to counter from, and the
## counter then rolls its own floor. A lethal shot is the best case of all —
## there is no counter to take. Costs at most one extra damage evaluation, and
## none at all when the luckiest roll lands in the same displayed band the
## luck-free one did, which is the common case; `forecast` is the AI's inner
## loop and pays for this on every candidate move.
static func _counter_best_case(
	state: GameState,
	counter: Engagement,
	counter_base_damage: int,
	counter_damage: int,
	defender_left: int
) -> int:
	var attacker := counter.defender
	if defender_left <= 0:
		return attacker.displayed_hp()
	var band := ceili(defender_left / 10.0)
	if band == counter.attacker_hp:
		return _hp_after(attacker.hp, counter_damage + _luck_bounds(state, counter).x)
	var luckiest := Engagement.create(
		counter.attacker,
		counter.attacker_cell,
		band,
		attacker,
		counter.defender_cell,
		counter.defender_hp,
		true
	)
	var weakened := _damage_pct(state, luckiest, counter_base_damage)
	return _hp_after(attacker.hp, weakened + _luck_bounds(state, luckiest).x)


## Applies the attack (with luck), then the counter-attack if the defender
## survives and can reach. Dead units are removed from the state, and both sides
## bank Command Power charge for the HP that changed hands.
static func resolve(
	state: GameState, attacker: Unit, defender: Unit
) -> CombatSnapshot.CombatResult:
	var result := CombatSnapshot.CombatResult.new()
	var selected := _select_shot(state, attacker, defender)
	if selected == null:
		push_error("CombatResolver: %s cannot attack %s" % [attacker.type.id, defender.type.id])
		return result
	var fight := Engagement.create(
		attacker,
		attacker.cell,
		attacker.displayed_hp(),
		defender,
		defender.cell,
		defender.displayed_hp()
	)
	# Taken off the Engagement, not the units: those are the effective values the
	# formula below is about to be resolved with, so the snapshot can never drift
	# from the exchange it describes.
	result.attacker_hp_before = fight.attacker_hp
	result.defender_hp_before = fight.defender_hp
	# The exchange has not spent anything yet, so each side comes out where it went
	# in until a shot below says otherwise.
	result.attacker_hp_after = fight.attacker_hp
	result.defender_hp_after = fight.defender_hp
	result.attacker_weapon_slot = selected.slot
	result.attacker_indirect = AttackRange.is_indirect(attacker)
	var base := _damage_pct(state, fight, selected.base_damage)
	if selected.consumes_primary_ammo:
		attacker.ammo = maxi(0, attacker.ammo - 1)
	result.attack_damage = base + _luck(state, fight)
	# Banked before the unit is removed: a kill charges for the HP it actually
	# took off, not for the overkill the roll happened to produce, and the ledger
	# can still see what a sinking transport is carrying.
	ChargeLedger.bank_losses(
		state, defender, mini(result.attack_damage, defender.hp), attacker.team
	)
	defender.hp = maxi(0, defender.hp - result.attack_damage)
	result.defender_hp_after = defender.displayed_hp()
	if defender.hp == 0:
		result.defender_died = true
		state.remove_unit(defender)
		return result
	var selected_counter := _counter_shot(state, defender, defender.cell, attacker, attacker.cell)
	if selected_counter == null:
		return result
	var counter := Engagement.create(
		defender,
		defender.cell,
		defender.displayed_hp(),
		attacker,
		attacker.cell,
		attacker.displayed_hp(),
		true
	)
	var counter_base := _damage_pct(state, counter, selected_counter.base_damage)
	result.counter_weapon_slot = selected_counter.slot
	if selected_counter.consumes_primary_ammo:
		defender.ammo = maxi(0, defender.ammo - 1)
	result.countered = true
	result.counter_damage = counter_base + _luck(state, counter)
	ChargeLedger.bank_losses(
		state, attacker, mini(result.counter_damage, attacker.hp), defender.team
	)
	attacker.hp = maxi(0, attacker.hp - result.counter_damage)
	result.attacker_hp_after = attacker.displayed_hp()
	if attacker.hp == 0:
		result.attacker_died = true
		state.remove_unit(attacker)
	return result


## The weapon the defender shoots back with, or null when it does not counter at
## all. One selection, handed to the caller that prices the counter — asking
## whether a counter happens and asking what it is fired with are the same
## question, and the forecast is the AI's inner loop.
static func _counter_shot(
	state: GameState,
	defender: Unit,
	defender_cell: Vector2i,
	attacker: Unit,
	attacker_cell: Vector2i
) -> DamageChart.Shot:
	# Deliberately the unit type's own range rather than AttackRange: countering
	# is adjacency, and a doctrine that extends how far a unit can *initiate*
	# must not turn an indirect into something that shoots back. Only the
	# distance is decided here, though — whether the shot is possible at all is
	# AttackRange's, below.
	if defender.type.max_range != 1:
		return null  # unarmed and indirect units never counter
	if defender.dived:
		return null  # a submarine that is hiding does not give itself away
	var dist := Grid.manhattan(attacker_cell, defender_cell)
	if dist != 1:
		return null  # an indirect attacker fires from beyond counter reach
	# The same authority the opening shot went through, which is what gives the
	# dive its edge: a submerged attacker is countered only by a hunter that can
	# reach under the surface, and shrugged at by everything else.
	return AttackRange.ready_shot(state, defender, attacker)


## One luck roll, from the attacking commander's range. Always exactly one draw
## from the match RNG whatever the range, so a doctrine that narrows luck cannot
## put a replay out of step with the seed it was recorded on.
static func _luck(state: GameState, fight: Engagement) -> int:
	var bounds := _luck_bounds(state, fight)
	return state.rng.randi_range(bounds.x, bounds.y)


## The `(min, max)` pair `_luck` rolls between, asked without drawing — what the
## forecast needs where `resolve` needs a number. One commander lookup and one
## call to each hook, so the preview's spread can never widen past the roll it is
## describing and the AI's inner loop pays for the answer once.
static func _luck_bounds(state: GameState, fight: Engagement) -> Vector2i:
	var att_co := state.commander_of(fight.attacker.team)
	var low := att_co.luck_min(state, fight)
	# A doctrine that raises its floor above the ceiling gets a fixed roll, not
	# an inverted range — the clamp `randi_range` has always been given.
	return Vector2i(low, maxi(low, att_co.luck_max(state, fight)))


## Displayed HP (0-10) a unit is left standing at after taking `damage`, from its
## internal HP. The resolver's own subtraction and the unit's own rounding, so a
## forecast and the exchange it forecasts cannot disagree about what a hit leaves
## behind.
static func _hp_after(hp: int, damage: int) -> int:
	return ceili(maxi(0, hp - damage) / 10.0)


## The terrain cover `unit` actually gets standing on `cell`. A unit in the air is
## over the tile rather than on it, so mountains and woods do nothing for it — the
## one place the formula asks what a defender *is* instead of only where it stands.
##
## Public because the AI planner prices ground defensively and must price the
## ground this formula gives, not a second reading of it: one answer to what
## cover a unit gets on a cell, asked here by both.
##
## Deliberately only the terrain half: a commander's star_bonus is still added on
## top by the caller, so a doctrine that hardens its army hardens its planes with
## it. What the ground gives is the part a plane is not entitled to.
static func cover_stars(state: GameState, unit: Unit, cell: Vector2i) -> int:
	if unit.type.domain == UnitType.AIR:
		return 0
	return state.map.terrain_at(cell).defense_stars


static func _damage_pct(state: GameState, fight: Engagement, base_damage: int) -> int:
	var att_co := state.commander_of(fight.attacker.team)
	var def_co := state.commander_of(fight.defender.team)
	var stars := clampi(
		(
			cover_stars(state, fight.defender, fight.defender_cell)
			+ def_co.star_bonus(state, fight)
			- att_co.star_pierce(state, fight)
		),
		0,
		CommanderType.MAX_STARS
	)
	var att := 100 + att_co.attack_bonus(state, fight)
	var def := 100 + def_co.defense_bonus(state, fight)
	var raw := (
		base_damage
		* (att / 100.0)
		* (fight.attacker_hp / 10.0)
		* (1.0 - 0.1 * stars * fight.defender_hp / 10.0)
		* ((200 - def) / 100.0)
	)
	return maxi(0, roundi(raw))


static func _select_shot(state: GameState, attacker: Unit, defender: Unit) -> DamageChart.Shot:
	# The same authority the counter already goes through: a submerged target
	# is engaged only by a hunter, and asking the chart directly here would let
	# the opening shot see past that gate the counter cannot.
	return AttackRange.ready_shot(state, attacker, defender)
