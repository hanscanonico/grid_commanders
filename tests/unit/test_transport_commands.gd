extends GutTest


func test_load_boards_the_transport() -> void:
	var state := Fixture.state("[terrain]\n...\n[units]\n1 i 0 0\n1 p 1 0")
	var infantry := state.units[0]
	var apc := state.units[1]
	var command := LoadCommand.new(infantry, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(infantry.carrier, apc)
	assert_eq(infantry.cell, apc.cell)
	assert_true(infantry.acted)
	assert_eq(state.unit_at(Vector2i(1, 0)), apc, "cell lookups see the transport")
	assert_eq(state.cargo_of(apc), [infantry] as Array[Unit])


func test_load_rejects_vehicles_and_full_or_enemy_transports() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 t 0 0\n1 p 1 0\n1 i 2 0\n2 p 3 0")
	var tank := state.units[0]
	var apc := state.units[1]
	var infantry := state.units[2]
	assert_eq(
		LoadCommand.new(tank, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).validate(state),
		"unit cannot be transported"
	)
	infantry.carrier = apc
	infantry.cell = apc.cell
	var second := Unit.create(Fixture.unit_db().by_id(&"infantry"), 1, Vector2i(2, 0))
	state.units.append(second)
	assert_eq(
		LoadCommand.new(second, Fixture.path([Vector2i(2, 0), Vector2i(1, 0)])).validate(state),
		"transport is full"
	)
	assert_eq(
		LoadCommand.new(second, Fixture.path([Vector2i(2, 0), Vector2i(3, 0)])).validate(state),
		"path is blocked by an enemy",
		"enemy transports cannot even be entered"
	)


## The destination is where the command looks for a hull, so walking to bare
## ground is refused before `carriage_error` is ever asked.
func test_load_onto_an_empty_cell_rejected() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 i 0 0")
	assert_eq(
		LoadCommand.new(state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).validate(
			state
		),
		"no friendly transport at the destination"
	)


func test_cargo_rides_with_the_transport() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 i 0 0\n1 p 1 0")
	var infantry := state.units[0]
	var apc := state.units[1]
	LoadCommand.new(infantry, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).apply(state)
	apc.acted = false
	MoveCommand.new(apc, Fixture.path([Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])).apply(
		state
	)
	assert_eq(infantry.cell, Vector2i(3, 0))
	assert_eq(infantry.carrier, apc)


func test_drop_unloads_exhausted_passenger() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 i 0 0\n1 p 1 0")
	var infantry := state.units[0]
	var apc := state.units[1]
	LoadCommand.new(infantry, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).apply(state)
	apc.acted = false
	var command := DropCommand.new(
		apc, Fixture.path([Vector2i(1, 0), Vector2i(2, 0)]), Vector2i(3, 0)
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_null(infantry.carrier)
	assert_eq(infantry.cell, Vector2i(3, 0))
	assert_true(infantry.acted)
	assert_eq(state.unit_at(Vector2i(3, 0)), infantry)


func test_drop_rejections() -> void:
	var state := Fixture.state("[terrain]\n..S.\n[units]\n1 p 1 0\n1 i 0 0")
	var apc := state.units[0]
	var infantry := state.units[1]
	assert_eq(
		DropCommand.new(apc, Fixture.path([Vector2i(1, 0)]), Vector2i(0, 0)).validate(state),
		"nothing to drop"
	)
	infantry.carrier = apc
	infantry.cell = apc.cell
	assert_eq(
		DropCommand.new(apc, Fixture.path([Vector2i(1, 0)]), Vector2i(2, 0)).validate(state),
		"cargo cannot stand there",
		"sea is no place for infantry"
	)
	assert_eq(
		DropCommand.new(apc, Fixture.path([Vector2i(1, 0)]), Vector2i(3, 0)).validate(state),
		"drop cell must be adjacent"
	)


func test_transport_death_takes_cargo_and_counts_for_rout() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 t 0 0\n2 p 1 0")
	state.rng.seed = 4
	var apc := state.units[1]
	var passenger := Unit.create(Fixture.unit_db().by_id(&"infantry"), 2, apc.cell)
	passenger.carrier = apc
	state.units.append(passenger)
	apc.hp = 10  # any hit kills
	var result := CombatResolver.resolve(state, state.units[0], apc)
	assert_true(result.defender_died)
	assert_false(state.units.has(passenger), "cargo dies with its transport")
	assert_eq(state.winner, 1, "the drowned passenger was Blue's last unit")


func test_ai_ignores_carried_units() -> void:
	var state := Fixture.state("[terrain]\n...\n[units]\n1 p 0 0\n1 i 1 0\n2 t 2 0")
	var infantry := state.units[1]
	infantry.carrier = state.units[0]
	infantry.cell = state.units[0].cell
	state.units[0].acted = true
	var ai := AIController.new(Fixture.unit_db())
	var command := ai.plan_next_command(state)
	assert_true(command is EndTurnCommand, "a carried unit must not be planned for")


# --- per-transport cargo rules -----------------------------------------------
#
# What a carrier accepts is its own data now, not one list every transport
# shares. These pin that the T-Copter is an APC that flies rather than something
# that will lift a tank.


func test_t_copter_carries_infantry() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 H 0 0\n1 i 1 0")
	var command := LoadCommand.new(state.units[1], Fixture.path([Vector2i(1, 0), Vector2i(0, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(state.units[1].carrier, state.units[0])


func test_t_copter_will_not_lift_a_tank() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 H 0 0\n1 t 1 0")
	var command := LoadCommand.new(state.units[1], Fixture.path([Vector2i(1, 0), Vector2i(0, 0)]))
	assert_eq(command.validate(state), "unit cannot be transported")


## An armed aircraft is not a transport whatever else it can do.
func test_a_gunship_carries_nothing() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 h 0 0\n1 i 1 0")
	var command := LoadCommand.new(state.units[1], Fixture.path([Vector2i(1, 0), Vector2i(0, 0)]))
	assert_eq(command.validate(state), "unit is not a transport")


# --- the lander --------------------------------------------------------------
#
# The transport that changed the shape of the rules: it carries what drives, and
# it can only put it ashore where a landing craft could actually beach.


func test_a_lander_carries_vehicles() -> void:
	# The lander lies at the beach and the tank walks aboard. It has to be that
	# way round: a tank cannot step onto open water, so a lander in the channel
	# can pick up nothing — which is what makes shoals worth putting on a map.
	var state := Fixture.state("[terrain]\n._\nSS\n[units]\n1 l 1 0\n1 t 0 0")
	var command := LoadCommand.new(state.units[1], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(state.units[1].carrier, state.units[0])


func test_a_lander_in_open_water_cannot_be_boarded() -> void:
	var state := Fixture.state("[terrain]\n.S\nSS\n[units]\n1 l 1 0\n1 t 0 0")
	var command := LoadCommand.new(state.units[1], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_eq(command.validate(state), "path crosses impassable terrain")


func test_a_lander_carries_two() -> void:
	var state := Fixture.state("[terrain]\n._.\nSSS\n[units]\n1 l 1 0\n1 t 0 0\n1 i 2 0")
	LoadCommand.new(state.units[1], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).apply(state)
	var second := LoadCommand.new(state.units[2], Fixture.path([Vector2i(2, 0), Vector2i(1, 0)]))
	assert_eq(second.validate(state), "", "a lander holds two")
	second.apply(state)
	assert_eq(state.cargo_of(state.units[0]).size(), 2)


func test_a_full_lander_takes_no_more() -> void:
	var state := Fixture.state("[terrain]\n._.\n...\n[units]\n1 l 1 0\n1 t 0 0\n1 i 2 0\n1 m 1 1")
	LoadCommand.new(state.units[1], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).apply(state)
	LoadCommand.new(state.units[2], Fixture.path([Vector2i(2, 0), Vector2i(1, 0)])).apply(state)
	var third := LoadCommand.new(state.units[3], Fixture.path([Vector2i(1, 1), Vector2i(1, 0)]))
	assert_eq(third.validate(state), "transport is full")


## A landing craft beaches on a shoal or ties up at a port. Anywhere else the
## cargo would be going over the side into open water.
func test_a_lander_unloads_from_a_shoal() -> void:
	var state := Fixture.state("[terrain]\n_.\nSS\n[units]\n1 l 0 0\n1 t 1 0")
	LoadCommand.new(state.units[1], Fixture.path([Vector2i(1, 0), Vector2i(0, 0)])).apply(state)
	var drop := DropCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(drop.validate(state), "")
	drop.apply(state)
	assert_eq(state.unit_at(Vector2i(1, 0)).type.id, &"tank")
	assert_true(state.unit_at(Vector2i(1, 0)).acted, "cargo comes out exhausted")


func test_a_lander_cannot_unload_in_open_water() -> void:
	var state := Fixture.state("[terrain]\n_S.\nSSS\n[units]\n1 l 0 0\n1 t 2 0")
	(
		LoadCommand
		. new(state.units[1], Fixture.path([Vector2i(2, 0), Vector2i(1, 0), Vector2i(0, 0)]))
		. apply(state)
	)
	state.units[0].acted = false
	var drop := DropCommand.new(
		state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]), Vector2i(2, 0)
	)
	assert_eq(drop.validate(state), "cannot unload here")


## The rule is the transport's own, so the two that shipped before it are
## untouched: an APC still drops wherever its passenger can stand.
func test_an_apc_still_unloads_anywhere() -> void:
	var state := Fixture.state("[terrain]\n...\n[units]\n1 p 1 0\n1 i 0 0")
	LoadCommand.new(state.units[1], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).apply(state)
	state.units[0].acted = false
	var drop := DropCommand.new(state.units[0], Fixture.path([Vector2i(1, 0)]), Vector2i(2, 0))
	assert_eq(drop.validate(state), "")
