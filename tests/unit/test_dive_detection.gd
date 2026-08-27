extends GutTest
## What can still see and shoot a dived hull: AttackRange.can_engage and
## Vision.is_hidden_from.
##
## The sibling of tests/unit/test_dive.gd, which owns the submarine's own rules,
## and of tests/unit/test_dive_planner.gd, which owns what the computer does with
## them. A dived boat that is still targetable is a sub with an expensive
## downside and no upside; one that is hidden but still counterattacks gives
## itself away for free. So each is asserted separately here rather than trusted
## to the one flag they all read.

# --- targeting ----------------------------------------------------------------


## Only a weapon built to hunt a submarine reaches one. That is the whole payoff
## of diving, and it has to hold in the command that validates the shot — the
## planner and the targeting overlay ask the same authority.
func test_only_a_hunter_can_engage_a_dived_sub() -> void:
	var state := Fixture.state("[terrain]\nSSS\n[units]\n1 s 1 0\n2 B 0 0\n2 c 2 0")
	var sub := state.units[0]
	sub.dived = true
	EndTurnCommand.new().apply(state)  # blue's turn
	var battleship := state.units[1]
	var cruiser := state.units[2]
	assert_false(
		AttackRange.can_engage(state, battleship, sub), "a battleship's guns do not reach under"
	)
	assert_true(AttackRange.can_engage(state, cruiser, sub), "a cruiser is built for exactly this")
	assert_eq(
		AttackCommand.new(cruiser, Fixture.path([Vector2i(2, 0)]), Vector2i(1, 0)).validate(state),
		""
	)


func test_surfacing_makes_the_sub_targetable_again() -> void:
	var state := Fixture.state("[terrain]\nSS\n[units]\n1 s 1 0\n2 B 0 0")
	var sub := state.units[0]
	var battleship := state.units[1]
	sub.dived = true
	assert_false(AttackRange.can_engage(state, battleship, sub))
	sub.dived = false
	assert_true(AttackRange.can_engage(state, battleship, sub))


## A boat that shot back would give itself away, so it does not — which is what
## makes attacking from under the water worth the fuel.
func test_a_dived_sub_does_not_counterattack() -> void:
	var state := Fixture.state("[terrain]\nSS\n[units]\n1 s 1 0\n2 c 0 0")
	state.rng.seed = 3
	var sub := state.units[0]
	sub.dived = true
	EndTurnCommand.new().apply(state)
	var result := CombatResolver.resolve(state, state.units[1], sub)
	assert_gt(result.attack_damage, 0, "the cruiser should have hit it")
	assert_false(result.countered)


## And the mirror: a submerged attacker is countered only by something that could
## have engaged it in the first place.
func test_only_a_hunter_counters_a_submerged_attacker() -> void:
	var state := Fixture.state("[terrain]\nSSS\n[units]\n1 s 1 0\n2 B 0 0\n2 c 2 0")
	state.rng.seed = 3
	var sub := state.units[0]
	sub.dived = true
	var against_battleship := CombatResolver.resolve(state, sub, state.units[1])
	assert_false(
		against_battleship.countered, "a battleship cannot shoot back at what it cannot see"
	)
	sub.ammo = sub.type.max_ammo
	var against_cruiser := CombatResolver.resolve(state, sub, state.units[2])
	assert_true(against_cruiser.countered, "the escort can and does")


# --- vision -------------------------------------------------------------------


## Being under the water is not a question of how far anyone can see, so unlike
## every other hiding rule this one holds in a match with no fog at all.
func test_a_dived_sub_is_hidden_without_fog() -> void:
	var state := Fixture.state("[terrain]\nSSSS\n[units]\n1 s 0 0\n2 B 3 0")
	var sub := state.units[0]
	sub.dived = true
	assert_false(state.fog_enabled, "this is the clear-weather case on purpose")
	assert_true(Vision.is_hidden_from(state, 2, sub))
	assert_false(Vision.can_see_unit(state, 2, sub, Vision.visible_cells(state, 2)))
	assert_true(
		Vision.can_see_unit(state, 1, sub, Vision.visible_cells(state, 1)),
		"its own side always knows where it is"
	)


## Hunting a submarine means closing with it: standing next to one gives it up.
func test_an_adjacent_enemy_finds_a_dived_sub() -> void:
	var state := Fixture.state("[terrain]\nSSS\n[units]\n1 s 1 0\n2 c 2 0")
	var sub := state.units[0]
	sub.dived = true
	assert_false(Vision.is_hidden_from(state, 2, sub), "the cruiser is right on top of it")
	MoveCommand.new(state.units[1], Fixture.path([Vector2i(2, 0)])).apply(state)
	assert_false(Vision.is_hidden_from(state, 2, sub))


func test_a_surfaced_sub_hides_from_nobody() -> void:
	var state := Fixture.state("[terrain]\nSSSS\n[units]\n1 s 0 0\n2 B 3 0")
	assert_false(Vision.is_hidden_from(state, 2, state.units[0]))
