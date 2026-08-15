extends GutTest
## ThreatMap's own rules, asked of the class directly: who gets into the map at
## all, how an enemy that reaches a cell from several directions is counted, and
## the ceiling on what one cell can cost. test_ai_smarts.gd exercises the map
## through the planner; these are the rules underneath it, which the planner can
## keep passing while any of them quietly breaks.


## A transport carries no weapon, so it has no firing ring to walk and nothing to
## be afraid of. build() drops it on max_range before it ever asks the resolver.
func test_an_unarmed_transport_threatens_nothing() -> void:
	var state := Fixture.state("[terrain]\n.....\n[units]\n1 i 0 0\n2 p 4 0")
	var infantry := state.units_of(1)[0]
	var map := ThreatMap.build(state, state.units_of(2))
	for x in 5:
		assert_eq(
			map.incoming_damage(state, infantry, Vector2i(x, 0)),
			0,
			"an APC threatens cell (%d, 0) with nothing" % x
		)


## Artillery carries one stocked weapon and no infinite-ammo secondary, so a dry
## one has nothing to shoot with and leaves the map entirely rather than being
## priced at zero. The same board with the shells still aboard is the control:
## the gate is the ammo, not the geometry.
func test_a_dry_enemy_with_no_secondary_drops_out_of_the_map() -> void:
	var board := "[terrain]\n.......\n[units]\n1 i 0 0\n2 g 3 0"

	var stocked := Fixture.state(board)
	var armed_map := ThreatMap.build(stocked, stocked.units_of(2))
	assert_gt(
		armed_map.incoming_damage(stocked, stocked.units_of(1)[0], Vector2i(0, 0)),
		0,
		"an artillery with shells threatens the infantry it is ranged on"
	)

	var empty := Fixture.state(board)
	empty.units_of(2)[0].ammo = 0
	var dry_map := ThreatMap.build(empty, empty.units_of(2))
	assert_eq(
		dry_map.incoming_damage(empty, empty.units_of(1)[0], Vector2i(0, 0)),
		0,
		"a dry artillery has no ready weapon, so it threatens nothing"
	)


## A direct unit reaches most cells from more than one firing position — this
## tank can shoot (3, 0) from either side of it — and _mark_ring must record the
## enemy once however many of them land on the cell, or the cell is priced at two
## shots the tank can only fire one of.
func test_an_enemy_reaching_a_cell_twice_is_counted_once() -> void:
	var state := Fixture.state("[terrain]\n........\n[units]\n1 i 0 0\n2 t 6 0")
	var infantry := state.units_of(1)[0]
	var tank := state.units_of(2)[0]
	var firing := AttackRange.firing_cells(state, tank)
	assert_true(Vector2i(2, 0) in firing, "the tank can fire from the near side of (3, 0)")
	assert_true(Vector2i(4, 0) in firing, "and from the far side of it")

	var one_shot := CombatResolver.forecast_at(state, tank, tank.cell, infantry, Vector2i(3, 0))
	var map := ThreatMap.build(state, state.units_of(2))
	assert_eq(
		map.incoming_damage(state, infantry, Vector2i(3, 0)),
		one_shot.attack_damage,
		"two firing positions are one tank, so the cell costs one forecast"
	)


## Damage is summed over every enemy that threatens the cell, but a unit can only
## be killed once: the total is capped at the defender's HP so two overkilling
## attackers do not read as worse than the loss of the unit.
func test_the_summed_forecast_is_capped_at_the_defenders_hp() -> void:
	var state := Fixture.state("[terrain]\n.....\n.....\n.....\n[units]\n1 i 2 1\n2 t 0 1\n2 t 4 1")
	var infantry := state.units_of(1)[0]
	var raw := 0
	for tank in state.units_of(2):
		var shot := CombatResolver.forecast_at(state, tank, tank.cell, infantry, infantry.cell)
		raw += shot.attack_damage
	assert_gt(raw, infantry.hp, "the two tanks together must overkill for the cap to be tested")
	var map := ThreatMap.build(state, state.units_of(2))
	assert_eq(
		map.incoming_damage(state, infantry, infantry.cell),
		infantry.hp,
		"the cell costs the unit, never more than the unit"
	)
