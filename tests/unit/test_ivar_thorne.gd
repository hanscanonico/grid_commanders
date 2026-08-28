extends GutTest
## Ivar Thorne: attack points for every pip his attacker is missing — read off
## the Engagement rather than the unit, which is D7 — and Cut Both Ways, two pips
## off every unit standing on the board and nothing off it.


func _state(map_text: String, thorne_team: int = 1) -> GameState:
	return Fixture.state(map_text, {} if thorne_team == 0 else {thorne_team: &"ivar_thorne"})


# --- wounded and dangerous ----------------------------------------------------


## The doctrine itself, in the currency it is written in: eight points a pip,
## counted off the displayed health the formula is using.
func test_the_bonus_is_eight_points_for_every_pip_the_attacker_is_missing() -> void:
	var state := _state("[terrain]\n==\n[units]\n1 t 0 0\n2 t 1 0")
	var thorne := state.commander_of(1)
	var his := state.units[0]
	var rival := state.units[1]
	for pips_and_points: Array in [[10, 0], [5, 40], [1, 72]]:
		var fight := Engagement.create(his, his.cell, pips_and_points[0], rival, rival.cell, 10)
		assert_eq(
			thorne.attack_bonus(state, fight),
			pips_and_points[1],
			"%d pips standing" % pips_and_points[0]
		)


## The arithmetic that is the design (§5): the formula already scales damage by
## the attacker's health, and the bonus only makes that slope shallower. Artillery
## into a tank on road is a flat base 70, so the two columns read straight off.
func test_the_bonus_softens_the_health_scaling_and_never_reverses_it() -> void:
	var board := "[terrain]\n===\n[units]\n1 g 0 0\n2 t 2 0"
	var plain := _state(board, 0)
	var his := _state(board)
	assert_eq(_shot_damage(plain, 100), 70, "a full gun, plain")
	assert_eq(_shot_damage(his, 100), 70, "full health earns him nothing")
	assert_eq(_shot_damage(plain, 50), 35, "half a gun, plain: 0.50")
	assert_eq(_shot_damage(his, 50), 49, "0.50 x 1.40 = 0.70 of a full shot")
	assert_eq(_shot_damage(plain, 10), 7, "one pip, plain: 0.10")
	assert_eq(_shot_damage(his, 10), 12, "0.10 x 1.72 = 0.17")
	assert_lt(_shot_damage(his, 50), _shot_damage(his, 100), "he never profits from being hurt")


func _shot_damage(state: GameState, hp: int) -> int:
	var gun := state.units[0]
	gun.hp = hp
	return CombatResolver.forecast(state, gun, gun.cell, state.units[1]).attack_damage


## D7, and the bar this milestone is measured against. A forecast prices the
## counter at the defender's *projected* post-attack health, so his tank is shown
## at ten pips and answers from four: a doctrine reading the live unit would price
## that counter at +0% and the resolver would then fire it at +48%.
##
## Luck is all that separates the prediction from the exchange, so it is read off
## a second generator on the same seed rather than hunted for — `_luck` draws
## exactly once per shot, opening then counter. The tank is left on exactly forty
## internal HP, so no roll can move which pip band it answers from.
func test_the_forecast_and_the_resolved_counter_agree_on_a_wounded_answer() -> void:
	var seed_used := 4242
	var state := _state("[terrain]\n==\n[units]\n2 t 0 0\n1 t 1 0")
	var raider := state.units[0]
	var his := state.units[1]
	his.hp = 95
	var forecast := CombatResolver.forecast(state, raider, raider.cell, his)
	assert_eq(forecast.attack_damage, 55, "a full tank into a tank on road")
	assert_eq(his.displayed_hp(), 10, "the live unit is untouched at ten pips")
	assert_eq(forecast.counter_damage, 33, "answered from four pips: 55 x 1.48 x 0.4")

	var thorne := state.commander_of(1)
	var projected := Engagement.create(his, his.cell, 4, raider, raider.cell, 10, true)
	var live := Engagement.create(his, his.cell, his.displayed_hp(), raider, raider.cell, 10, true)
	assert_eq(thorne.attack_bonus(state, projected), 48, "what the forecast priced the counter at")
	assert_eq(thorne.attack_bonus(state, live), 0, "what reading the live unit would have priced")

	state.rng.seed = seed_used
	var rolls := RandomNumberGenerator.new()
	rolls.seed = seed_used
	var opening_luck := rolls.randi_range(0, CommanderType.LUCK_MAX)
	var counter_luck := rolls.randi_range(0, CommanderType.LUCK_MAX)
	var result := CombatResolver.resolve(state, raider, his)
	assert_eq(his.displayed_hp(), 4, "answered from four pips whatever the opening roll")
	assert_eq(result.attack_damage, forecast.attack_damage + opening_luck, "the opening shot")
	assert_eq(result.counter_damage, forecast.counter_damage + counter_luck, "and the counter")


