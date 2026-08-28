extends GutTest
## Halden Marr: sea mobility, the exact three shore terrain ids, and the ground
## advice that walks his army onto them.

var unit_db: UnitDB


func before_each() -> void:
	unit_db = Fixture.unit_db()


func _state(map_text: String, commander: bool = true) -> GameState:
	return Fixture.state(map_text, {1: &"halden_marr"} if commander else {})


func _fight(attacker: Unit, defender: Unit) -> Engagement:
	return Engagement.create(attacker, attacker.cell, 10, defender, defender.cell, 10)


func test_sea_units_gain_attack_and_movement() -> void:
	var state := _state("[terrain]\nPS\n[owners]\n1 0 0\n[units]\n1 c 0 0\n2 s 1 0")
	var cruiser := state.units[0]
	var co := state.commander_of(1)
	assert_eq(co.attack_bonus(state, _fight(cruiser, state.units[1])), 10)
	assert_eq(MovementResolver.move_budget(state, cruiser), cruiser.type.move_points + 1)
	state.add_charge(1, co.power_cost)
	PowerCommand.new().apply(state)
	assert_eq(co.attack_bonus(state, _fight(cruiser, state.units[1])), 20)
	assert_eq(MovementResolver.move_budget(state, cruiser), cruiser.type.move_points + 3)


func test_shoal_reef_and_port_each_grant_the_shore_star() -> void:
	var cases: Array = [["_", "i"], ["*", "c"], ["P", "c"]]
	for case: Array in cases:
		var symbol: String = case[0]
		var defender_symbol: String = case[1]
		var state := _state(
			"[terrain]\nS%s\n[units]\n2 c 0 0\n1 %s 1 0" % [symbol, defender_symbol]
		)
		var fight := _fight(state.units[0], state.units[1])
		assert_eq(state.commander_of(1).star_bonus(state, fight), 1, symbol)


func test_the_shore_power_holds_on_a_land_only_board() -> void:
	var map_text := Fixture.TANK_VS_INFANTRY
	var neutral := _state(map_text, false)
	assert_true(neutral.commander_of(1).wants_power(neutral, 1))
	var marr := _state(map_text)
	assert_false(marr.commander_of(1).wants_power(marr, 1))


func test_the_shore_power_fires_for_a_hull() -> void:
	var state := _state("[terrain]\n...S\n[units]\n1 t 0 0\n2 i 1 0\n1 B 3 0")
	assert_true(state.commander_of(1).wants_power(state, 1))


## The beneficiary and the striker have to be the same unit. Here the hull is
## out of range of the only enemy and the Infantry that can shoot it takes none
## of the shore bonuses, so the intersection is empty — which the two halves,
## asked separately, could not see.
func test_the_shore_power_holds_when_the_hull_has_no_shot_of_its_own() -> void:
	var state := _state("[terrain]\nS...........\n[units]\n1 B 0 0\n1 i 9 0\n2 i 10 0")
	assert_true(CommanderType.neutral().wants_power(state, 1), "the default fires here")
	assert_false(state.commander_of(1).wants_power(state, 1))


func test_the_shore_power_fires_for_a_unit_standing_on_a_shoal() -> void:
	var state := _state("[terrain]\n_.\n[units]\n1 t 0 0\n2 i 1 0")
	assert_true(state.commander_of(1).wants_power(state, 1))


func test_the_shore_power_fires_for_a_shoal_one_march_away() -> void:
	var state := _state("[terrain]\n..\n._\n[units]\n1 t 0 0\n2 i 1 0")
	assert_true(state.commander_of(1).wants_power(state, 1))


# --- ground advice -----------------------------------------------------------

## A march of plains with one shoal a tile short of the tank's full reach: the
## coast costs exactly one tile of progress to stand on.
const NEAR_SHORE_BOARD := """
[terrain]
......_.......
[units]
1 t 1 0
2 t 12 0
"""

## The same march with the shoal two tiles short instead.
const FAR_SHORE_BOARD := """
[terrain]
....._........
[units]
1 t 1 0
2 t 12 0
"""


func _advance_destination(state: GameState, profile: AIProfile) -> Vector2i:
	var command := AIController.new(unit_db, profile).plan_next_command(state)
	assert_true(command is MoveCommand, "expected an advance, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	return path[path.size() - 1]


## Every bonus Make for the Shore grants a land unit lands on shore ground, so a
## banked meter is worth a tile of march to stand there — the shore cell wins the
## quiet advance the doctrine-blind planner would march past.
func test_a_banked_meter_walks_him_onto_the_shore() -> void:
	var state := _state(NEAR_SHORE_BOARD)
	state.add_charge(1, state.commander_of(1).power_cost)
	var staged := AIController.new(unit_db).plan_next_command(state)
	assert_true(staged is MoveCommand, "expected the staging move, got %s" % staged)
	var path: Array[Vector2i] = (staged as MoveCommand).path
	assert_eq(path[path.size() - 1], Vector2i(6, 0), "the tank should stop on the shoal")
	assert_eq(staged.validate(state), "")


## The everyday preference is one tile, so an empty meter keeps marching rather
## than trading two tiles of progress for a beach.
func test_an_empty_meter_does_not_detour_for_the_shore() -> void:
	var state := _state(FAR_SHORE_BOARD)
	assert_eq(_advance_destination(state, AIProfile.new()), Vector2i(7, 0))


## Every effect he has is keyed on the coast, so a board with none of it is
## advice-free — which is what keeps the land-only neutrality below honest.
func test_a_land_only_board_is_worth_nothing_to_stand_on() -> void:
	var state := _state("[terrain]\n.F.\nM.C\n[units]\n1 t 0 0\n2 i 2 1")
	var co := state.commander_of(1)
	var tank := state.units[0]
	state.add_charge(1, co.power_cost)
	for y in 2:
		for x in 3:
			assert_eq(co.stand_value(state, tank, Vector2i(x, y)), 0, "%d,%d" % [x, y])


## D2: the one planner dial. At zero the doctrine-blind planner is restored, so
## a banked meter no longer buys the detour the first test above pins.
func test_a_zero_doctrine_weight_ignores_the_shore_advice() -> void:
	var advised := _state(NEAR_SHORE_BOARD)
	advised.add_charge(1, advised.commander_of(1).power_cost)
	var blind := AIProfile.new()
	blind.doctrine_weight = 0.0
	var neutral := _state(NEAR_SHORE_BOARD, false)
	assert_eq(_advance_destination(advised, blind), _advance_destination(neutral, AIProfile.new()))


func test_land_only_combat_is_bit_identical_to_neutral() -> void:
	var map_text := Fixture.TANK_VS_INFANTRY
	var marr := _state(map_text)
	var neutral := _state(map_text, false)
	assert_eq(
		CombatResolver.forecast(marr, marr.units[0], Vector2i.ZERO, marr.units[1]).attack_damage,
		(
			CombatResolver
			. forecast(neutral, neutral.units[0], Vector2i.ZERO, neutral.units[1])
			. attack_damage
		)
	)
