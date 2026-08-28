extends GutTest
## Perrin Ash: only air units move off the neutral combat line.


func _state(map_text: String, commander: bool = true) -> GameState:
	return Fixture.state(map_text, {1: &"perrin_ash"} if commander else {})


func _damage(state: GameState) -> int:
	var result := CombatResolver.forecast(
		state, state.units[0], state.units[0].cell, state.units[1]
	)
	return result.attack_damage


func test_air_attack_reaches_twenty_while_the_power_runs() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 h 0 0\n2 i 1 0")
	var co := state.commander_of(1)
	var fight := Engagement.create(
		state.units[0], Vector2i.ZERO, 10, state.units[1], Vector2i(1, 0), 10
	)
	assert_eq(co.attack_bonus(state, fight), 10)
	state.add_charge(1, co.power_cost)
	PowerCommand.new().apply(state)
	assert_eq(co.attack_bonus(state, fight), 20)
	EndTurnCommand.new().apply(state)
	assert_true(state.power_active(1), "the air cover lasts through the opposing turn")


func test_land_only_combat_is_bit_identical_to_neutral() -> void:
	var map_text := Fixture.TANK_VS_INFANTRY
	assert_eq(_damage(_state(map_text)), _damage(_state(map_text, false)))


func test_air_superiority_holds_with_no_aircraft() -> void:
	var state := _state(Fixture.TANK_VS_INFANTRY)
	assert_true(CommanderType.neutral().wants_power(state, 1), "contact: the default fires here")
	assert_false(state.commander_of(1).wants_power(state, 1), "no aircraft, nothing to cover")


func test_air_superiority_fires_with_a_copter_in_the_army() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 1 0\n1 h 2 0")
	assert_true(state.commander_of(1).wants_power(state, 1), "an aircraft is a reason to fire")


func _retuned_domain(state: GameState, domain: StringName) -> PerrinAsh:
	var co: PerrinAsh = state.commander_of(1).duplicate()  # never the shared DB resource
	co.superiority_domain = domain
	state.set_commander(1, co)
	return co


func test_the_gate_follows_the_configured_superiority_domain() -> void:
	var state := _state(Fixture.TANK_VS_INFANTRY)
	var co := _retuned_domain(state, UnitType.LAND)
	assert_true(co.wants_power(state, 1), "the army is all of the domain the power now covers")


func test_the_power_bonus_follows_the_configured_superiority_domain() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 1 0\n1 h 2 0")
	var co := _retuned_domain(state, UnitType.LAND)
	var enemy := state.units[1]
	var tank := Engagement.create(state.units[0], Vector2i.ZERO, 10, enemy, Vector2i(1, 0), 10)
	var copter := Engagement.create(state.units[2], Vector2i(2, 0), 10, enemy, Vector2i(1, 0), 10)
	state.add_charge(1, co.power_cost)
	PowerCommand.new().apply(state)
	assert_eq(co.attack_bonus(state, tank), co.superiority_attack_pct, "the covered domain gains")
	assert_eq(
		co.attack_bonus(state, copter), co.air_attack_pct, "the air passive, and nothing more"
	)


func test_an_aircraft_that_has_acted_still_wants_the_round_power() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 1 0\n1 h 2 0")
	state.units[2].acted = true
	assert_true(
		state.commander_of(1).wants_power(state, 1),
		"the cover is up through the opposing turn, so a spent flight still counters harder"
	)
