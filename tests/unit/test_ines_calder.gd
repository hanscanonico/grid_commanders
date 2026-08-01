extends GutTest
## Ines Calder: the full price curve, the standing attack tax and the active
## swing Weight of Numbers promises.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state() -> GameState:
	var map := MapData.parse("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	state.set_commander(1, commander_db.by_id(&"ines_calder"))
	return state


func _fight(state: GameState) -> Engagement:
	return Engagement.create(
		state.units[0], Vector2i.ZERO, 10, state.units[1], Vector2i(1, 0), 10
	)


func test_discount_reaches_both_ends_of_the_roster() -> void:
	var state := _state()
	assert_eq(UnitPricing.cost_for(state, 1, unit_db.by_id(&"infantry")), 800)
	assert_eq(UnitPricing.cost_for(state, 1, unit_db.by_id(&"battleship")), 22400)


func test_weight_of_numbers_is_a_twenty_five_point_swing() -> void:
	var state := _state()
	var co := state.commander_of(1)
	assert_eq(co.attack_bonus(state, _fight(state)), -10)
	state.add_charge(1, co.power_cost)
	PowerCommand.new().apply(state)
	assert_eq(co.attack_bonus(state, _fight(state)), 15)


func test_production_advice_prefers_cheap_units() -> void:
	var state := _state()
	var co := state.commander_of(1)
	assert_lt(co.build_bias(state, 1, unit_db.by_id(&"infantry")), 0)
	assert_eq(co.build_bias(state, 1, unit_db.by_id(&"tank")), 0)
