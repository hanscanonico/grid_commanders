extends GutTest
## Rhea Sol, and with her the R3 guard: rules, AI and UI must agree on how far
## an indirect unit can shoot once a doctrine has moved the answer.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


func _state(map_text: String, with_rhea: bool = true) -> GameState:
	return Fixture.state(map_text, {1: &"rhea_sol"} if with_rhea else {})


# --- the doctrine ------------------------------------------------------------


## Artillery vs Infantry on plains, base 90: 90 * 1.1 * 0.9 = 89.1 -> 89,
## against 90 * 0.9 = 81 flat.
func test_indirect_units_hit_harder() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 g 0 0\n2 i 2 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		89
	)


## Tank vs Artillery on plains, base 70: her guns take 70 * 0.9 * 1.1 = 69.3
## -> 69, against 70 * 0.9 = 63 flat.
func test_indirect_units_are_softer() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 g 0 0\n2 t 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[1], Vector2i(1, 0), state.units[0])
			. attack_damage
		),
		69
	)


func test_direct_units_are_untouched() -> void:
	var map_text := "[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0"
	var neutral := _state(map_text, false)
	var rhea := _state(map_text)
	assert_eq(
		CombatResolver.forecast(rhea, rhea.units[0], Vector2i(0, 0), rhea.units[1]).attack_damage,
		(
			CombatResolver
			. forecast(neutral, neutral.units[0], Vector2i(0, 0), neutral.units[1])
			. attack_damage
		)
	)


# --- Grid Saturation, and the shared range helper ----------------------------


## Artillery is range 2-3. The power takes it to 4 — and the command, the AI and
## the targeting overlay all have to agree, which is why they share AttackRange.
func test_the_power_extends_the_firing_range() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 g 0 0\n2 i 4 0")
	var artillery := state.units[0]
	assert_eq(AttackRange.maximum(state, artillery), 3)
	assert_false(AttackRange.covers(state, artillery, artillery.cell, Vector2i(4, 0)))
	var before := AttackCommand.new(artillery, [artillery.cell], Vector2i(4, 0))
	assert_eq(before.validate(state), "target out of range")

	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(AttackRange.maximum(state, artillery), 4)
	assert_true(AttackRange.covers(state, artillery, artillery.cell, Vector2i(4, 0)))
	assert_eq(AttackCommand.new(artillery, [artillery.cell], Vector2i(4, 0)).validate(state), "")


func test_the_minimum_range_is_not_moved() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 g 0 0\n2 i 1 0")
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(AttackRange.minimum(state, state.units[0]), 2, "the dead zone stays")
	assert_eq(
		AttackCommand.new(state.units[0], [state.units[0].cell], Vector2i(1, 0)).validate(state),
		"target out of range"
	)


func test_direct_units_gain_no_range() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 t 0 0\n2 i 2 0")
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(AttackRange.maximum(state, state.units[0]), 1)


func test_an_unarmed_unit_never_gains_a_weapon() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 p 0 0\n2 i 1 0")
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(AttackRange.maximum(state, state.units[0]), 0)
	assert_false(AttackRange.covers(state, state.units[0], Vector2i(0, 0), Vector2i(1, 0)))


## The AI finds the extended shot, because its target search asks the same
## helper the command does.
func test_the_ai_takes_the_extended_shot() -> void:
	var state := _state("[terrain]\n.....\n.....\n[units]\n1 g 0 0\n2 i 4 0")
	assert_eq(Fixture.fire_power(state, 1), "")
	var ai := AIController.new(unit_db)
	var command := ai.plan_next_command(state)
	assert_true(command is AttackCommand, "expected an attack, got %s" % command)
	assert_eq((command as AttackCommand).target_cell, Vector2i(4, 0))


## The extra reach must not turn a siege gun into something that shoots back:
## countering is adjacency, whatever a doctrine does to firing range.
func test_the_power_does_not_let_indirects_counter() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 g 0 0\n2 t 1 0")
	assert_eq(Fixture.fire_power(state, 1), "")
	state.rng.seed = 3
	var result := CombatResolver.resolve(state, state.units[1], state.units[0])
	assert_gt(result.attack_damage, 0)
	assert_false(result.countered, "artillery still never counters")


func test_the_power_expires_with_the_turn() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 g 0 0\n2 i 4 0")
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(AttackRange.maximum(state, state.units[0]), 4)
	EndTurnCommand.new().apply(state)
	assert_eq(AttackRange.maximum(state, state.units[0]), 3)


# --- production advice -------------------------------------------------------


## The pull is mild by measurement, not oversight: at -4 the doctrine matrix
## priced her at 34% — an army of guns the planner cannot move-and-fire — so
## the bias orders the cheap end of the build list and leaves its top alone.
func test_build_advice_pulls_indirects_mildly() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 g 0 0\n2 t 1 0")
	var co := state.commander_of(1)
	assert_eq(co.build_bias(state, 1, unit_db.by_id(&"artillery")), -2)
	assert_eq(co.build_bias(state, 1, unit_db.by_id(&"rockets")), -2, "keyed on being indirect")
	assert_eq(co.build_bias(state, 1, unit_db.by_id(&"tank")), 0)
