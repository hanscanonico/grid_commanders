extends GutTest
## The snapshots on CombatResult that exist for the battle cut-in and for
## nothing else (battle-animations plan D1 and secondary-weapons plan D3).
##
## Split out of test_combat_resolver.gd because it is a different question. That
## file pins the *formula*; this one pins the record of what the formula was
## handed — the only part of the exchange the presentation layer is allowed to
## replay, and the only reason core/ knows the cut-in exists at all.
##
## Worth its own tests because a wrong snapshot is invisible in play: the cut-in
## would tick down from the wrong number and still look perfectly plausible.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


## The animation is handed the result *after* the command applied, so both units
## already hold their post-combat HP. The snapshot is the only record of what
## they went in with.
func test_resolve_snapshots_the_hp_both_sides_went_in_with() -> void:
	var state := Fixture.state(Fixture.TANK_VS_INFANTRY)
	state.rng.seed = 11
	var attacker := state.units[0]
	var defender := state.units[1]
	attacker.hp = 55  # 6 displayed
	defender.hp = 74  # 8 displayed
	var result := CombatResolver.resolve(state, attacker, defender)
	assert_eq(result.attacker_hp_before, 6, "displayed HP, not internal")
	assert_eq(result.defender_hp_before, 8, "displayed HP, not internal")
	assert_lt(
		defender.displayed_hp(), result.defender_hp_before, "the unit itself has already moved on"
	)


## The one case with nothing left to read off the unit: a dead defender is gone
## from the state, so the cut-in's entire "this side was still standing a moment
## ago" comes from the snapshot.
func test_resolve_snapshots_survive_a_kill() -> void:
	var state := Fixture.state(Fixture.TANK_VS_INFANTRY)
	state.rng.seed = 7
	var defender := state.units[1]
	defender.hp = 10  # any hit kills
	var result := CombatResolver.resolve(state, state.units[0], defender)
	assert_true(result.defender_died)
	assert_eq(result.defender_hp_before, 1)
	assert_eq(result.attacker_hp_before, 10)
	assert_eq(defender.displayed_hp(), 0)


## The snapshot is taken off the Engagement the formula resolves, so it describes
## that exchange and no other. An indirect attack — no counter, no reply — still
## records both sides, because the cut-in stages both halves either way.
func test_resolve_snapshots_an_unanswered_volley() -> void:
	var state := Fixture.state(Fixture.ARTILLERY_VS_TANK)
	state.rng.seed = 3
	var attacker := state.units[0]
	attacker.hp = 41  # 5 displayed
	var result := CombatResolver.resolve(state, attacker, state.units[1])
	assert_false(result.countered)
	assert_eq(result.attacker_hp_before, 5)
	assert_eq(result.defender_hp_before, 10)
	assert_eq(attacker.displayed_hp(), 5, "nothing shot back, so the attacker is untouched")


## The other end of the same record. The cut-in ticks HP *down* to it, so both
## ends have to come off the result: reading the finish off the live unit worked
## only for as long as every caller handed over a result the board had already
## applied.
func test_resolve_snapshots_the_hp_both_sides_came_out_with() -> void:
	var state := Fixture.state("[terrain]\n==\n[units]\n1 t 0 0\n2 m 1 0")
	state.rng.seed = 11
	var attacker := state.units[0]
	var defender := state.units[1]
	var result := CombatResolver.resolve(state, attacker, defender)
	assert_true(result.countered, "this pairing shoots back")
	assert_eq(result.defender_hp_after, defender.displayed_hp())
	assert_eq(result.attacker_hp_after, attacker.displayed_hp())
	assert_lt(result.defender_hp_after, result.defender_hp_before)
	assert_lt(result.attacker_hp_after, result.attacker_hp_before)


## A killed unit leaves the state, and an unanswered volley leaves the attacker
## untouched: the two ends of the range the after-snapshot has to cover.
func test_resolve_snapshots_a_kill_and_an_unanswered_volley() -> void:
	var state := Fixture.state(Fixture.TANK_VS_INFANTRY)
	state.rng.seed = 7
	var defender := state.units[1]
	defender.hp = 10  # any hit kills
	var result := CombatResolver.resolve(state, state.units[0], defender)
	assert_true(result.defender_died)
	assert_eq(result.defender_hp_after, 0)
	assert_eq(result.attacker_hp_after, result.attacker_hp_before, "nothing shot back")


## Whether the shot was lobbed is the rules' answer, recorded at the moment they
## gave it. The cut-in arcs an indirect round higher, and asking AttackRange again
## at replay time is the second opinion the plan's D1 forbids.
func test_resolve_snapshots_whether_the_opening_shot_was_lobbed() -> void:
	var flat := Fixture.state(Fixture.TANK_VS_INFANTRY)
	flat.rng.seed = 3
	assert_false(CombatResolver.resolve(flat, flat.units[0], flat.units[1]).attacker_indirect)
	var lobbed := Fixture.state(Fixture.ARTILLERY_VS_TANK)
	lobbed.rng.seed = 3
	var result := CombatResolver.resolve(lobbed, lobbed.units[0], lobbed.units[1])
	assert_true(result.attacker_indirect)
	assert_false(result.countered, "and an indirect shot is never answered, so never lobbed back")


## The weapon pair is replay data just like HP. Tank chooses its MG against a
## Mech, while the surviving stocked Mech independently chooses its bazooka.
func test_resolve_snapshots_each_sides_independent_weapon_slot() -> void:
	var state := Fixture.state("[terrain]\n==\n[units]\n1 t 0 0\n2 m 1 0")
	state.rng.seed = 11
	var tank := state.units[0]
	var mech := state.units[1]
	var result := CombatResolver.resolve(state, tank, mech)
	assert_true(result.countered)
	assert_eq(result.attacker_weapon_slot, DamageChart.SECONDARY)
	assert_eq(result.counter_weapon_slot, DamageChart.PRIMARY)
	assert_eq(tank.ammo, tank.type.max_ammo, "the MG spent no cannon round")
	assert_eq(mech.ammo, mech.type.max_ammo - 1, "the bazooka spent one primary round")
