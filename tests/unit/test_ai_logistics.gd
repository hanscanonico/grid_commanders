extends GutTest
## The two logistics commands the planner never issued: Join and Supply.
##
## Split out of test_ai_smarts.gd, which sits at the gdlintrc max-public-methods
## ceiling, and because these ask a different question: the smarts suite pins how
## the planner *ranks* candidates it already had, while this one pins that two
## command types the rules have always offered reach the board at all.
##
## Every test is one board reached twice, with the dial off and on. The off runs
## are the inertness pin the standing 0-skips-the-code contract owes; profiles
## are built here rather than loaded, so retuning a shipped tier is a balance
## decision and never a test failure.

## Two tanks at 40 HP with an enemy tank parked well out of reach: nothing to
## shoot, nothing to take, and no property to walk home to. The only thing either
## of them can do that is worth anything is become one tank.
const WOUNDED_PAIR := "[terrain]\n..........\n[units]\n1 t 0 0\n1 t 2 0\n2 t 9 0"

## The same board with an APC beside a tank that has fired itself dry.
const DRY_TANK := "[terrain]\n..........\n[units]\n1 p 0 0\n1 t 1 0\n2 t 9 0"

const LIVE := 0.25

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return state


## Normal's shipped numbers with both logistics dials off, so a test turns on
## exactly the one it is about.
func _profile() -> AIProfile:
	var profile := AIProfile.new()
	profile.join_weight = 0.0
	profile.supply_weight = 0.0
	return profile


func _hurt(state: GameState, hp: int) -> GameState:
	for unit in state.units_of(1):
		unit.hp = hp
	return state


func _dry(state: GameState) -> GameState:
	for unit in state.units_of(1):
		unit.ammo = 0
	return state


func _plan(state: GameState, profile: AIProfile) -> Command:
	return AIController.new(unit_db, profile).plan_next_command(state)


## Every command one whole turn is planned as, so an inertness pin reads the
## turn rather than its first move.
func _plan_a_turn(state: GameState, profile: AIProfile) -> Array[String]:
	var ai := AIController.new(unit_db, profile)
	var log: Array[String] = []
	for i in 40:
		var command := ai.plan_next_command(state)
		log.append(_describe(command))
		command.apply(state)
		if command is EndTurnCommand:
			break
	return log


func _describe(command: Command) -> String:
	if command is JoinCommand:
		return "join %s" % [(command as JoinCommand).path]
	if command is SupplyCommand:
		return "supply %s" % [(command as SupplyCommand).path]
	if command is AttackCommand:
		return "attack %s" % [(command as AttackCommand).target_cell]
	if command is MoveCommand:
		return "move %s" % [(command as MoveCommand).path]
	if command is BuildCommand:
		return "build %s" % [(command as BuildCommand).unit_type.id]
	return "end turn"


# --- Join ---------------------------------------------------------------------


## The acceptance case: on a board whose only value-positive move is a merge, the
## planner merges. Blind it drifts at the enemy instead, two cripples abreast.
func test_a_wounded_pair_merges_when_nothing_better_is_on_the_ballot() -> void:
	var blind := _plan(_hurt(_state(WOUNDED_PAIR), 40), _profile())
	assert_true(blind is MoveCommand, "blind, the pair has nothing to do but advance")

	var profile := _profile()
	profile.join_weight = LIVE
	var state := _hurt(_state(WOUNDED_PAIR), 40)
	var command := _plan(state, profile)
	assert_true(command is JoinCommand, "expected a join, got %s" % _describe(command))
	assert_eq(command.validate(state), "", "the planned join must be legal")
	assert_eq(
		(command as JoinCommand).path,
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i],
		"the first of the two walks onto its twin"
	)


## The inertness pin: at 0 nothing in the capability runs, so the same board is
## played out exactly as it was before the planner had ever heard of joining.
func test_join_at_zero_never_merges_over_a_whole_turn() -> void:
	var turn := _plan_a_turn(_hurt(_state(WOUNDED_PAIR), 40), _profile())
	for line in turn:
		assert_false(line.begins_with("join"), "the dial is off; nothing may merge (%s)" % line)


## The guard that stops the AI merging its army into one super-unit: a join
## spends the unit that walks, so a unit still worth fielding is never the one
## spent. The line is retreat_hp, the same sense of "wounded" the repair errand
## uses, and here the twin standing still is healthy.
func test_a_healthy_twin_is_never_spent_on_a_join() -> void:
	var profile := _profile()
	profile.join_weight = LIVE
	var state := _state(WOUNDED_PAIR)
	state.units_of(1)[0].hp = 40  # the walker is a cripple; its twin is fresh
	var command := _plan(state, profile)
	assert_false(command is JoinCommand, "a full-strength unit is not spare parts")


## HP over the cap is thrown away — JoinCommand caps the merged unit at 100 and
## refunds nothing — so the merge is priced net of the spill. Two units this
## nearly whole have more to lose than to gain and must stay two.
func test_a_merge_that_would_spill_hp_is_refused() -> void:
	var profile := _profile()
	profile.join_weight = LIVE
	profile.retreat_hp = 85  # both twins count as wounded, so only the spill decides
	var command := _plan(_hurt(_state(WOUNDED_PAIR), 80), profile)
	assert_false(command is JoinCommand, "60 of the 80 points carried would evaporate")

	var worthwhile := _plan(_hurt(_state(WOUNDED_PAIR), 50), profile)
	assert_true(worthwhile is JoinCommand, "at 50 each the whole load lands and the merge is on")


# --- Supply -------------------------------------------------------------------


## The acceptance case: an APC beside a tank with an empty rack tops it up
## instead of trailing the army.
func test_an_apc_tops_up_a_dry_tank_instead_of_drifting() -> void:
	var blind := _plan(_dry(_state(DRY_TANK)), _profile())
	assert_true(blind is MoveCommand, "blind, the APC has nothing on its ballot but the advance")

	var profile := _profile()
	profile.supply_weight = LIVE
	var state := _dry(_state(DRY_TANK))
	var command := _plan(state, profile)
	assert_true(command is SupplyCommand, "expected a supply, got %s" % _describe(command))
	assert_eq(command.validate(state), "", "the planned supply must be legal")
	assert_eq(
		(command as SupplyCommand).path,
		[Vector2i(0, 0)] as Array[Vector2i],
		"the tank is already in reach, so the cheapest cell to refill it from is this one"
	)


## The inertness pin, the same shape as the join one above.
func test_supply_at_zero_never_refills_over_a_whole_turn() -> void:
	var turn := _plan_a_turn(_dry(_state(DRY_TANK)), _profile())
	for line in turn:
		assert_false(line.begins_with("supply"), "the dial is off; nothing may refill (%s)" % line)


## Fuel counts through the one authority for running dry — the same question the
## refit errand asks — so a land unit's part-spent tank is not a shortfall. It is
## parked at worst, and topping it up mid-turn buys nothing the start of the next
## turn would not.
func test_a_part_spent_land_tank_is_not_worth_supplying() -> void:
	var profile := _profile()
	profile.supply_weight = LIVE
	var state := _state(DRY_TANK)
	state.units_of(1)[1].fuel = 4  # ammo untouched: fuel alone is on the ballot
	var command := _plan(state, profile)
	assert_false(command is SupplyCommand, "a land unit low on fuel is parked, not stranded")
