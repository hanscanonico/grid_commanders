extends GutTest
## Halden Marr: sea mobility and the exact three shore terrain ids.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


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
	var map_text := "[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0"
	assert_true(_state(map_text, false).commander_of(1).wants_power(_state(map_text, false), 1))
	var marr := _state(map_text)
	assert_false(marr.commander_of(1).wants_power(marr, 1))


func test_the_shore_power_fires_for_a_hull() -> void:
	var state := _state("[terrain]\n..S\n[units]\n1 t 0 0\n2 i 1 0\n1 c 2 0")
	assert_true(state.commander_of(1).wants_power(state, 1))


func test_the_shore_power_fires_for_a_unit_standing_on_a_shoal() -> void:
	var state := _state("[terrain]\n_.\n[units]\n1 t 0 0\n2 i 1 0")
	assert_true(state.commander_of(1).wants_power(state, 1))


func test_the_shore_power_fires_for_a_shoal_one_march_away() -> void:
	var state := _state("[terrain]\n..\n._\n[units]\n1 t 0 0\n2 i 1 0")
	assert_true(state.commander_of(1).wants_power(state, 1))


func test_land_only_combat_is_bit_identical_to_neutral() -> void:
	var map_text := "[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0"
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
