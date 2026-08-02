extends GutTest
## Iris Colt: a late power refreshes non-attack actions, never attacks or builds.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	state.set_commander(1, commander_db.by_id(&"iris_colt"))
	return state


func _fire(state: GameState) -> void:
	var commander := state.commander_of(1)
	state.add_charge(1, commander.power_cost)
	var command := PowerCommand.new()
	assert_eq(command.validate(state), "")
	command.apply(state)


func test_all_combat_is_ten_percent_softer() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	var fight := Engagement.create(
		state.units[0], Vector2i.ZERO, 10, state.units[1], Vector2i(1, 0), 10
	)
	var commander := state.commander_of(1)
	assert_eq(commander.attack_bonus(state, fight), -10)
	assert_eq(commander.defense_bonus(state, fight), -10)


func test_second_wind_refreshes_a_move_but_not_an_attack() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 p 0 0\n1 t 2 0\n2 i 3 0")
	var mover := state.units[0]
	var attacker := state.units[1]
	MoveCommand.new(mover, [Vector2i(0, 0), Vector2i(1, 0)]).apply(state)
	AttackCommand.new(attacker, [Vector2i(2, 0)], Vector2i(3, 0)).apply(state)
	assert_true(mover.refreshable)
	assert_false(attacker.refreshable)
	_fire(state)
	assert_false(mover.acted, "the non-attacking action gets a second turn")
	assert_true(attacker.acted, "an attacker stays exhausted")


func test_a_new_build_is_never_refreshed() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n1 0 0")
	state.funds[1] = 1000
	var build := BuildCommand.new(1, unit_db.by_id(&"infantry"), Vector2i.ZERO)
	assert_eq(build.validate(state), "")
	build.apply(state)
	assert_false(build.built_unit.refreshable)
	_fire(state)
	assert_true(build.built_unit.acted)


## The rider boards on the same turn it is set down, which is the case where the
## flag it carried in was its own. Second Wind must still pass it by: the drop is
## the transport's action, so eligibility cannot depend on how the rider got aboard.
func test_a_dropped_rider_is_never_refreshed() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 p 0 0\n1 i 1 0")
	var carrier := state.units[0]
	var rider := state.units[1]
	var board := LoadCommand.new(rider, [Vector2i(1, 0), Vector2i(0, 0)])
	assert_eq(board.validate(state), "")
	board.apply(state)
	assert_true(rider.refreshable, "boarding is the rider's own non-attack action")
	var drop := DropCommand.new(carrier, [Vector2i(0, 0), Vector2i(1, 0)], Vector2i(2, 0))
	assert_eq(drop.validate(state), "")
	drop.apply(state)
	assert_false(rider.refreshable)
	_fire(state)
	assert_true(rider.acted, "a unit somebody else set down stays exhausted")


func test_ai_spends_second_wind_late_and_moves_twice() -> void:
	var state := _state("[terrain]\n............\n[units]\n1 p 0 0\n2 i 11 0")
	var commander := state.commander_of(1)
	state.add_charge(1, commander.power_cost)
	var ai := AIController.new(unit_db)
	var first := ai.plan_next_command(state)
	assert_true(first is MoveCommand, "Second Wind must not fire before the first action")
	first.apply(state)
	var first_cell := state.units[0].cell
	var second := ai.plan_next_command(state)
	assert_true(second is PowerCommand, "the eligible move should trigger the late power")
	second.apply(state)
	var third := ai.plan_next_command(state)
	assert_true(third is MoveCommand, "the refreshed unit should be planned again")
	third.apply(state)
	assert_gt(state.units[0].cell.x, first_cell.x)
