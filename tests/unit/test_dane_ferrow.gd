extends GutTest
## Dane Ferrow: one kill funnel for direct fire, counter-fire and drowned cargo.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String, ferrow_team: int = 1) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	state.set_commander(ferrow_team, commander_db.by_id(&"dane_ferrow"))
	state.rng.seed = 4
	return state


func _board(state: GameState, id: StringName, team: int, carrier: Unit) -> Unit:
	var unit := Unit.create(unit_db.by_id(id), team, carrier.cell)
	unit.carrier = carrier
	state.units.append(unit)
	return unit


func test_a_direct_kill_steals_ten_percent_of_base_cost() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 T 1 0")
	var victim := state.units[1]
	victim.hp = 10
	state.funds[2] = 5000
	CombatResolver.resolve(state, state.units[0], victim)
	assert_eq(state.funds[1], 1600, "ten percent of a 16,000 Md Tank")
	assert_eq(state.funds[2], 3400, "the same money leaves the victim")


func test_bounty_clamps_to_the_victim_s_treasury_and_needs_a_kill() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 T 1 0")
	var victim := state.units[1]
	state.funds[2] = 400
	CombatResolver.bank_losses(state, victim, 50, 1)
	assert_eq(state.funds[1], 0, "nonlethal damage pays nothing")
	CombatResolver.bank_losses(state, victim, victim.hp, 1)
	assert_eq(state.funds[1], 400, "a bounty cannot take money that is not there")
	assert_eq(state.funds[2], 0)


func test_a_starvation_death_pays_no_bounty() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n2 f 2 0\n2 i 3 0")
	state.units[1].fuel = 1
	state.funds[2] = 5000
	EndTurnCommand.new().apply(state)
	assert_eq(state.funds[1], 0, "a start-of-turn loss has no dealer")
	assert_eq(state.funds[2], 5000, "nothing is stolen from a starvation loss")


func test_a_counter_kill_pays_the_countering_commander() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 m 0 0\n2 t 1 0", 2)
	state.units[0].hp = 10
	state.funds[1] = 1000
	var result := CombatResolver.resolve(state, state.units[0], state.units[1])
	assert_true(result.attacker_died)
	assert_eq(state.funds[2], 300, "ten percent of the attacking Mech's base value")
	assert_eq(state.funds[1], 700)


func test_cargo_each_pays_through_the_same_kill_funnel() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 p 1 0")
	var transport := state.units[1]
	transport.hp = 10
	_board(state, &"md_tank", 2, transport)
	state.funds[2] = 5000
	CombatResolver.resolve(state, state.units[0], transport)
	assert_eq(state.funds[1], 2100, "APC 500 plus Md Tank cargo 1,600")
	assert_eq(state.funds[2], 2900)


func test_collect_doubles_the_rate_and_defence_stays_soft() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 T 1 0")
	var co := state.commander_of(1)
	var fight := Engagement.create(state.units[0], Vector2i.ZERO, 10, state.units[1], Vector2i(1, 0), 10)
	assert_eq(co.defense_bonus(state, fight), -10)
	state.add_charge(1, co.power_cost)
	PowerCommand.new().apply(state)
	assert_eq(co.kill_bounty_pct(state, 1, state.units[1]), 20)
	state.funds[2] = 5000
	CombatResolver.bank_losses(state, state.units[1], state.units[1].hp, 1)
	assert_eq(state.funds[1], 3200)


func test_same_seed_replays_the_same_treasuries() -> void:
	assert_eq(_played_funds(), _played_funds())


func _played_funds() -> Dictionary:
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 1 0\n2 T 2 0")
	state.rng.seed = 4242
	state.units[1].hp = 10
	state.funds[2] = 5000
	CombatResolver.resolve(state, state.units[0], state.units[1])
	return state.funds.duplicate()
