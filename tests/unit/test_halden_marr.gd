extends GutTest
## Halden Marr: sea mobility and the exact three shore terrain ids.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String, commander: bool = true) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	if commander:
		state.set_commander(1, commander_db.by_id(&"halden_marr"))
	return state


func _fight(state: GameState, attacker: Unit, defender: Unit) -> Engagement:
	return Engagement.create(attacker, attacker.cell, 10, defender, defender.cell, 10)


func test_sea_units_gain_attack_and_movement() -> void:
	var state := _state("[terrain]\nPS\n[owners]\n1 0 0\n[units]\n1 c 0 0\n2 s 1 0")
	var cruiser := state.units[0]
	var co := state.commander_of(1)
	assert_eq(co.attack_bonus(state, _fight(state, cruiser, state.units[1])), 10)
	assert_eq(MovementResolver.move_budget(state, cruiser), cruiser.type.move_points + 1)
	state.add_charge(1, co.power_cost)
	PowerCommand.new().apply(state)
	assert_eq(co.attack_bonus(state, _fight(state, cruiser, state.units[1])), 20)
	assert_eq(MovementResolver.move_budget(state, cruiser), cruiser.type.move_points + 3)


func test_shoal_reef_and_port_each_grant_the_shore_star() -> void:
	var cases: Array = [["_", "i"], ["*", "c"], ["P", "c"]]
	for case: Array in cases:
		var symbol: String = case[0]
		var defender_symbol: String = case[1]
		var state := _state(
			"[terrain]\nS%s\n[units]\n2 c 0 0\n1 %s 1 0" % [symbol, defender_symbol]
		)
		var fight := _fight(state, state.units[0], state.units[1])
		assert_eq(state.commander_of(1).star_bonus(state, fight), 1, symbol)


func test_land_only_combat_is_bit_identical_to_neutral() -> void:
	var map_text := "[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0"
	var marr := _state(map_text)
	var neutral := _state(map_text, false)
	assert_eq(
		CombatResolver.forecast(marr, marr.units[0], Vector2i.ZERO, marr.units[1]).attack_damage,
		CombatResolver.forecast(neutral, neutral.units[0], Vector2i.ZERO, neutral.units[1]).attack_damage
	)
