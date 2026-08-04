extends GutTest


func test_valid_move_applies() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 i 0 0")
	var unit := state.units[0]
	var command := MoveCommand.new(
		unit, Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(unit.cell, Vector2i(2, 0))
	assert_true(unit.acted)


func test_wait_in_place_is_a_single_cell_path() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 i 0 0")
	var unit := state.units[0]
	var command := MoveCommand.new(unit, Fixture.path([Vector2i(0, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(unit.cell, Vector2i(0, 0))
	assert_true(unit.acted)


func test_acted_unit_is_rejected() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 i 0 0")
	var unit := state.units[0]
	unit.acted = true
	var command := MoveCommand.new(unit, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_eq(command.validate(state), "unit has already acted")


func test_path_must_start_at_unit_cell() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 i 0 0")
	var command := MoveCommand.new(state.units[0], Fixture.path([Vector2i(1, 0), Vector2i(2, 0)]))
	assert_eq(command.validate(state), "path must start at the unit's cell")


func test_non_contiguous_path_is_rejected() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 i 0 0")
	var command := MoveCommand.new(state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(2, 0)]))
	assert_eq(command.validate(state), "path is not contiguous")


func test_path_exceeding_movement_is_rejected() -> void:
	# infantry has 3 movement; a 4-step path is too long
	var state := Fixture.state("[terrain]\n......\n[units]\n1 i 0 0")
	var command := (
		MoveCommand
		. new(
			state.units[0],
			(
				Fixture
				. path(
					[
						Vector2i(0, 0),
						Vector2i(1, 0),
						Vector2i(2, 0),
						Vector2i(3, 0),
						Vector2i(4, 0),
					]
				)
			)
		)
	)
	assert_eq(command.validate(state), "path exceeds movement points")


func test_path_through_enemy_is_rejected() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 i 0 0\n2 i 1 0")
	var command := (
		MoveCommand
		. new(
			state.units[0],
			(
				Fixture
				. path(
					[
						Vector2i(0, 0),
						Vector2i(1, 0),
						Vector2i(2, 0),
					]
				)
			)
		)
	)
	assert_eq(command.validate(state), "path is blocked by an enemy")


func test_stopping_on_friendly_is_rejected() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 i 0 0\n1 i 1 0")
	var command := MoveCommand.new(state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_eq(command.validate(state), "destination is occupied")


func test_impassable_terrain_is_rejected() -> void:
	# tank cannot enter mountains
	var state := Fixture.state("[terrain]\n.M\n[units]\n1 t 0 0")
	var command := MoveCommand.new(state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_eq(command.validate(state), "path crosses impassable terrain")
