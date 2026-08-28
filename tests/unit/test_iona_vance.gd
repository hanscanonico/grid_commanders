extends GutTest
## Iona Vance: the flat +3/+3 both terms of the formula count equally, and Tip
## the Scales — a pip onto her army, a pip off every hostile one, and nothing off
## the board.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


func _state(map_text: String, vance_team: int = 1) -> GameState:
	return Fixture.state(map_text, {} if vance_team == 0 else {vance_team: &"iona_vance"})


func _attack_damage(state: GameState) -> int:
	var attacker := state.units[0]
	return CombatResolver.forecast(state, attacker, attacker.cell, state.units[1]).attack_damage


# --- the even hand -----------------------------------------------------------


## Both terms, on one matchup: a Tank's MG into an Infantry on plains, base 75
## with one defence star. Neutral it is 75 x 0.9 = 68; her attack multiplies the
## base by 1.03 and her defence the whole chain by (200 - 103) / 100 = 0.97, so
## the two move the same shot in opposite directions by comparable amounts.
func test_the_attack_and_the_defence_halves_both_count() -> void:
	var board := Fixture.TANK_VS_INFANTRY
	assert_eq(_attack_damage(_state(board, 0)), 68, "no commander")
	assert_eq(_attack_damage(_state(board, 1)), 70, "her tank shooting")
	assert_eq(_attack_damage(_state(board, 2)), 65, "her infantry being shot at")


## Nothing specialised: every unit in every domain, with the power down.
func test_the_doctrine_reaches_every_domain_and_needs_no_power() -> void:
	var state := _state(
		"[terrain]\n..SS\n....\n[units]\n1 i 0 0\n1 t 1 0\n1 f 0 1\n1 c 2 0\n2 i 3 1"
	)
	var vance := state.commander_of(1)
	var rival := state.units[4]
	assert_false(state.power_active(1))
	for unit in state.units_of(1):
		var shooting := Engagement.create(unit, unit.cell, 10, rival, rival.cell, 10)
		var shot_at := Engagement.create(rival, rival.cell, 10, unit, unit.cell, 10)
		assert_eq(vance.attack_bonus(state, shooting), 3, "%s attack" % unit.type.id)
		assert_eq(vance.defense_bonus(state, shot_at), 3, "%s defence" % unit.type.id)


# --- Tip the Scales ----------------------------------------------------------


func test_the_swing_moves_a_pip_on_both_sides() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 t 0 0\n2 t 2 0")
	var hers := state.units[0]
	var theirs := state.units[1]
	hers.hp = 50
	theirs.hp = 50
	assert_eq(Fixture.fire_power(state), "")
	assert_eq(hers.hp, 60, "a pip onto her own")
	assert_eq(theirs.hp, 40, "a pip off theirs")


func test_the_heal_never_overshoots_full_health() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 t 0 0\n1 i 1 0\n2 t 2 0")
	state.units[0].hp = 100
	state.units[1].hp = 95
	assert_eq(Fixture.fire_power(state), "")
	assert_eq(state.units[0].hp, 100, "already full")
	assert_eq(state.units[1].hp, 100, "a part-pip short of full")


## The floor is the whole of D4: this power moves numbers and never takes a unit
## off the board, so a unit standing on its last pip is still standing on it —
## and one already under the floor is left there rather than topped up to it.
func test_a_hostile_unit_on_its_last_pip_keeps_it() -> void:
	var state := _state("[terrain]\n====\n[units]\n1 t 0 0\n2 t 1 0\n2 t 2 0\n2 t 3 0")
	state.units[1].hp = 15
	state.units[2].hp = 10
	state.units[3].hp = 3
	assert_eq(Fixture.fire_power(state), "")
	assert_eq(state.units[1].hp, 10, "down to the floor and no further")
	assert_eq(state.units[2].hp, 10, "already on the floor")
	assert_eq(state.units[3].hp, 3, "under the floor, and not healed up to it")
	assert_eq(state.units.size(), 4, "nothing leaves the board")
	for unit in state.units:
		assert_gt(unit.hp, 0, "%s survives" % unit.type.id)


