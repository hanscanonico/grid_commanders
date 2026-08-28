extends GutTest
## Mara Voss, and with her the is_counter flag and the ROUND power duration.


func _state(map_text: String) -> GameState:
	return Fixture.state(map_text, {1: &"mara_voss"})


# --- the doctrine ------------------------------------------------------------


## Her Tank MG opening on Infantry: 75 * 0.9 * 0.9 = 60.75 -> 61, against 68.
func test_initiating_hits_softer() -> void:
	var state := _state(Fixture.TANK_VS_INFANTRY)
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		61
	)


## The same units the other way round: the enemy Tank opens, and her Infantry's
## counter carries the bonus. Infantry vs Tank base 5, defender at 8 displayed
## after the hit: 5 * 1.2 * 0.8 * 0.9 = 4.32 -> 4, against 5 * 0.8 * 0.9 = 3.6
## -> 4. Read the hook directly, since rounding hides it at this base damage.
func test_countering_hits_harder() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0")
	var fight := Engagement.create(
		state.units[0], Vector2i(0, 0), 10, state.units[1], Vector2i(1, 0), 10, true
	)
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 20, "countering")
	fight.is_counter = false
	assert_eq(state.commander_of(1).attack_bonus(state, fight), -10, "initiating")


## Indirect units never counter, so neither half of the doctrine reaches them.
func test_indirect_units_are_untouched() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 g 0 0\n2 i 2 0")
	var fight := Engagement.create(
		state.units[0], Vector2i(0, 0), 10, state.units[1], Vector2i(2, 0), 10
	)
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 0)


# --- Hold the Line -----------------------------------------------------------


## The whole point of a ROUND power: it has to still be up while the opponent
## plays, since that is the turn it defends against.
func test_the_power_covers_the_opponents_turn() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0")
	assert_eq(Fixture.fire_power(state, 1), "")
	EndTurnCommand.new().apply(state)
	assert_true(state.power_active(1), "still up on blue's turn")
	# Blue's Tank MG into her defended Infantry: 75 * (200 - 130)/100 * 0.9
	# = 75 * 0.7 * 0.9 = 47.25 -> 47, against 68 undefended.
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[1], Vector2i(1, 0), state.units[0])
			. attack_damage
		),
		47
	)
	EndTurnCommand.new().apply(state)
	assert_false(state.power_active(1), "and down as her next turn opens")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[1], Vector2i(1, 0), state.units[0])
			. attack_damage
		),
		68
	)


func test_the_power_stacks_onto_the_counter_bonus() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0")
	assert_eq(Fixture.fire_power(state, 1), "")
	var fight := Engagement.create(
		state.units[0], Vector2i(0, 0), 10, state.units[1], Vector2i(1, 0), 10, true
	)
	assert_eq(
		state.commander_of(1).attack_bonus(state, fight), 60, "20 passive + 40 from the power"
	)


# --- ground advice -----------------------------------------------------------


## Cover is only advice while somebody can actually come to her.
func test_stand_advice_wants_stars_only_under_threat() -> void:
	var state := _state("[terrain]\n.F=.......\n[units]\n1 t 0 0\n2 t 6 0")
	var co := state.commander_of(1)
	var tank := state.units[0]
	assert_eq(co.stand_value(state, tank, Vector2i(1, 0)), 2, "woods are two stars")
	assert_eq(co.stand_value(state, tank, Vector2i(2, 0)), 0, "a road holds nothing")


func test_stand_advice_is_quiet_out_of_contact() -> void:
	var line := ".F" + ".".repeat(18)
	var state := _state("[terrain]\n%s\n[units]\n1 t 0 0\n2 t 19 0" % line)
	assert_eq(state.commander_of(1).stand_value(state, state.units[0], Vector2i(1, 0)), 0)


## The reach behind the advice is memoised per scan, so the pin is that a later
## turn re-asks it: a tank out of fuel walks nowhere and stops being a threat.
func test_stand_advice_re_reads_reach_on_a_later_turn() -> void:
	var state := _state("[terrain]\n.F=.......\n[units]\n1 t 0 0\n2 t 6 0")
	var co := state.commander_of(1)
	assert_eq(co.stand_value(state, state.units[0], Vector2i(1, 0)), 2, "in contact")
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	state.units[1].fuel = 0
	assert_eq(co.stand_value(state, state.units[0], Vector2i(1, 0)), 0, "stranded")


## Indirect units sit the advice out, like both halves of her combat doctrine.
func test_stand_advice_sits_out_for_indirect_units() -> void:
	var state := _state("[terrain]\n.F........\n[units]\n1 g 0 0\n2 t 6 0")
	assert_eq(state.commander_of(1).stand_value(state, state.units[0], Vector2i(1, 0)), 0)