# --- Cut Both Ways ------------------------------------------------------------


## D6's deliberate exception: everyone pays. His own army, his ally's and every
## hostile one alike, which is what the power is.
func test_the_cut_reaches_his_own_army_his_allys_and_every_enemys() -> void:
	var state := _state("[terrain]\n====\n[units]\n1 t 0 0\n2 t 1 0\n3 t 2 0\n4 t 3 0")
	state.sides = {1: 0, 2: 0}
	for unit in state.units:
		unit.hp = 50
	assert_eq(Fixture.fire_power(state), "")
	assert_eq(state.units[0].hp, 30, "his own")
	assert_eq(state.units[1].hp, 30, "his ally's, which no other power touches")
	assert_eq(state.units[2].hp, 30, "a rival")
	assert_eq(state.units[3].hp, 30, "the other rival")


## The floor is D4's whole bar: this power moves numbers and takes nothing off the
## board, so a unit on two pips or less is left standing on one — and one already
## under the floor is left where it stands rather than topped up to it.
func test_nothing_dies_and_a_unit_on_one_pip_is_still_on_one_pip() -> void:
	var state := _state("[terrain]\n=====\n[units]\n1 t 0 0\n2 t 1 0\n2 t 2 0\n2 t 3 0\n2 t 4 0")
	state.units[1].hp = 100
	state.units[2].hp = 25
	state.units[3].hp = 10
	state.units[4].hp = 4
	assert_eq(Fixture.fire_power(state), "")
	assert_eq(state.units[0].hp, 80, "two pips off his own")
	assert_eq(state.units[1].hp, 80, "two pips off a full one")
	assert_eq(state.units[2].hp, 10, "down to the floor and no further")
	assert_eq(state.units[3].hp, 10, "already on its last pip, and still standing on it")
	assert_eq(state.units[4].hp, 4, "under the floor, and not healed up to it")
	assert_eq(state.units.size(), 5, "nothing leaves the board")


# --- the AI gate --------------------------------------------------------------


func test_the_gate_fires_where_there_is_blood_to_take_and_a_fight_to_take_it_in() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 t 0 0\n2 t 2 0")
	assert_true(state.commander_of(1).wants_power(state, 1))


## Nothing dies, so the only thing worth weighing is whether the other side has
## anything left to lose: an army already on its last pip is not worth a meter.
func test_the_gate_stays_quiet_when_every_enemy_is_on_the_floor() -> void:
	var state := _state("[terrain]\n===\n[units]\n1 t 0 0\n2 t 2 0")
	state.units[0].hp = 50
	state.units[1].hp = 10
	assert_false(state.commander_of(1).wants_power(state, 1))


func test_the_gate_stays_quiet_with_nobody_in_contact() -> void:
	var state := _state("[terrain]\n" + "=".repeat(30) + "\n[units]\n1 t 0 0\n2 t 29 0")
	assert_false(state.commander_of(1).wants_power(state, 1))


## Enemies are read through the sight authority, never around it: a submerged
## submarine is not blood he can see.
func test_a_hidden_enemy_is_not_counted() -> void:
	var state := _state("[terrain]\nSSSSSS\n[units]\n1 c 0 0\n2 s 5 0")
	assert_true(state.commander_of(1).wants_power(state, 1), "surfaced, it is worth bleeding")
	state.units[1].dived = true
	assert_false(state.commander_of(1).wants_power(state, 1))
