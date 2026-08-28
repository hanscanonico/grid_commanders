extends GutTest
## Purchase pricing is a single rule shared by commands, AI and presentation.
## Base UnitType costs deliberately remain unchanged everywhere else.


class PriceCommander:
	extends CommanderType

	var pct := 100

	func _init(p_pct: int) -> void:
		pct = p_pct

	func build_cost_pct(_state: GameState, _team: int, _unit_type: UnitType) -> int:
		return pct


var unit_db: UnitDB


func before_each() -> void:
	unit_db = Fixture.unit_db()


func _state(map_text: String, pct: int = 100) -> GameState:
	var state := Fixture.state(map_text)
	state.set_commander(1, PriceCommander.new(pct))
	return state


func test_prices_apply_percentage_round_down_and_floor() -> void:
	var state := _state(Fixture.NEUTRAL_BASE, 83)
	assert_eq(UnitPricing.cost_for(state, 1, unit_db.by_id(&"infantry")), 800)
	assert_eq(UnitPricing.cost_for(state, 1, unit_db.by_id(&"tank")), 5800)
	state.set_commander(1, PriceCommander.new(1))
	assert_eq(UnitPricing.cost_for(state, 1, unit_db.by_id(&"infantry")), 500)


func test_build_command_validates_and_charges_the_authoritative_price() -> void:
	var state := _state(Fixture.OWNED_BASE, 80)
	state.funds[1] = 800
	var command := BuildCommand.new(1, unit_db.by_id(&"infantry"), Vector2i.ZERO)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(command.paid_cost, 800)
	assert_eq(state.funds[1], 0)
	assert_eq(unit_db.by_id(&"infantry").cost, 1000, "strategic value stays at base cost")


func test_ai_affordability_uses_the_authoritative_price() -> void:
	var state := _state("[terrain]\nB....\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 m 3 0", 80)
	for unit in state.units:
		unit.acted = true
	state.funds[1] = 5600
	var command := AIController.new(unit_db, AIProfile.new()).plan_next_command(state)
	assert_true(command is BuildCommand, "the discounted tank should be affordable")
	assert_eq((command as BuildCommand).unit_type.id, &"tank")
	assert_eq(command.validate(state), "")


func test_build_menu_prints_and_disables_against_the_authoritative_price() -> void:
	var state := _state(Fixture.OWNED_BASE, 80)
	state.funds[1] = 799
	var rows := BattleMenus.build_actions(
		state, unit_db, state.map.terrain_at(Vector2i.ZERO), 1, SideIdentity.for_game(state)
	)
	var infantry: Dictionary = rows[0]
	assert_eq(infantry["id"], &"infantry")
	assert_eq(infantry["label"], "Infantry  800")
	assert_true(infantry["disabled"])
