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
## standing on the tile under it and gets none — see _cover_stars. Ground and sea
## units read the terrain exactly as they always did.
##
## Damage% subtracts internal HP (0-100) directly. Luck comes from the
## GameState's seeded RNG, and its bounds come from the attacking commander, so
## matches stay deterministic and replayable either way.
##
## Both forecast() and resolve() go through _damage_pct, which is what keeps the
## damage preview honest about doctrines for free.

const LUCK_MAX := CommanderType.LUCK_MAX


class Forecast:
	var can_attack := false
	var attack_damage := 0
	## -1 when no counter is possible (defender dead, indirect, unarmed
	## against the attacker, or the attacker fires from beyond range 1).
	var counter_damage := -1
	## The same exchange in displayed HP (1-10) — the unit every other HP display
	## in the game speaks, and so the unit the damage preview leads with.
	##
	## `_after_min` / `_after_max` bound the HP a side is left standing at across
	## the luck range `resolve` rolls inside, worst and best case for its owner.
	## The attacker's span answers for the opening roll as well as the counter's:
	## a luckier shot leaves the defender a weaker band to shoot back from, and a
	## lethal one means no counter at all, so the best case is taken from the
	## luckiest shot and the worst from the unluckiest. The percentages above stay
	## luck-free, so they are a *floor* under a doctrine with a lucky floor; these
	## bounds are not.
	##
	## Filled by the same pass that fills the percentages, for the same reason
	## CombatResult snapshots the HP the cut-in counts down from: the preview
	## replays the resolver's arithmetic and never repeats it. With no counter
	## the attacker's three numbers are all its current HP. Nothing in core/ or
	## ai/ reads these.
	var attacker_hp_before := 0
	var attacker_hp_after_min := 0
	var attacker_hp_after_max := 0
	var defender_hp_before := 0
	var defender_hp_after_min := 0
	var defender_hp_after_max := 0


class CombatResult:
	var attack_damage := 0
	var countered := false
	var counter_damage := 0
	var defender_died := false
	var attacker_died := false
	## Displayed HP (1-10) each side went into the exchange with, snapshotted by
	## `resolve` before a point of it is spent.
	##
	## The only thing in this file that exists for the presentation layer. By the
	## time the battle cut-in is handed a result the command has already applied,
	## so both units hold their *post*-combat HP and the animation has nothing to
	## count down from. Recorded here rather than re-derived there, because the
	## cut-in must replay the exchange and never recompute it — a second opinion
	## on combat is exactly the bug class this repo already paid for once with
	## movement. Nothing in core/ or ai/ reads these.
	var attacker_hp_before := 0
	var defender_hp_before := 0


