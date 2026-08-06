extends GutTest
## SupplyCommand on its own: what it refuses, who a top-up reaches, and what a
## walk that never arrives refills.
##
## `friendlies_in_reach` is public so the UI can decide whether to offer the
## action at all, and had no direct caller in the suite — it was only ever
## exercised through `validate`, which asks it about the cell the unit is already
## standing on. The question the UI asks is the other one: who would this reach
## if it walked over there.
##
## Who is in reach is `TurnRules.in_supply_reach` and is pinned where that rule
## lives — the radius in tests/unit/test_gideon_holt.gd, the supplier passing
## itself and its passengers over in tests/unit/test_fuel_and_ammo.gd. This file
## asks only the command's own surface.


func _state(map_text: String, fog: bool = false) -> GameState:
	var state := Fixture.state(map_text)
	state.fog_enabled = fog
	return state


func _drain(unit: Unit) -> Unit:
	unit.fuel = 3
	unit.ammo = 0
	return unit


func _is_full(unit: Unit) -> bool:
	return unit.fuel == unit.type.max_fuel and unit.ammo == unit.type.max_ammo


# --- the top-up ---------------------------------------------------------------


## One action, every friendly in reach — and nobody else's army, however close it
## is parked.
func test_a_supply_refills_every_friendly_in_reach() -> void:
	var state := _state("[terrain]\n....\n....\n[units]\n1 t 0 0\n1 p 1 0\n1 t 2 0\n2 t 1 1")
	var west := _drain(state.units[0])
	var apc := state.units[1]
	var east := _drain(state.units[2])
	var enemy := _drain(state.units[3])
	var command := SupplyCommand.new(apc, Fixture.path([Vector2i(1, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(_is_full(west), "the tank on one side is topped up")
	assert_true(_is_full(east), "and so is the one on the other")
	assert_false(_is_full(enemy), "the enemy beside the truck is not the truck's problem")
	assert_true(apc.acted, "and the truck has spent its turn")


## The move happens first, so who is in reach is answered from where the truck
## ends up rather than from where it started.
func test_a_supply_drives_to_the_unit_it_refills() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 p 0 0\n1 t 4 0")
	var apc := state.units[0]
	var tank := _drain(state.units[1])
	var command := SupplyCommand.new(
		apc, Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(apc.cell, Vector2i(3, 0))
	assert_true(_is_full(tank))


# --- the refusals -------------------------------------------------------------


func test_supply_answers_the_move_rules_first() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 p 0 0\n1 t 1 0")
	var apc := state.units[0]
	assert_eq(
		SupplyCommand.new(apc, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).validate(state),
		"destination is occupied",
		"a supply is a move, so it may not end on the unit it came to refill"
	)
	apc.acted = true
	assert_eq(
		SupplyCommand.new(apc, Fixture.path([Vector2i(0, 0)])).validate(state),
		"unit has already acted"
	)


## The roster's one can_resupply unit is the APC. Anything else standing beside a
## dry tank is just standing there.
func test_supply_rejects_a_unit_that_carries_no_supplies() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n1 t 1 0")
	_drain(state.units[1])
	assert_eq(
		SupplyCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)])).validate(state),
		"unit cannot resupply others"
	)


func test_supply_rejects_a_board_with_nobody_of_ours_in_reach() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 p 0 0\n2 t 1 0")
	_drain(state.units[1])
	assert_eq(
		SupplyCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)])).validate(state),
		"no one in reach to supply"
	)


# --- the UI's question --------------------------------------------------------


## What the action is offered on: who a top-up would reach from a cell the truck
## has not driven to yet. `from` is a parameter for exactly this, the way
## CombatResolver.forecast_at takes the defender's cell.
func test_friendlies_in_reach_answers_for_a_cell_the_truck_has_not_reached() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 p 0 0\n1 t 4 0\n2 t 3 0")
	var apc := state.units[0]
	var tank := state.units[1]
	var command := SupplyCommand.new(apc, Fixture.path([Vector2i(0, 0)]))
	assert_eq(command.friendlies_in_reach(state, Vector2i(0, 0)), [] as Array[Unit], "nobody here")
	assert_eq(
		command.friendlies_in_reach(state, Vector2i(3, 0)),
		[tank] as Array[Unit],
		"three cells over the tank is adjacent, and the enemy beside it never counts"
	)


# --- the ambush ---------------------------------------------------------------


## The trap springs on commit like it does for every other move-and-then command:
## the truck stops short, and the unit it was driving to stays empty.
func test_an_ambushed_supply_tops_nobody_up() -> void:
	var state := _state("[terrain]\n......\n[units]\n1 p 0 0\n2 i 2 0\n1 i 5 0", true)
	var apc := state.units[0]
	var stranded := state.units[2]
	stranded.fuel = 5
	var command := SupplyCommand.new(
		apc,
		Fixture.path(
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
		)
	)
	assert_eq(
		command.validate(state), "", "the hidden enemy must not be refused — that is the probe"
	)
	command.apply(state)
	assert_true(command.ambushed)
	assert_eq(apc.cell, Vector2i(1, 0), "stopped on the last free cell before the hidden enemy")
	assert_eq(stranded.fuel, 5, "and the unit it was driving to is still dry")
