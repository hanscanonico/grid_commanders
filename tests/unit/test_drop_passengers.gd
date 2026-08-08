extends GutTest
## A drop names which passenger steps off. Judging every drop against the
## first-loaded rider wrongly refused the second one exactly when it was the
## only one that could stand beside the transport — a Lander's two riders need
## not share a move class.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


func test_drop_judges_each_passenger_not_just_the_first() -> void:
	# A lander beached on a shoal carries a tank (treads, loaded first) and then an
	# infantry (foot). The mountain beside it takes the infantry but not the tank;
	# judging every drop against the first passenger wrongly refused the infantry.
	var state := Fixture.state("[terrain]\n._S\nSMS\n[units]\n1 l 1 0")
	var lander := state.units[0]
	var tank := Unit.create(unit_db.by_id(&"tank"), 1, lander.cell)
	tank.carrier = lander
	var infantry := Unit.create(unit_db.by_id(&"infantry"), 1, lander.cell)
	infantry.carrier = lander
	state.units.append(tank)
	state.units.append(infantry)
	assert_eq(state.cargo_of(lander), [tank, infantry] as Array[Unit], "tank is loaded first")
	var path := Fixture.path([Vector2i(1, 0)])
	# The named second passenger drops onto the mountain the tank cannot climb.
	var drop_infantry := DropCommand.new(lander, path, Vector2i(1, 1), infantry)
	assert_eq(drop_infantry.validate(state), "")
	# The tank still cannot stand on that mountain, whichever passenger is first.
	assert_eq(
		DropCommand.new(lander, path, Vector2i(1, 1), tank).validate(state),
		"cargo cannot stand there"
	)
	# The first passenger's own path still works: the tank drops onto the plains.
	assert_eq(DropCommand.new(lander, path, Vector2i(0, 0), tank).validate(state), "")
	# A unit this transport is not carrying cannot be selected for a drop.
	var stranger := Unit.create(unit_db.by_id(&"infantry"), 1, Vector2i(0, 0))
	state.units.append(stranger)
	assert_eq(
		DropCommand.new(lander, path, Vector2i(1, 1), stranger).validate(state),
		"unit is not aboard"
	)
	# Applying the infantry drop lands it, exhausted, on the mountain; tank stays.
	drop_infantry.apply(state)
	assert_null(infantry.carrier)
	assert_eq(infantry.cell, Vector2i(1, 1))
	assert_true(infantry.acted)
	assert_eq(state.unit_at(Vector2i(1, 1)), infantry)
	assert_eq(state.cargo_of(lander), [tank] as Array[Unit], "the tank stays aboard")


## A drop can fail two ways, and they are different events. `Command.ambushed`
## means a hidden enemy on the *path* cut the move short; a drop cell that turns
## out occupied stops nothing — the transport arrived, the passenger simply has
## nowhere to step. Reporting the second as the first plays the trap cue for a
## plain blockage.
func test_a_blocked_drop_is_not_an_ambush() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 p 0 0\n2 i 2 0")
	state.fog_enabled = true
	var apc := state.units[0]
	var rider := Unit.create(unit_db.by_id(&"infantry"), 1, apc.cell)
	rider.carrier = apc
	state.units.append(rider)
	# The enemy sits on the drop cell, not on the path, and team 1 cannot see it.
	var command := DropCommand.new(
		apc, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]), Vector2i(2, 0)
	)
	assert_eq(
		command.validate(state), "", "a hidden occupant must not be refused — that reveals it"
	)
	command.apply(state)
	assert_false(command.ambushed, "nothing sprang a trap: the transport reached its cell")
	assert_true(command.drop_blocked, "the drop cell was occupied")
	assert_eq(apc.cell, Vector2i(1, 0), "the move ran its full length")
	assert_eq(state.cargo_of(apc), [rider] as Array[Unit], "the passenger stays aboard")


func test_a_drop_whose_move_is_ambushed_still_reports_the_trap() -> void:
	var state := Fixture.state("[terrain]\n....\n....\n[units]\n1 p 0 0\n2 i 2 0")
	state.fog_enabled = true
	var apc := state.units[0]
	var rider := Unit.create(unit_db.by_id(&"infantry"), 1, apc.cell)
	rider.carrier = apc
	state.units.append(rider)
	# This time the hidden enemy is *on* the path, and the drop cell is clear.
	var command := DropCommand.new(
		apc, Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]), Vector2i(2, 1)
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(command.ambushed, "the move was cut short at the hidden enemy")
	assert_false(command.drop_blocked, "and that is the trap, not a blocked cell")
	assert_eq(apc.cell, Vector2i(1, 0), "stopped on the last free cell before it")
	assert_eq(state.cargo_of(apc), [rider] as Array[Unit], "the passenger stays aboard")
