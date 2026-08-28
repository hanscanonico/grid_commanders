extends GutTest
## Gideon Holt: supply radius, the repair discount, and Open the Depots.

var unit_db: UnitDB


func before_each() -> void:
	unit_db = Fixture.unit_db()


func _state(map_text: String, with_gideon: bool = true) -> GameState:
	return Fixture.state(map_text, {1: &"gideon_holt"} if with_gideon else {})


# --- supply radius -----------------------------------------------------------


## An APC at (0,0) reaches a tank at (2,0) — two tiles — but not one at (3,0).
func test_supply_reaches_two_tiles_at_turn_start() -> void:
	var state := _state("[terrain]\n=====\n[units]\n1 p 0 0\n1 t 2 0\n1 t 4 0")
	var near := state.units[1]
	var far := state.units[2]
	near.fuel = 1
	far.fuel = 1
	TurnRules.begin_turn(state)
	assert_eq(near.fuel, near.type.max_fuel, "two tiles is in reach")
	assert_eq(far.fuel, 1, "four tiles is not")


func test_a_neutral_commander_still_supplies_only_adjacent_units() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 p 0 0\n1 t 2 0", false)
	state.units[1].fuel = 1
	TurnRules.begin_turn(state)
	assert_eq(state.units[1].fuel, 1, "without Gideon, two tiles is out of reach")


func test_the_supply_action_uses_the_same_radius() -> void:
	var state := _state("[terrain]\n=====\n[units]\n1 p 0 0\n1 t 2 0")
	var apc := state.units[0]
	var tank := state.units[1]
	tank.fuel = 1
	var command := SupplyCommand.new(apc, [apc.cell])
	assert_eq(command.validate(state), "", "the APC has someone in reach")
	command.apply(state)
	assert_eq(tank.fuel, tank.type.max_fuel)


func test_supply_still_skips_the_unit_itself_and_its_passengers() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 p 0 0\n1 i 1 0")
	var apc := state.units[0]
	var infantry := state.units[1]
	infantry.carrier = apc
	infantry.cell = apc.cell
	var command := SupplyCommand.new(apc, [apc.cell])
	assert_eq(command.validate(state), "no one in reach to supply")


# --- repair discount ---------------------------------------------------------


## A full 2-HP repair on a 7 000 Tank is 1 400 at list price, 1 120 at 80%.
func test_repairs_cost_twenty_percent_less() -> void:
	var state := _state("[terrain]\nC\n[units]\n1 t 0 0")
	state.set_owner(Vector2i(0, 0), 1)
	state.units[0].hp = 60
	state.funds[1] = 5000
	TurnRules.begin_turn(state)
	assert_eq(state.units[0].hp, 80, "still a full 2 HP of healing")
	# begin_turn also pays income for the one property held.
	assert_eq(state.funds[1], 5000 + GameState.INCOME_PER_PROPERTY - 1120)


func test_a_neutral_commander_pays_the_list_price() -> void:
	var state := _state("[terrain]\nC\n[units]\n1 t 0 0", false)
	state.set_owner(Vector2i(0, 0), 1)
	state.units[0].hp = 60
	state.funds[1] = 5000
	TurnRules.begin_turn(state)
	assert_eq(state.funds[1], 5000 + GameState.INCOME_PER_PROPERTY - 1400)


## The discount also decides whether a repair happens at all: a side that cannot
## afford the list price may still afford Gideon's.
func test_the_discount_can_be_what_makes_a_repair_affordable() -> void:
	var state := _state("[terrain]\nC\n[units]\n1 t 0 0")
	state.set_owner(Vector2i(0, 0), 1)
	state.units[0].hp = 60
	state.funds[1] = 200  # 1 200 with income: under 1 400, over 1 120
	TurnRules.begin_turn(state)
	assert_eq(state.units[0].hp, 80)
	assert_eq(state.funds[1], 200 + GameState.INCOME_PER_PROPERTY - 1120)


# --- Open the Depots ---------------------------------------------------------


func test_the_power_refills_and_heals_the_whole_army() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 t 0 0\n1 i 1 0\n2 t 2 0")
	var tank := state.units[0]
	var infantry := state.units[1]
	var enemy := state.units[2]
	tank.fuel = 3
	tank.ammo = 0
	tank.hp = 50
	infantry.hp = 95
	enemy.fuel = 3
	enemy.hp = 50
	state.add_charge(1, state.commander_of(1).power_cost)
	PowerCommand.new().apply(state)
	assert_eq(tank.fuel, tank.type.max_fuel, "fuel")
	assert_eq(tank.ammo, tank.type.max_ammo, "ammo")
	assert_eq(tank.hp, 60, "one displayed HP")
	assert_eq(infantry.hp, 100, "and healing never overshoots full")
	assert_eq(enemy.fuel, 3, "the enemy is not resupplied")
	assert_eq(enemy.hp, 50)


## The heal is free, unlike the paid repairs his doctrine discounts.
func test_the_power_costs_no_funds() -> void:
	var state := _state("[terrain]\n=\n[units]\n1 t 0 0")
	state.units[0].hp = 50
	state.funds[1] = 0
	state.add_charge(1, state.commander_of(1).power_cost)
	PowerCommand.new().apply(state)
	assert_eq(state.units[0].hp, 60)
	assert_eq(state.funds[1], 0)


## A passenger is not part of the fielded army, so a worn one is not a second
## reason to open the depots — the carrier filter every doctrine counting its own
## units shares.
func test_the_depots_do_not_count_a_passenger() -> void:
	var state := _state("[terrain]\n====\n[units]\n1 p 0 0\n1 i 1 0")
	var apc := state.units[0]
	var infantry := state.units[1]
	infantry.carrier = apc
	infantry.cell = apc.cell
	infantry.hp = 50
	apc.hp = 50
	var co := state.commander_of(1)
	assert_false(co.wants_power(state, 1), "one worn unit on the board and one riding is still one")
	infantry.carrier = null
	assert_true(co.wants_power(state, 1), "set down, the same unit is the second")


# --- economy advice ----------------------------------------------------------


## Repairs at 80% move the planner's retreat line: a tank at 55 HP turns for
## the repair city that the neutral planner — pinned by the advice-seam tests —
## would still fight on with.
func test_cheap_repairs_send_a_wounded_tank_home_earlier() -> void:
	var state := _state("[terrain]\nC.............\n[owners]\n1 0 0\n[units]\n1 t 4 0\n2 i 13 0")
	state.units[0].hp = 55
	var command := AIController.new(unit_db).plan_next_command(state)
	assert_true(command is MoveCommand, "expected a move, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_lt(path[path.size() - 1].x, 4, "the tank turns for the repair city")
