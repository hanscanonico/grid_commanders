extends GutTest
## Sera Lark: the +1 every domain gets, Forced March stacking on top of it, and
## the fuel that must still bill only the steps actually walked.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


func _state(map_text: String, with_lark: bool = true) -> GameState:
	return Fixture.state(map_text, {1: &"sera_lark"} if with_lark else {})


## One board with a unit of each domain on it: foot, treads, air and a hull.
func _all_domains(with_lark: bool = true) -> GameState:
	var map_text := "[terrain]\n..SS\n....\n[units]\n1 i 0 0\n1 t 1 0\n1 f 0 1\n1 c 2 0"
	return _state(map_text, with_lark)


# --- the passive -------------------------------------------------------------


func test_every_domain_moves_one_tile_further() -> void:
	var state := _all_domains()
	var neutral := _all_domains(false)
	for i in state.units.size():
		var unit := state.units[i]
		assert_eq(
			MovementResolver.move_budget(state, unit),
			unit.type.move_points + 1,
			"%s under Lark" % unit.type.id
		)
		assert_eq(
			MovementResolver.move_budget(neutral, neutral.units[i]),
			unit.type.move_points,
			"%s without her" % unit.type.id
		)


## The budget is the whole doctrine: a mountain still costs a foot unit two, so
## the extra tile is bought on the flat rather than off the terrain.
func test_terrain_costs_are_untouched() -> void:
	var state := _state("[terrain]\n.M\n[units]\n1 i 0 0")
	var mountain := terrain_db.by_symbol("M")
	assert_eq(MovementResolver.step_cost(state, state.units[0], mountain), 2)


func test_the_passive_reaches_a_tile_the_neutral_army_cannot() -> void:
	var map_text := "[terrain]\n.....\n[units]\n1 i 0 0"
	var state := _state(map_text)
	assert_true(MovementResolver.reachable(state, state.units[0]).has(Vector2i(4, 0)))
	var neutral := _state(map_text, false)
	assert_false(MovementResolver.reachable(neutral, neutral.units[0]).has(Vector2i(4, 0)))


# --- Forced March ------------------------------------------------------------


func test_the_power_stacks_on_the_passive() -> void:
	var state := _all_domains()
	assert_eq(Fixture.fire_power(state, 1), "")
	for unit in state.units:
		assert_eq(
			MovementResolver.move_budget(state, unit),
			unit.type.move_points + 2,
			"%s marching" % unit.type.id
		)


func test_the_power_expires_with_the_turn_and_the_passive_outlives_it() -> void:
	var state := _all_domains()
	var infantry := state.units[0]
	assert_eq(Fixture.fire_power(state, 1), "")
	EndTurnCommand.new().apply(state)
	assert_eq(MovementResolver.move_budget(state, infantry), infantry.type.move_points + 1)


## Movement granted is not movement spent: a marching infantry with five points
## that walks two plains tiles is billed for two.
func test_fuel_is_spent_for_the_steps_taken_not_the_budget_granted() -> void:
	var state := _state("[terrain]\n......\n[units]\n1 i 0 0")
	var infantry := state.units[0]
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(MovementResolver.move_budget(state, infantry), infantry.type.move_points + 2)
	var before := infantry.fuel
	state.advance_unit(infantry, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	assert_eq(before - infantry.fuel, 2, "two plains steps, whatever the budget was")


# --- the AI gate -------------------------------------------------------------


## Forced March buys ground rather than a fight, so the gate weighs the property
## the march itself would put in reach — a city five plains from an infantry that
## already moves four with her passive is exactly the case it exists for.
func test_the_gate_counts_the_move_the_march_would_grant() -> void:
	var state := _state("[terrain]\n.....C\n[units]\n1 i 0 0")
	assert_false(MovementResolver.reachable(state, state.units[0]).has(Vector2i(5, 0)))
	assert_true(state.commander_of(1).wants_power(state, 1))


func test_the_gate_stays_quiet_with_nothing_to_reach_and_nobody_to_fight() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 i 0 0")
	assert_false(state.commander_of(1).wants_power(state, 1))


## Forced March grants no damage, so a fight already in reach is no reason to
## spend the meter: the tile it buys changes nothing about that shot.
func test_forced_march_refuses_a_pure_fight() -> void:
	var map_text := "[terrain]\n.....\n[units]\n1 t 0 0\n2 t 2 0"
	var neutral := _state(map_text, false)
	assert_true(neutral.commander_of(1).wants_power(neutral, 1), "the offensive default fires")
	var state := _state(map_text)
	assert_false(state.commander_of(1).wants_power(state, 1), "Lark holds")