## Health is infrastructure (four-players D2): the heal is her own army's and the
## harm stops at the side boundary, so an ally is missed by both halves.
func test_an_ally_is_untouched_by_both_halves() -> void:
	var state := _state("[terrain]\n====\n[units]\n1 t 0 0\n2 t 1 0\n3 t 2 0\n4 t 3 0")
	state.sides = {1: 0, 2: 0}
	for unit in state.units:
		unit.hp = 50
	assert_eq(Fixture.fire_power(state), "")
	assert_eq(state.units[0].hp, 60, "hers")
	assert_eq(state.units[1].hp, 50, "her ally's, neither mended nor hurt")
	assert_eq(state.units[2].hp, 40, "a rival")
	assert_eq(state.units[3].hp, 40, "the other rival")


## R5: the harm reaches every hostile army, exactly as Signal Jam does, so a
## four-seat free-for-all is three opponents in one command.
func test_the_harm_lands_on_all_three_opponents_of_a_four_army_board() -> void:
	var state := _state("[terrain]\n====\n[units]\n1 t 0 0\n2 t 1 0\n3 t 2 0\n4 t 3 0")
	for unit in state.units:
		unit.hp = 50
	assert_eq(Fixture.fire_power(state), "")
	assert_eq(state.units[0].hp, 60)
	for unit in state.units.slice(1):
		assert_eq(unit.hp, 40, "team %d" % unit.team)


# --- the AI gate -------------------------------------------------------------


func test_the_gate_fires_where_there_are_pips_to_move_and_a_fight_to_move_them_in() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 t 0 0\n2 t 2 0")
	assert_true(state.commander_of(1).wants_power(state, 1))


## Both halves at their clamp: her army full, the one rival on the floor. There
## is a fight to have, and firing would move nothing in it.
func test_the_gate_stays_quiet_when_the_swing_would_move_nothing() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 t 0 0\n2 t 2 0")
	state.units[1].hp = 10
	assert_false(state.commander_of(1).wants_power(state, 1))


func test_the_gate_stays_quiet_with_nobody_in_contact() -> void:
	var state := _state("[terrain]\n" + "=".repeat(30) + "\n[units]\n1 t 0 0\n2 t 29 0")
	state.units[0].hp = 50
	assert_false(state.commander_of(1).wants_power(state, 1))


## Enemies are read through the sight authority, never around it: a submerged
## submarine with nothing of hers beside it is not a reason to fire.
func test_a_hidden_enemy_is_not_counted() -> void:
	var state := _state("[terrain]\nSSSSSS\n[units]\n1 c 0 0\n2 s 5 0")
	assert_true(state.commander_of(1).wants_power(state, 1), "surfaced, it is worth a pip")
	state.units[1].dived = true
	assert_false(state.commander_of(1).wants_power(state, 1))


# --- four armies, played out --------------------------------------------------


## The board-wide swing under four planners, which is the shape R5 is about: the
## rules must accept every command it leads to, and the match must still finish.
## Her seat is asserted to have fired, so a doctrine that quietly banked its meter
## all match cannot pass this as a soak of the other three.
func test_a_four_army_match_runs_and_resolves_with_vance_at_the_table() -> void:
	var map := MapData.load_from_file("res://maps/fixtures/quartet.txt", terrain_db)
	assert_not_null(map)
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = 660
	var doctrines: Array[StringName] = [&"iona_vance", &"mara_voss", &"orin_flux", &"nia_rowan"]
	for i in state.teams.size():
		state.set_commander(state.teams[i], commander_db.by_id(doctrines[i]))
	var planners: Dictionary = {}
	for team in state.teams:
		planners[team] = AIController.new(unit_db)
	var commands := 0
	var vance_powers := 0
	while state.winner == 0 and state.day <= 30 and commands < 3000:
		var ai: AIController = planners[state.current_team]
		var command := ai.plan_next_command(state)
		var error := command.validate(state)
		if error != "":
			fail_test("day %d, team %d: %s" % [state.day, state.current_team, error])
			return
		command.apply(state)
		commands += 1
		if command is PowerCommand and (command as PowerCommand).team == state.teams[0]:
			vance_powers += 1
	gut.p("quartet: %d commands, day %d, winner %d" % [commands, state.day, state.winner])
	assert_gt(vance_powers, 0, "Vance never fired Tip the Scales")
	assert_ne(state.winner, 0, "the match resolved")
