extends GutTest
## Radek Morn: the flat +5/+5 both terms of the formula count equally, and
## Hammerfall — the game's first aimed Command Power, and the only thing in the
## game that takes a unit off the board without a shot.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String, morn_team: int = 1) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	if morn_team != 0:
		state.set_commander(morn_team, commander_db.by_id(&"radek_morn"))
	return state


## Fires at `target` through the real command, meter and all, so nothing here
## reaches past PowerCommand to call the doctrine directly.
func _fire_at(state: GameState, target: Vector2i) -> void:
	state.add_charge(state.current_team, state.commander_of(state.current_team).power_cost)
	var command := PowerCommand.new()
	command.target = target
	assert_eq(command.validate(state), "")
	command.apply(state)


func _cells_at(state: GameState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for unit in state.units:
		cells.append(unit.cell)
	return cells


func _attack_damage(state: GameState) -> int:
	var attacker := state.units[0]
	return CombatResolver.forecast(state, attacker, attacker.cell, state.units[1]).attack_damage


# --- the flat hand ------------------------------------------------------------


## Both terms, on one matchup: a Tank's MG into an Infantry on plains, base 75
## with one defence star. Neutral it is 75 x 0.9 = 68; his attack multiplies the
## base by 1.05 and his defence the whole chain by (200 - 105) / 100 = 0.95 — Iona
## Vance's shape at +3/+3, simply turned up.
func test_the_attack_and_the_defence_halves_both_count() -> void:
	var board := "[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0"
	assert_eq(_attack_damage(_state(board, 0)), 68, "no commander")
	assert_eq(_attack_damage(_state(board, 1)), 71, "his tank shooting")
	assert_eq(_attack_damage(_state(board, 2)), 64, "his infantry being shot at")


## Nothing specialised: every unit in every domain, with the power down.
func test_the_doctrine_reaches_every_domain_and_needs_no_power() -> void:
	var state := _state(
		"[terrain]\n..SS\n....\n[units]\n1 i 0 0\n1 t 1 0\n1 f 0 1\n1 c 2 0\n2 i 3 1"
	)
	var morn := state.commander_of(1)
	var rival := state.units[4]
	assert_false(state.power_active(1))
	for unit in state.units_of(1):
		var shooting := Engagement.create(unit, unit.cell, 10, rival, rival.cell, 10)
		var shot_at := Engagement.create(rival, rival.cell, 10, unit, unit.cell, 10)
		assert_eq(morn.attack_bonus(state, shooting), 5, "%s attack" % unit.type.id)
		assert_eq(morn.defense_bonus(state, shot_at), 5, "%s defence" % unit.type.id)


# --- the footprint (plan D3) --------------------------------------------------


func test_he_is_the_only_general_who_aims() -> void:
	for co in commander_db.all():
		assert_eq(co.aims_power(), co.id == &"radek_morn", "%s aims_power" % co.id)


func test_the_square_is_the_eight_neighbours_and_the_centre() -> void:
	var state := _state("[terrain]\n....\n....\n....\n....\n[units]\n1 i 0 3")
	assert_eq(
		state.commander_of(1).power_blast_cells(state, 1, Vector2i(2, 1)),
		(
			[
				Vector2i(1, 0),
				Vector2i(2, 0),
				Vector2i(3, 0),
				Vector2i(1, 1),
				Vector2i(2, 1),
				Vector2i(3, 1),
				Vector2i(1, 2),
				Vector2i(2, 2),
				Vector2i(3, 2),
			]
			as Array[Vector2i]
		)
	)


## A corner aim is a legal shot that simply catches fewer tiles, which is the one
## thing that makes aiming into a corner a real decision.
func test_the_square_is_clipped_at_a_corner() -> void:
	var state := _state("[terrain]\n....\n....\n....\n....\n[units]\n1 i 3 3")
	assert_eq(
		state.commander_of(1).power_blast_cells(state, 1, Vector2i.ZERO),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)] as Array[Vector2i]
	)


## Every cell of the board is a legal aim, fog or no fog: validate refuses one off
## the board and has no opinion about what was standing on it.
func test_only_an_off_board_aim_is_refused() -> void:
	var state := _state("[terrain]\n.....\n.....\n.....\n.....\n.....\n[units]\n1 i 0 0\n2 i 4 4")
	state.add_charge(1, state.commander_of(1).power_cost)
	var off := PowerCommand.new()
	off.target = Vector2i(5, 2)
	assert_eq(off.validate(state), "that target is off the board")
	var empty := PowerCommand.new()
	empty.target = Vector2i(2, 2)
	assert_eq(empty.validate(state), "", "bare ground is a legal aim, and a spent meter")


# --- what the square takes (plan D4) ------------------------------------------