## Luck-free prediction for the damage preview. `attacker_cell` is the planned
## firing position (the move is usually not committed yet). The counter uses
## the defender's projected post-attack HP, like Advance Wars shows it — the
## luck-free one, so the counter's own HP spread is its roll and not the
## opening shot's compounded into it.
static func forecast(
	state: GameState, attacker: Unit, attacker_cell: Vector2i, defender: Unit
) -> Forecast:
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
) -> Forecast:
	var result := Forecast.new()
	if not attacker.has_ammo():
		return result
	var shot := Engagement.create(
		attacker,
		attacker_cell,
		attacker.displayed_hp(),
		defender,
		defender_cell,
		defender.displayed_hp()
	)
	var damage := _damage_pct(state, shot)
	if damage < 0:
		return result
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
	if (
		hp_after > 0
		and _defender_can_counter(state, defender, defender_cell, attacker, attacker_cell)
	):
		var counter := Engagement.create(
			defender,
			defender_cell,
			ceili(hp_after / 10.0),
			attacker,
			attacker_cell,
			attacker.displayed_hp(),
			true
		)
		var counter_damage := _damage_pct(state, counter)
		if counter_damage >= 0:
			result.counter_damage = counter_damage
			# Worst case: the unluckiest shot leaves the defender the strongest
			# band it can answer from, which is the luck-free one the percentage
			# above is already projected off.
			result.attacker_hp_after_min = _hp_after(
				attacker.hp, counter_damage + _luck_bounds(state, counter).y
			)
			result.attacker_hp_after_max = _counter_best_case(
				state, counter, counter_damage, defender.hp - damage - shot_luck.y
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
	state: GameState, counter: Engagement, counter_damage: int, defender_left: int
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
	var weakened := _damage_pct(state, luckiest)
	if weakened < 0:
		return attacker.displayed_hp()
	return _hp_after(attacker.hp, weakened + _luck_bounds(state, luckiest).x)


## Applies the attack (with luck), then the counter-attack if the defender
## survives and can reach. Dead units are removed from the state, and both sides
## bank Command Power charge for the HP that changed hands.
static func resolve(state: GameState, attacker: Unit, defender: Unit) -> CombatResult:
	var result := CombatResult.new()
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
	var base := _damage_pct(state, fight)
	if base < 0:
		push_error("CombatResolver: %s cannot attack %s" % [attacker.type.id, defender.type.id])
		return result
	if attacker.type.max_ammo > 0:
		attacker.ammo = maxi(0, attacker.ammo - 1)
	result.attack_damage = base + _luck(state, fight)
	# Banked before the unit is removed: a kill charges for the HP it actually
	# took off, not for the overkill the roll happened to produce.
	state.bank_losses(defender, mini(result.attack_damage, defender.hp), attacker.team)
	defender.hp = maxi(0, defender.hp - result.attack_damage)
	if defender.hp == 0:
		result.defender_died = true
		_bank_cargo_losses(state, defender, attacker.team)
		state.remove_unit(defender)
		return result
	if not _defender_can_counter(state, defender, defender.cell, attacker, attacker.cell):
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
	var counter_base := _damage_pct(state, counter)
	if counter_base < 0:
		return result
	if defender.type.max_ammo > 0:
		defender.ammo = maxi(0, defender.ammo - 1)
	result.countered = true
	result.counter_damage = counter_base + _luck(state, counter)
	state.bank_losses(attacker, mini(result.counter_damage, attacker.hp), defender.team)
	attacker.hp = maxi(0, attacker.hp - result.counter_damage)
	if attacker.hp == 0:
		result.attacker_died = true
		_bank_cargo_losses(state, attacker, defender.team)
		state.remove_unit(attacker)
	return result


## Cargo that drowns with its transport banks the same as if each passenger had
## been killed in the open: the value basis is the passenger's remaining HP
## fraction of its cost, split by the same loser/dealer rates bank_losses gives
## the transport itself. Recurses because remove_unit's erase does — an old save
## may nest transports even though the load commands now refuse it. This runs
## before remove_unit so cargo_of can still see the passengers, and stays here in
## the resolver where every other charge accrual lives; the fuel-crash death in
## turn_rules erases cargo without a fight and deliberately banks nothing.
static func _bank_cargo_losses(state: GameState, transport: Unit, dealer_team: int) -> void:
	for passenger in state.cargo_of(transport):
		state.bank_losses(passenger, passenger.hp, dealer_team)
		_bank_cargo_losses(state, passenger, dealer_team)


static func _defender_can_counter(
	state: GameState,
	defender: Unit,
	defender_cell: Vector2i,
	attacker: Unit,
	attacker_cell: Vector2i
) -> bool:
	# Deliberately the unit type's own range rather than AttackRange: countering
	# is adjacency, and a doctrine that extends how far a unit can *initiate*
	# must not turn an indirect into something that shoots back. Only the
	# distance is decided here, though — whether the shot is possible at all is
	# AttackRange's, below.
	if defender.type.max_range != 1:
		return false  # unarmed and indirect units never counter
	if not defender.has_ammo():
		return false
	if defender.dived:
		return false  # a submarine that is hiding does not give itself away
	var dist := absi(attacker_cell.x - defender_cell.x) + absi(attacker_cell.y - defender_cell.y)
	if dist != 1:
		return false  # an indirect attacker fires from beyond counter reach
	# The same authority the opening shot went through, which is what gives the
	# dive its edge: a submerged attacker is countered only by a hunter that can
	# reach under the surface, and shrugged at by everything else.
	return AttackRange.can_engage(state, defender, attacker)


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


## The terrain cover the defender actually gets. A unit in the air is over the
## tile rather than on it, so mountains and woods do nothing for it — the one
## place the formula asks what a defender *is* instead of only where it stands.
##
## Deliberately only the terrain half: a commander's star_bonus is still added on
## top by the caller, so a doctrine that hardens its army hardens its planes with
## it. What the ground gives is the part a plane is not entitled to.
static func _cover_stars(state: GameState, fight: Engagement) -> int:
	if fight.defender.type.domain == UnitType.AIR:
		return 0
	return state.map.terrain_at(fight.defender_cell).defense_stars


static func _damage_pct(state: GameState, fight: Engagement) -> int:
	var base := state.damage_chart.base_damage(fight.attacker.type.id, fight.defender.type.id)
	if base < 0:
		return -1
	var att_co := state.commander_of(fight.attacker.team)
	var def_co := state.commander_of(fight.defender.team)
	var stars := clampi(
		(
			_cover_stars(state, fight)
			+ def_co.star_bonus(state, fight)
			- att_co.star_pierce(state, fight)
		),
		0,
		CommanderType.MAX_STARS
	)
	var att := 100 + att_co.attack_bonus(state, fight)
	var def := 100 + def_co.defense_bonus(state, fight)
	var raw := (
		base
		* (att / 100.0)
		* (fight.attacker_hp / 10.0)
		* (1.0 - 0.1 * stars * fight.defender_hp / 10.0)
		* ((200 - def) / 100.0)
	)
	return maxi(0, roundi(raw))
