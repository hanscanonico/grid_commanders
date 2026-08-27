extends GutTest


func test_move_and_fire_applies() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 t 0 0\n2 i 2 0")
	state.rng.seed = 42
	var tank := state.units[0]
	var infantry := state.units[1]
	var command := AttackCommand.new(
		tank, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]), Vector2i(2, 0)
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(tank.cell, Vector2i(1, 0))
	assert_true(tank.acted)
	assert_not_null(command.result)
	assert_lt(infantry.hp, 100)


func test_fire_in_place_applies() -> void:
	var state := Fixture.state(Fixture.TANK_VS_INFANTRY)
	state.rng.seed = 42
	var command := AttackCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(state.units[0].acted)


func test_target_out_of_range_rejected() -> void:
	var state := Fixture.state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 2 0")
	var command := AttackCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)]), Vector2i(2, 0))
	assert_eq(command.validate(state), "target out of range")


func test_friendly_target_rejected() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 t 0 0\n1 i 1 0")
	var command := AttackCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "cannot attack a unit on your own side")


func test_empty_target_cell_rejected() -> void:
	var state := Fixture.state(Fixture.LONE_TANK)
	var command := AttackCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "no unit at the target cell")


func test_unarmed_unit_rejected() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 p 0 0\n2 i 1 0")
	var command := AttackCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "unit is unarmed")


func test_indirect_cannot_move_and_fire() -> void:
	var state := Fixture.state("[terrain]\n.....\n[units]\n1 g 0 0\n2 t 3 0")
	var command := AttackCommand.new(
		state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]), Vector2i(3, 0)
	)
	assert_eq(command.validate(state), "indirect units cannot move and fire")


func test_indirect_fires_within_ring() -> void:
	var state := Fixture.state(Fixture.ARTILLERY_VS_TANK)
	state.rng.seed = 8
	var command := AttackCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)]), Vector2i(2, 0))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_false(command.result.countered, "no counter against ranged fire")


func test_indirect_minimum_range_enforced() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 g 0 0\n2 t 1 0")
	var command := AttackCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "target out of range")


func test_acted_unit_rejected_via_move_rules() -> void:
	var state := Fixture.state(Fixture.TANK_VS_INFANTRY)
	state.units[0].acted = true
	var command := AttackCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "unit has already acted")
