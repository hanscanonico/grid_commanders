extends GutTest
## Ines Calder: the full price curve, the standing attack tax and the active
## swing Weight of Numbers promises.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


func _state() -> GameState:
	return Fixture.state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0", {1: &"ines_calder"})


func _fight(state: GameState) -> Engagement:
	return Engagement.create(state.units[0], Vector2i.ZERO, 10, state.units[1], Vector2i(1, 0), 10)


func test_discount_reaches_both_ends_of_the_roster() -> void:
	var state := _state()
	assert_eq(UnitPricing.cost_for(state, 1, unit_db.by_id(&"infantry")), 900)
	assert_eq(UnitPricing.cost_for(state, 1, unit_db.by_id(&"battleship")), 25200)


func test_weight_of_numbers_is_a_twenty_five_point_swing() -> void:
	var state := _state()
	var co := state.commander_of(1)
	assert_eq(co.attack_bonus(state, _fight(state)), -10)
	state.add_charge(1, co.power_cost)
	PowerCommand.new().apply(state)
	assert_eq(co.attack_bonus(state, _fight(state)), 15)


func test_production_advice_prefers_cheap_units() -> void:
	var state := _state()
	var co := state.commander_of(1)
	assert_lt(co.build_bias(state, 1, unit_db.by_id(&"infantry")), 0)
	assert_eq(co.build_bias(state, 1, unit_db.by_id(&"tank")), 0)
	assert_lt(
		co.build_bias(state, 1, unit_db.by_id(&"recon")),
		0,
		"her ceiling is a price, so it reaches every cheap type and not a named list"
	)


## A funded base whose capture roster is already filled, with one mech fielded so
## the second copy's duplicate cost is in play — the board her cheap-breadth bias
## is read on.
const CHEAP_BREADTH_BOARD := """
[terrain]
B....
.....
[owners]
1 0 0
[units]
1 i 1 0
1 i 2 0
1 i 3 0
1 m 0 1
2 i 4 1
"""


func _build_as(commander_id: StringName, funds: int) -> Command:
	var state := Fixture.state(CHEAP_BREADTH_BOARD)
	if commander_id != CommanderType.NEUTRAL_ID:
		state.set_commander(1, commander_db.by_id(commander_id))
	for unit in state.units:
		unit.acted = true
	state.funds[1] = funds
	return AIController.new(unit_db).plan_next_command(state)


func _built_id(command: Command) -> StringName:
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	return (command as BuildCommand).unit_type.id


## Four thousand in the bank is where her bias reaches the recon: unlisted on
## build_priority, it takes _build_rank's doctrine-tail branch at 2009 while the
## second mech sits at 2010. The neutral commander banks the same board.
##
## She is the third commander to field a scout and the only one who does not name
## one — a consequence of pricing her bias by a ceiling rather than by a list.
## Kept deliberately: the narrowed bias was built and measured against this one
## and lost (docs/commander_balance.md, 2026-08-16), and AIProfile.build_priority
## says so where it explains the mechanism.
func test_four_thousand_buys_calder_a_recon() -> void:
	assert_eq(_built_id(_build_as(&"ines_calder", 4000)), &"recon")
	assert_true(
		_build_as(CommanderType.NEUTRAL_ID, 4000) is EndTurnCommand,
		"the neutral commander banks four thousand"
	)