## Full health or not, his or theirs. The tank on its last pip and the one at full
## strength leave the board in the same breath.
func test_everything_standing_in_the_square_is_destroyed_whoever_owns_it() -> void:
	var state := _state(
		"[terrain]\n.....\n.....\n.....\n[units]\n1 t 1 1\n1 i 4 2\n2 t 2 1\n2 t 4 0"
	)
	state.units[0].hp = 10
	_fire_at(state, Vector2i(1, 1))
	assert_eq(
		_cells_at(state),
		[Vector2i(4, 2), Vector2i(4, 0)] as Array[Vector2i],
		"only what stood outside the square"
	)


## remove_unit takes a transport's cargo down with it, so the meteor needs no
## opinion about cargo at all.
func test_cargo_goes_down_with_its_transport() -> void:
	var state := _state("[terrain]\n....\n....\n....\n[units]\n1 i 3 2\n2 p 1 1")
	var apc := state.units[1]
	var rider := Unit.create(unit_db.by_id(&"infantry"), 2, apc.cell)
	rider.carrier = apc
	state.units.append(rider)
	_fire_at(state, Vector2i(1, 1))
	assert_eq(state.units.size(), 1, "the APC and its passenger both left")
	assert_eq(state.units[0].team, 1)


## His, theirs and his ally's alike. Hammerfall takes whatever is standing in the
## square, which is the deliberate exception to the ally rule.
func test_an_ally_in_the_square_dies_too() -> void:
	var state := _state("[terrain]\n....\n....\n....\n[units]\n1 t 0 0\n2 t 1 1\n3 t 3 2")
	state.sides = {1: 0, 2: 0}
	_fire_at(state, Vector2i(1, 1))
	assert_eq(
		_cells_at(state),
		[Vector2i(3, 2)] as Array[Vector2i],
		"his own and his ally's both went with it"
	)


## Units only. A headquarters, factory or city in the square keeps its owner —
## only what is standing on it dies.
func test_a_property_in_the_square_keeps_its_owner() -> void:
	var state := _state(
		"[terrain]\n.C..\n....\n....\n[owners]\n2 1 0\n[units]\n1 i 1 0\n1 t 3 2\n2 i 3 1"
	)
	assert_eq(state.owner_at(Vector2i(1, 0)), 2)
	_fire_at(state, Vector2i(1, 0))
	assert_eq(state.owner_at(Vector2i(1, 0)), 2, "the city is still theirs")
	assert_eq(state.units.size(), 2, "the infantry standing on it is not")


## A death outside a fight is not an exchange, so it pays nobody: charge is minted
## in three calls inside CombatResolver and nowhere else. Banking it to the victim
## would make the answer to the most expensive power in the game their own power.
func test_no_charge_is_banked_on_either_side() -> void:
	var state := _state("[terrain]\n....\n....\n....\n[units]\n1 t 3 0\n2 t 1 1\n2 t 3 2")
	state.set_commander(2, commander_db.by_id(&"iona_vance"))
	state.commander_state(2).charge = 5000
	_fire_at(state, Vector2i(1, 1))
	assert_eq(state.commander_state(1).charge, 0, "the cost is spent and nothing comes back")
	assert_eq(state.commander_state(2).charge, 5000, "the victim banks nothing for being nuked")


## A match can now end without a shot, and nothing new was needed for it:
## remove_unit already calls _check_rout, so an army that loses its last unit here
## falls on the path that already fells one shot to pieces.
func test_an_army_that_loses_its_last_unit_in_the_square_falls() -> void:
	var state := _state("[terrain]\n....\n....\n....\n[units]\n1 t 3 2\n2 t 1 1")
	_fire_at(state, Vector2i(1, 1))
	assert_true(state.is_eliminated(2), "its last unit was in the square")
	assert_eq(state.winner, 1, "and the match resolved on the power")


## COM-179: `remove_unit` used to check rout one death at a time, so a blast
## emptying two armies at once had its winner decided by which unit
## `power_blast_cells`' scan happened to reach first — the army whose last
## unit came off the board first fell first, and `_check_victory` then found
## the other side's doomed unit still standing and crowned it. Mirroring the
## board swaps which of the two units the scan meets first; the outcome must
## not move with it. Both his own last unit and the rival's are in the square,
## so this is a true mutual wipeout: nobody is left to win.
func test_a_mutual_wipeout_resolves_the_same_regardless_of_scan_order() -> void:
	var his_unit_scanned_first := _state("[terrain]\n...\n...\n...\n[units]\n1 t 0 0\n2 t 2 0")
	his_unit_scanned_first.rng.seed = 179
	_fire_at(his_unit_scanned_first, Vector2i(1, 1))
	assert_push_error("every remaining army fell at once")

	var rival_scanned_first := _state("[terrain]\n...\n...\n...\n[units]\n1 t 2 0\n2 t 0 0")
	rival_scanned_first.rng.seed = 179
	_fire_at(rival_scanned_first, Vector2i(1, 1))
	assert_push_error("every remaining army fell at once")

	for state in [his_unit_scanned_first, rival_scanned_first]:
		assert_eq(state.winner, 0, "a mutual wipeout has no side left to crown")
		assert_true(state.is_eliminated(1), "his own last unit went into the square too")
		assert_true(state.is_eliminated(2), "and so did theirs")
	assert_eq(
		his_unit_scanned_first.winner,
		rival_scanned_first.winner,
		"same outcome whichever unit the blast scan met first"
	)


