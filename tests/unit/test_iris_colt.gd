extends GutTest
## Iris Colt: a late power refreshes every unit that spent its own action,
## attacks included, and never a build or a unit somebody else set down.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


func _state(map_text: String) -> GameState:
	return Fixture.state(map_text, {1: &"iris_colt"})


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


func test_second_wind_refreshes_a_move_and_an_attack_alike() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 p 0 0\n1 t 2 0\n2 i 3 0")
	var mover := state.units[0]
	var attacker := state.units[1]
	MoveCommand.new(mover, [Vector2i(0, 0), Vector2i(1, 0)]).apply(state)
	AttackCommand.new(attacker, [Vector2i(2, 0)], Vector2i(3, 0)).apply(state)
	assert_true(mover.refreshable)
	assert_true(attacker.refreshable, "the shot was the attacker's own action")
	_fire(state)
	assert_false(mover.acted, "the walk gets a second turn")
	assert_false(attacker.acted, "and so does the shot")


## The retune itself, read through the command that has to accept it: an
## exhausted attacker is refused, and the same shot validates once the meter is
## spent.
func test_a_refreshed_attacker_may_fire_again() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	var attacker := state.units[0]
	var target := state.units[1]
	var first := AttackCommand.new(attacker, [Vector2i(0, 0)], Vector2i(1, 0))
	assert_eq(first.validate(state), "")
	first.apply(state)
	var hp_after_first := target.hp
	assert_lt(hp_after_first, Unit.MAX_HP, "the first shot landed")
	var again := AttackCommand.new(attacker, [Vector2i(0, 0)], Vector2i(1, 0))
	assert_ne(again.validate(state), "", "an exhausted attacker is refused")
	_fire(state)
	assert_eq(again.validate(state), "", "Second Wind hands the shot back")
	again.apply(state)
	assert_lt(target.hp, hp_after_first, "and the second shot lands")


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
	assert_true(rider.refreshable, "boarding is the rider's own action")
	var drop := DropCommand.new(carrier, [Vector2i(0, 0), Vector2i(1, 0)], Vector2i(2, 0))
	assert_eq(drop.validate(state), "")
	drop.apply(state)
	assert_false(rider.refreshable)
	_fire(state)
	assert_true(rider.acted, "a unit somebody else set down stays exhausted")


func test_ai_spends_second_wind_late_to_reach_a_shot() -> void:
	var state := _state("[terrain]\n............\n[units]\n1 t 0 0\n2 i 11 0")
	var commander := state.commander_of(1)
	state.add_charge(1, commander.power_cost)
	var ai := AIController.new(unit_db)
	var first := ai.plan_next_command(state)
	assert_true(first is MoveCommand, "Second Wind must not fire before the first action")
	first.apply(state)
	var first_cell := state.units[0].cell
	var second := ai.plan_next_command(state)
	assert_true(second is PowerCommand, "one walk short of the enemy is worth the meter")
	second.apply(state)
	var third := ai.plan_next_command(state)
	assert_false(third is EndTurnCommand, "the refreshed tank should be planned again")
	third.apply(state)
	assert_gt(state.units[0].cell.x, first_cell.x)


## The behaviour change: a refreshed unit that could only walk again buys nothing,
## so the meter is kept. This APC is unarmed and cannot capture, and the enemy is
## far out of anybody's reach.
func test_a_second_walk_alone_never_spends_the_meter() -> void:
	var state := _state("[terrain]\n............\n[units]\n1 p 0 0\n2 i 11 0")
	var commander := state.commander_of(1)
	var mover := state.units[0]
	MoveCommand.new(mover, [Vector2i(0, 0), Vector2i(1, 0)]).apply(state)
	assert_true(mover.refreshable)
	assert_false(commander.wants_power(state, 1), "a second advance is not worth a full meter")


func test_a_refreshed_shot_within_reach_spends_the_meter() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 t 0 0\n2 i 4 0")
	var commander := state.commander_of(1)
	MoveCommand.new(state.units[0], [Vector2i(0, 0), Vector2i(1, 0)]).apply(state)
	assert_true(commander.wants_power(state, 1), "a refreshed tank can walk into range and fire")


func test_a_refreshed_capture_within_reach_spends_the_meter() -> void:
	var state := _state("[terrain]\n..C..\n[units]\n1 i 0 0\n2 i 4 0")
	var commander := state.commander_of(1)
	MoveCommand.new(state.units[0], [Vector2i(0, 0), Vector2i(1, 0)]).apply(state)
	assert_true(
		commander.wants_power(state, 1), "unowned ground the refreshed infantry can stand on"
	)


func test_a_refreshed_capture_out_of_reach_keeps_the_meter() -> void:
	var state := _state("[terrain]\n..........C\n[units]\n1 i 0 0\n2 i 10 0")
	var commander := state.commander_of(1)
	MoveCommand.new(state.units[0], [Vector2i(0, 0), Vector2i(1, 0)]).apply(state)
	assert_false(commander.wants_power(state, 1), "the city is beyond a second walk")
