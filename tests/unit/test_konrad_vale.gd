extends GutTest
## Konrad Vale: the full surcharge curve and the elite stats that purchase it.

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
	var map := MapData.parse("[terrain]\n.C\n[units]\n1 t 0 0\n2 i 1 0", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	state.set_commander(1, commander_db.by_id(&"konrad_vale"))
	return state


func _fight(state: GameState) -> Engagement:
	return Engagement.create(
		state.units[0], Vector2i.ZERO, 10, state.units[1], Vector2i(1, 0), 10
	)


func test_surcharge_reaches_both_ends_of_the_roster() -> void:
	var state := _state()
	assert_eq(UnitPricing.cost_for(state, 1, unit_db.by_id(&"infantry")), 1200)
	assert_eq(UnitPricing.cost_for(state, 1, unit_db.by_id(&"battleship")), 33600)


func test_elite_stats_and_overwhelming_force_stack() -> void:
	var state := _state()
	var co := state.commander_of(1)
	assert_eq(co.attack_bonus(state, _fight(state)), 10)
	assert_eq(co.defense_bonus(state, _fight(state)), 10)
	assert_eq(co.star_pierce(state, _fight(state)), 0)
	state.add_charge(1, co.power_cost)
	PowerCommand.new().apply(state)
	assert_eq(co.attack_bonus(state, _fight(state)), 35)
	assert_eq(co.star_pierce(state, _fight(state)), 1)


func test_production_advice_moves_away_from_cheap_units() -> void:
	var state := _state()
	var co := state.commander_of(1)
	assert_gt(co.build_bias(state, 1, unit_db.by_id(&"infantry")), 0)
	assert_eq(co.build_bias(state, 1, unit_db.by_id(&"tank")), 0)