## R4: the Balance Lab is *told* how a match ended rather than reading it back off
## a board elimination has already cleared, and a power rout is a rout. A misread
## here silently corrupts every balance report afterwards.
func test_a_power_rout_is_reported_as_a_rout_and_not_as_an_hq_capture() -> void:
	var state := _state("[terrain]\n.Q..\n....\n....\n[owners]\n2 1 0\n[units]\n1 t 3 2\n2 t 1 1")
	_fire_at(state, Vector2i(1, 1))
	assert_eq(BalanceMatchEngine.termination(state, false, false), "rout")


# --- where the computer aims (plan D5) ----------------------------------------


## The aim is the highest-value net square and `wants_power` is that same number,
## because one function answers both — so he cannot want to fire and then aim
## somewhere he did not want to. Three tanks in an L only one square covers.
func test_the_computer_aims_at_the_richest_square_and_wants_to_fire_at_it() -> void:
	var state := _state(
		(
			"[terrain]\n............\n............\n............"
			+ "\n[units]\n1 i 0 0\n2 t 8 0\n2 t 10 0\n2 t 9 2\n2 i 3 1"
		)
	)
	var morn := state.commander_of(1)
	assert_eq(morn.power_target(state, 1), Vector2i(9, 1), "the only square that holds all three")
	assert_true(morn.wants_power(state, 1), "three tanks clears his price")

	_fire_at(state, morn.power_target(state, 1))
	assert_eq(
		_cells_at(state),
		[Vector2i(0, 0), Vector2i(3, 1)] as Array[Vector2i],
		"the square he named is the square he cleared"
	)


## His own side is a loss on the same scale, so the aim steps off his own units.
## And a lone infantry does not pay for the dearest meter in the game — the same
## number saying so, which is why the gate and the aim are one function.
func test_his_own_units_are_priced_against_the_aim() -> void:
	var state := _state("[terrain]\n.......\n[units]\n2 i 3 0\n1 t 4 0")
	var morn := state.commander_of(1)
	assert_eq(morn.power_target(state, 1), Vector2i(2, 0), "the square that spares his own tank")
	assert_false(morn.wants_power(state, 1), "one infantry is not worth 24,000 of meter")


## Scan-ordered over cells, so a replan off one board always agrees with itself:
## two squares worth the same are settled by which comes first, never by chance.
func test_two_equal_squares_are_settled_by_scan_order() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 i 0 0\n2 i 2 0")
	var morn := state.commander_of(1)
	assert_eq(morn.power_target(state, 1), Vector2i(2, 0), "(2,0) and (3,0) both hold the target")
	assert_eq(morn.power_target(state, 1), Vector2i(2, 0), "and asking again says the same")


## Enemies are read through the sight authority, never around it: a submerged
## submarine with nothing of his beside it is not a square worth naming.
func test_a_hidden_enemy_is_not_counted() -> void:
	var state := _state("[terrain]\nSSSSSS\n[units]\n1 c 0 0\n2 s 5 0")
	var morn := state.commander_of(1)
	var sub := state.units[1]
	var aim := morn.power_target(state, 1)
	assert_true(sub.cell in morn.power_blast_cells(state, 1, aim), "surfaced, it is the prize")
	sub.dived = true
	aim = morn.power_target(state, 1)
	assert_false(sub.cell in morn.power_blast_cells(state, 1, aim), "under the water, it is not")


# --- played out ---------------------------------------------------------------


## The whole seam under a real planner: the computer has to reach a firing, the
## rules have to accept the command it issues, and the match has to run on. A
## doctrine that quietly banked its meter all match would pass every unit test
## above and fail here.
func test_a_match_with_morn_at_the_table_fires_the_hammer() -> void:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	assert_not_null(map)
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = 909
	state.set_commander(1, commander_db.by_id(&"radek_morn"))
	state.set_commander(2, commander_db.by_id(&"tomas_reed"))
	var planners: Dictionary = {}
	for team in state.teams:
		planners[team] = AIController.new(unit_db)
	var commands := 0
	var hammers := 0
	while state.winner == 0 and state.day <= 30 and commands < 3000:
		var ai: AIController = planners[state.current_team]
		var command := ai.plan_next_command(state)
		var error := command.validate(state)
		if error != "":
			fail_test("day %d, team %d: %s" % [state.day, state.current_team, error])
			return
		if command is PowerCommand and state.current_team == 1:
			hammers += 1
			assert_true(
				map.in_bounds((command as PowerCommand).target), "the computer aimed off the board"
			)
		command.apply(state)
		commands += 1
	gut.p("first_steps: %d commands, day %d, winner %d" % [commands, state.day, state.winner])
	assert_gt(hammers, 0, "Morn never fired Hammerfall")
