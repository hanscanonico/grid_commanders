extends GutTest
## Perrin Ash: only air units move off the neutral combat line.

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
	return Fixture.state(map_text, {1: &"perrin_ash"} if commander else {})


func _damage(state: GameState) -> int:
	var result := CombatResolver.forecast(
		state, state.units[0], state.units[0].cell, state.units[1]
	)
	return result.attack_damage


func test_air_attack_reaches_twenty_while_the_power_runs() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 h 0 0\n2 i 1 0")
	var co := state.commander_of(1)
	var fight := Engagement.create(
		state.units[0], Vector2i.ZERO, 10, state.units[1], Vector2i(1, 0), 10
	)
	assert_eq(co.attack_bonus(state, fight), 10)
	state.add_charge(1, co.power_cost)
	PowerCommand.new().apply(state)
	assert_eq(co.attack_bonus(state, fight), 20)
	EndTurnCommand.new().apply(state)
	assert_true(state.power_active(1), "the air cover lasts through the opposing turn")


func test_land_only_combat_is_bit_identical_to_neutral() -> void:
	var map_text := "[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0"
	assert_eq(_damage(_state(map_text)), _damage(_state(map_text, false)))
