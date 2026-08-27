extends GutTest
## Alina Ward: combined-arms adjacency, and Coordinated Push.

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
	return Fixture.state(map_text, {1: &"alina_ward"})


func _damage(state: GameState, attacker: Unit, defender: Unit) -> int:
	return CombatResolver.forecast(state, attacker, attacker.cell, defender).attack_damage


# --- the doctrine ------------------------------------------------------------


## Tank MG alone on plains: 75 * 0.9 = 67.5 -> 68, the neutral number.
func test_a_lone_unit_gets_no_bonus() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 t 0 0\n2 i 1 0")
	assert_eq(_damage(state, state.units[0], state.units[1]), 68)


## Same shot with a friendly Infantry (foot) beside the Tank (treads):
## 75 * 1.1 * 0.9 = 74.25 -> 74.
func test_a_neighbour_of_another_class_lifts_the_attack() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 t 0 0\n1 i 0 1\n2 i 1 0")
	assert_eq(_damage(state, state.units[0], state.units[2]), 74)


func test_a_neighbour_of_the_same_class_does_not() -> void:
	# Tank beside an APC: both treads, so the line is not actually mixed.
	var state := _state("[terrain]\n..\n..\n[units]\n1 t 0 0\n1 p 0 1\n2 i 1 0")
	assert_eq(_damage(state, state.units[0], state.units[2]), 68)


## The infantry riding that APC is on the APC's cell but is not on the board, so
## a ferried squad does not make the line mixed — the carrier filter, from the
## side that would otherwise pay a bonus for a unit nobody can see.
func test_a_passenger_is_not_a_neighbour() -> void:
	var state := _state("[terrain]\n...\n...\n[units]\n1 t 0 0\n1 p 0 1\n1 i 2 1\n2 i 1 0")
	var infantry := state.units[2]
	infantry.carrier = state.units[1]
	infantry.cell = state.units[1].cell
	assert_eq(_damage(state, state.units[0], state.units[3]), 68)
	infantry.carrier = null
	assert_eq(_damage(state, state.units[0], state.units[3]), 74, "set down, it counts")


## Infantry is foot and Mech is boot: separate movement classes, and these
## two count as different even though both walk.
func test_infantry_and_mech_count_as_mixed() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 i 0 0\n1 m 0 1\n2 t 1 0")
	# infantry -> tank base 5: 5 * 1.1 * 0.9 = 4.95 -> 5, against 4.5 -> 5 flat.
	# Compare the hook directly, since the rounding hides it at this base damage.
	var fight := Engagement.create(
		state.units[0], Vector2i(0, 0), 10, state.units[2], Vector2i(1, 0), 10
	)
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 10)


func test_an_enemy_neighbour_is_not_a_friendly_one() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 t 0 0\n2 i 0 1\n2 i 1 0")
	assert_eq(_damage(state, state.units[0], state.units[2]), 68)


## The bonus follows the cell the shot is fired *from*, not the cell the unit
## currently stands on — otherwise the damage preview would lie about a move.
func test_the_bonus_is_judged_from_the_planned_firing_cell() -> void:
	var state := _state("[terrain]\n...\n...\n[units]\n1 t 0 0\n1 i 2 1\n2 i 2 0")
	var tank := state.units[0]
	var target := state.units[2]
	# Where it stands, at (0,0), it has no neighbours at all.
	assert_eq(CombatResolver.forecast(state, tank, Vector2i(0, 0), target).attack_damage, 68)
	# Previewing a shot from (1,1) puts the friendly infantry at (2,1) beside it,
	# and the preview has to say so before the move is committed.
	assert_eq(CombatResolver.forecast(state, tank, Vector2i(1, 1), target).attack_damage, 74)


# --- Coordinated Push --------------------------------------------------------


func test_the_power_lifts_attack_defence_and_movement() -> void:
	var state := _state("[terrain]\n...\n...\n[units]\n1 t 0 0\n2 i 1 0")
	var tank := state.units[0]
	var base_budget := MovementResolver.move_budget(state, tank)
	state.add_charge(1, state.commander_of(1).power_cost)
	PowerCommand.new().apply(state)
	# 75 * 1.1 * 0.9 = 74.25 -> 74, the same lift the adjacency gives.
	assert_eq(_damage(state, tank, state.units[1]), 74, "attack")
	assert_eq(MovementResolver.move_budget(state, tank), base_budget + 1, "movement")
	# Blue infantry shooting back at a tank under Push: base 5, def 110, so
	# 5 * 1.0 * 0.9 * 0.9 = 4.05 -> 4, against 4.5 -> 5 without it.
	assert_eq(_damage(state, state.units[1], tank), 4, "defence")


func test_the_power_expires_with_the_turn() -> void:
	var state := _state("[terrain]\n...\n...\n[units]\n1 t 0 0\n2 i 1 0")
	var tank := state.units[0]
	state.add_charge(1, state.commander_of(1).power_cost)
	PowerCommand.new().apply(state)
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points + 1)
	EndTurnCommand.new().apply(state)
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points)
	assert_eq(_damage(state, tank, state.units[1]), 68, "back to the neutral number")


## Both halves of the doctrine stack: adjacency and the power are separate
## percentage points on the same attack.
func test_the_power_stacks_with_the_adjacency_bonus() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 t 0 0\n1 i 0 1\n2 i 1 0")
	state.add_charge(1, state.commander_of(1).power_cost)
	PowerCommand.new().apply(state)
	# 75 * 1.2 * 0.9 = 81
	assert_eq(_damage(state, state.units[0], state.units[2]), 81)


# --- ground advice -----------------------------------------------------------


## The same neighbour test the attack bonus reads, asked about a cell the unit
## is only considering: beside the infantry counts, beside nothing does not.
func test_stand_advice_wants_a_mixed_neighbour() -> void:
	var state := _state("[terrain]\n....\n....\n[units]\n1 t 0 0\n1 i 2 1\n2 i 3 0")
	var co := state.commander_of(1)
	var tank := state.units[0]
	assert_eq(co.stand_value(state, tank, Vector2i(2, 0)), 1, "the infantry is below this cell")
	assert_eq(co.stand_value(state, tank, Vector2i(0, 1)), 0, "nothing stands beside this one")
