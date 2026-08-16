extends GutTest
## Which line the Fire key is answered with when the Command Power cannot go off.
## Pure and Node-free, so every refusal is read without booting the battle scene
## (the same terms BattleLegend and ReadyUnits are tested on).

const NO_SEATS: Array[int] = []


func _state() -> GameState:
	return Fixture.state("[terrain]\n...\n...\n[units]\n1 t 0 0\n2 i 2 0")


func _seated() -> GameState:
	var game := _state()
	game.set_commander(1, Fixture.commander_db().by_id(&"rhea_sol"))
	return game


func test_a_neutral_commander_has_no_power_to_fire() -> void:
	assert_eq(BattlePower.NO_POWER, BattlePower.refusal_for(_state(), NO_SEATS))


func test_a_meter_still_filling_names_its_own_numbers() -> void:
	var game := _seated()
	var cost := game.commander_of(1).power_cost
	game.add_charge(1, cost / 2)
	assert_eq(BattlePower.CHARGING % [cost / 2, cost], BattlePower.refusal_for(game, NO_SEATS))


func test_a_full_meter_may_fire() -> void:
	var game := _seated()
	game.add_charge(1, game.commander_of(1).power_cost)
	assert_eq("", BattlePower.refusal_for(game, NO_SEATS))


func test_a_running_power_is_not_fired_twice() -> void:
	var game := _seated()
	assert_eq("", Fixture.fire_power(game, 1))
	assert_eq(BattlePower.RUNNING, BattlePower.refusal_for(game, NO_SEATS))


## The one refusal PowerCommand cannot make: it does not know who is at the
## keyboard, so the seat is asked before the meter.
func test_a_computer_seat_answers_before_the_meter() -> void:
	var game := _seated()
	game.add_charge(1, game.commander_of(1).power_cost)
	assert_eq(BattlePower.AI_SEAT, BattlePower.refusal_for(game, [1] as Array[int]))
	assert_eq("", BattlePower.refusal_for(game, [2] as Array[int]))
