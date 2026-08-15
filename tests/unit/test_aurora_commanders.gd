extends GutTest
## This is the home for cass_orlov, cassian_rook, lyra_quill and orin_flux
## coverage — grep for any of those names lands here rather than at a
## test_cass_orlov.gd-style file that does not exist.
##
## The Aurora Compact three — Lyra Quill, Orin Flux and Cassian Rook — plus
## Cass Orlov, who shares their remaining hook needs. Grouped because between
## them they cover the last three things wave 2 added: the luck-range hooks, a
## power that reaches across the table, and HP-threshold targeting.


func _state(map_text: String, commander: StringName) -> GameState:
	return Fixture.state(map_text, {} if commander == &"" else {1: commander})


# --- Lyra Quill: the luck hooks ----------------------------------------------


## Her floor is 4, so a Tank MG that would roll 68-77 against Infantry rolls 72-77.
## Checked over many seeds rather than one, since the point is the range.
func test_her_luck_never_rolls_low() -> void:
	for seed_value in 40:
		var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 1 0", &"lyra_quill")
		state.rng.seed = seed_value
		var result := CombatResolver.resolve(state, state.units[0], state.units[1])
		assert_between(result.attack_damage, 68 + 4, 68 + 9, "seed %d" % seed_value)


func test_her_units_are_slightly_softer() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0", &"lyra_quill")
	# Tank MG into her Infantry: 75 * (200 - 95)/100 * 0.9 = 70.875 -> 71.
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[1], Vector2i(1, 0), state.units[0])
			. attack_damage
		),
		71
	)


## Perfect Solution: maximum luck every time, plus +10% attack.
## 75 * 1.1 * 0.9 = 74.25 -> 74, and always +9.
func test_her_power_removes_the_roll() -> void:
	for seed_value in 10:
		var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 i 1 0", &"lyra_quill")
		state.rng.seed = seed_value
		assert_eq(Fixture.fire_power(state, 1), "")
		var result := CombatResolver.resolve(state, state.units[0], state.units[1])
		assert_eq(result.attack_damage, 74 + 9, "seed %d" % seed_value)


## Determinism still holds: a narrowed range must draw exactly one number from
## the seeded RNG, or a replay recorded on that seed falls out of step.
func test_a_narrowed_luck_range_stays_replayable() -> void:
	var damages: Array[int] = []
	for run in 2:
		var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n2 t 1 0", &"lyra_quill")
		state.rng.seed = 99
		var result := CombatResolver.resolve(state, state.units[0], state.units[1])
		damages.append(result.attack_damage)
		damages.append(result.counter_damage)
	assert_eq(damages[0], damages[2])
	assert_eq(damages[1], damages[3])


# --- Orin Flux: reaching across the table ------------------------------------


func test_his_scouts_see_further() -> void:
	var state := _state("[terrain]\n......\n......\n[units]\n1 r 0 0", &"orin_flux")
	state.fog_enabled = true
	var visible := Vision.visible_cells(state, 1)
	# Recon sees 5 tiles of Manhattan reach; his sees 6.
	assert_true(visible.has(Vector2i(5, 1)), "his Recon reaches 6")
	var neutral := _state("[terrain]\n......\n......\n[units]\n1 r 0 0", &"")
	neutral.fog_enabled = true
	assert_false(Vision.visible_cells(neutral, 1).has(Vector2i(5, 1)), "an ordinary one does not")


func test_signal_jam_slows_the_enemy() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 r 0 0\n2 t 2 0", &"orin_flux")
	var enemy := state.units[1]
	var friendly := state.units[0]
	assert_eq(MovementResolver.move_budget(state, enemy), enemy.type.move_points)
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(
		MovementResolver.move_budget(state, enemy), enemy.type.move_points - 1, "a point gone"
	)
	assert_eq(
		MovementResolver.move_budget(state, friendly),
		friendly.type.move_points,
		"his own army is untouched"
	)


## Slowed, never frozen: the floor in move_budget is what stops a jam parking a
## one-point unit, and it may not reach around the fuel cap to do it.
func test_signal_jam_leaves_a_slow_unit_one_step() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 r 0 0\n2 t 2 0", &"orin_flux")
	var enemy := state.units[1]
	assert_eq(Fixture.fire_power(state, 1), "")
	enemy.type = enemy.type.duplicate()  # never the shared DB resource
	enemy.type.move_points = 1
	assert_eq(MovementResolver.move_budget(state, enemy), 1, "still one step")
	enemy.fuel = 0
	assert_eq(MovementResolver.move_budget(state, enemy), 0, "but an empty tank stays put")


func test_signal_jam_shortens_enemy_vision() -> void:
	var state := _state("[terrain]\n......\n......\n[units]\n1 r 0 0\n2 r 5 1", &"orin_flux")
	state.fog_enabled = true
	var far := Vector2i(1, 1)  # 4 + 0 = Manhattan 4 from the enemy recon at (5,1)
	assert_true(Vision.visible_cells(state, 2).has(far), "recon sees 5")
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_true(state.power_active(1))
	var jammed := Vision.visible_cells(state, 2)
	assert_true(jammed.has(Vector2i(2, 1)), "still sees 4")
	assert_false(jammed.has(Vector2i(0, 1)), "but no longer 5")


## ROUND duration, so "until their next turn" means it is still up while the
## opponent actually plays.
func test_signal_jam_lasts_through_the_opponents_turn() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 r 0 0\n2 t 2 0", &"orin_flux")
	assert_eq(Fixture.fire_power(state, 1), "")
	EndTurnCommand.new().apply(state)
	assert_true(state.power_active(1), "still jamming while blue plays")
	EndTurnCommand.new().apply(state)
	assert_false(state.power_active(1))


# --- Cassian Rook: movement ---------------------------------------------------


func test_his_light_units_are_faster_and_his_heavy_ones_softer() -> void:
	var state := _state(
		"[terrain]\n....\n....\n[units]\n1 r 0 0\n1 t 0 1\n2 i 3 0", &"cassian_rook"
	)
	var recon := state.units[0]
	var tank := state.units[1]
	assert_eq(MovementResolver.move_budget(state, recon), recon.type.move_points + 1)
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points, "treads unchanged")
	# Tank MG vs Infantry: 75 * 0.9 * 0.9 = 60.75 -> 61, against 68.
	assert_eq(
		CombatResolver.forecast(state, tank, Vector2i(0, 1), state.units[2]).attack_damage, 61
	)


## Rapid Redeployment moves everything and costs the turn's damage to do it.
func test_his_power_trades_damage_for_movement() -> void:
	var state := _state(
		"[terrain]\n....\n....\n[units]\n1 r 0 0\n1 t 0 1\n2 i 3 0", &"cassian_rook"
	)
	var recon := state.units[0]
	var tank := state.units[1]
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(MovementResolver.move_budget(state, recon), recon.type.move_points + 3, "1 + 2")
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points + 2)
	# Tank now at -30 total: 75 * 0.7 * 0.9 = 47.25 -> 47.
	assert_eq(
		CombatResolver.forecast(state, tank, Vector2i(0, 1), state.units[2]).attack_damage, 47
	)


# --- Cass Orlov: HP-threshold targeting ---------------------------------------


func test_she_hits_nearly_dead_units_harder() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0", &"cass_orlov")
	var target := state.units[1]
	# Healthy: no bonus. 75 * 0.9 = 67.5 -> 68.
	assert_eq(
		CombatResolver.forecast(state, state.units[0], Vector2i(0, 0), target).attack_damage, 68
	)
	target.hp = 50  # 5 displayed: inside her threshold
	# 75 * 1.15 * (1 - 0.1 * 1 * 0.5) = 81.9375 -> 82.
	assert_eq(
		CombatResolver.forecast(state, state.units[0], Vector2i(0, 0), target).attack_damage, 82
	)


## The finisher's bonus costs her nothing: her army defends like anyone else's.
func test_her_own_units_defend_normally() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0", &"cass_orlov")
	# Tank MG into her Infantry: 75 * (200 - 100)/100 * 0.9 = 67.5 -> 68.
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[1], Vector2i(1, 0), state.units[0])
			. attack_damage
		),
		68
	)


## No Escape widens "damaged" from nearly-dead to anything short of full.
func test_her_power_widens_what_counts_as_damaged() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0", &"cass_orlov")
	var target := state.units[1]
	target.hp = 90  # 9 displayed: outside the passive, inside the power
	var fight := Engagement.create(state.units[0], Vector2i(0, 0), 10, target, Vector2i(1, 0), 9)
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 0, "passive needs 5 HP or less")
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 30)


## The other half of No Escape: the two chasers on `no_escape_ids` get a tile to
## run the wounded down with, and nobody else does. Read through
## MovementResolver.move_budget, which is the one caller of the hook.
func test_her_power_hurries_the_two_units_that_do_the_chasing() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 r 0 0\n1 i 1 0\n1 t 2 0", &"cass_orlov")
	var recon := state.units[0]
	var infantry := state.units[1]
	var tank := state.units[2]
	for unit in state.units:
		assert_eq(
			MovementResolver.move_budget(state, unit),
			unit.type.move_points,
			"%s walks its own distance while the meter is banking" % unit.type.id
		)
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(MovementResolver.move_budget(state, recon), recon.type.move_points + 1)
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points + 1)
	assert_eq(
		MovementResolver.move_budget(state, infantry),
		infantry.type.move_points,
		"the infantry is not on the list and gains nothing"
	)
