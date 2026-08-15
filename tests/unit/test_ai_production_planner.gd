extends GutTest
## A named, discoverable home for AIProductionPlanner regressions found by
## constructing the planner directly, the way test_ai_production.gd:451 already
## calls `_build_rank` on one.
##
## Deliberately thin: what the AI buys and why is pinned in depth across
## test_ai_production.gd. This file exists so a bug found by constructing
## AIProductionPlanner and AIPlanningContext directly has a home a grep for its
## class name finds, not to duplicate that coverage.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


func _context(map_text: String) -> AIPlanningContext:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	var context := AIPlanningContext.new(unit_db)
	context.begin(state)
	return context


## The direct-construction seam future regressions extend: `plan()` returns a
## typed BuildCommand off a base the team owns, funded by the day's own income.
func test_plan_returns_a_build_command_with_funds_and_a_base() -> void:
	var context := _context("[terrain]\nB.\n[owners]\n1 0 0\n[units]\n1 i 1 0")
	var planner := AIProductionPlanner.new(AIProfile.new())
	var command := planner.plan(context)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	assert_eq(command.validate(context.state), "")
	assert_eq((command as BuildCommand).cell, Vector2i(0, 0))


## With the capture roster already full, the same base spends its funds on the
## more expensive unit the standing priority list favours instead.
func test_plan_prefers_a_costlier_unit_once_the_roster_is_full() -> void:
	var context := _context("[terrain]\nB....\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 m 3 0")
	context.state.funds[context.team] = 7000
	var planner := AIProductionPlanner.new(AIProfile.new())
	var command := planner.plan(context)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	assert_eq((command as BuildCommand).unit_type.id, &"tank")


# --- duplicate_priority_cost: the dial that stops one unit type forever -------

## Two empty bases and a full capture roster, so the planner buys twice off the
## standing list with nothing else competing for either facility.
const TWO_BASE_BOARD := """
[terrain]
BB...
.....
[owners]
1 0 0
1 1 0
[units]
1 i 0 1
1 i 1 1
1 i 2 1
"""


## The list the two-base board is bought against: a tank the planner prefers and
## a mech only a duplicate charge can ever reach.
func _two_entry_profile(duplicate_cost: int) -> AIProfile:
	var profile := AIProfile.new()
	profile.build_priority = ([&"tank", &"mech"] as Array[StringName])
	profile.duplicate_priority_cost = duplicate_cost
	return profile


## What the planner buys at each of two bases in turn, the first purchase
## standing on the board when the second is planned.
func _two_builds(duplicate_cost: int) -> Array[StringName]:
	var context := _context(TWO_BASE_BOARD)
	context.state.funds[context.team] = 20000
	var planner := AIProductionPlanner.new(_two_entry_profile(duplicate_cost))
	var bought: Array[StringName] = []
	for i in 2:
		var command := planner.plan(context)
		assert_true(command is BuildCommand, "expected a build, got %s" % command)
		if not (command is BuildCommand):
			break
		var build := command as BuildCommand
		assert_eq(build.validate(context.state), "")
		build.apply(context.state)
		bought.append(build.unit_type.id)
		context.begin(context.state)
	return bought


## The whole point of the dial: at its shipped charge the second purchase moves
## down the list, and at zero the army buys the list's one winner forever.
func test_duplicates_push_the_next_purchase_down_the_list() -> void:
	assert_eq(
		_two_builds(3),
		[&"tank", &"mech"] as Array[StringName],
		"one tank fielded should push the list's tail ahead of a second"
	)
	assert_eq(
		_two_builds(0),
		[&"tank", &"tank"] as Array[StringName],
		"with no duplicate charge the list has exactly one winner"
	)


## The arithmetic behind it: each copy already fielded costs exactly one dial's
## worth of places, so a tuned value means what the field's comment says.
func test_each_copy_owned_costs_exactly_duplicate_priority_cost_places() -> void:
	var tank: UnitType = unit_db.by_id(&"tank")
	var profile := _two_entry_profile(4)
	var planner := AIProductionPlanner.new(profile)
	for owned in 3:
		var wants := AIProductionPlanner.BuildWants.new()
		wants.owned = {&"tank": owned} as Dictionary[StringName, int]
		assert_eq(
			planner._build_rank(tank, wants),
			AIProductionPlanner.RANK_PRIORITY + 4 * owned,
			"the list's first entry with %d already fielded" % owned
		)


# --- _worth_waiting_for: the three branches of the banking rule ---------------

## A base, five owned properties for income, and a capture roster already full.
## Funds of 7000 buy the list's tank today; two turns of that income reach the
## md tank the list prefers.
const BANKING_BOARD := """
[terrain]
BCCCC
.....
[owners]
1 0 0
1 1 0
1 2 0
1 3 0
1 4 0
[units]
1 i 0 1
1 i 1 1
1 i 2 1
"""


func _banking_profile(save_up_turns: int) -> AIProfile:
	var profile := AIProfile.new()
	profile.build_priority = ([&"md_tank", &"tank"] as Array[StringName])
	profile.save_up_turns = save_up_turns
	return profile


func _banking_plan(save_up_turns: int) -> Command:
	var context := _context(BANKING_BOARD)
	context.state.funds[context.team] = 7000
	assert_eq(TurnRules.income_for(context.state, context.team), 5000, "the board's income")
	return AIProductionPlanner.new(_banking_profile(save_up_turns)).plan(context)


## Zero is the documented "spend it all" setting, and it is an early return
## rather than a budget that happens to reach nothing.
func test_no_banking_spends_the_treasury_today() -> void:
	var command := _banking_plan(0)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	assert_eq((command as BuildCommand).unit_type.id, &"tank")


## The budget itself: 7000 buys a tank now, and 7000 plus two turns of 5000
## reaches the 16000 md tank the list ranks above it, so the planner waits.
func test_a_better_unit_inside_the_banked_budget_holds_the_purchase() -> void:
	assert_null(_banking_plan(2), "the md tank is two turns of income away and outranks the tank")


## The same board and the same wait, with the sky urgent. Only the ordering of
## air_answer_ids differs from the pair above: the affordable answer ranks below
## the one two turns away, so the budget test would bank — and the guard is what
## says an urgent tier never does.
const OUTGUNNED_BOARD := """
[terrain]
BACCC
C....
[owners]
1 0 0
1 1 0
1 2 0
1 3 0
1 4 0
1 0 1
[units]
1 i 1 1
1 i 2 1
1 i 3 1
2 b 4 1
"""


func _outgunned_plan(air_answer_ids: Array[StringName]) -> Command:
	var context := _context(OUTGUNNED_BOARD)
	context.state.funds[context.team] = 8000
	assert_eq(TurnRules.income_for(context.state, context.team), 6000, "the board's income")
	var profile := _banking_profile(2)
	profile.air_answer_ids = air_answer_ids
	return AIProductionPlanner.new(profile).plan(context)


func test_an_urgent_tier_never_banks() -> void:
	assert_null(
		_outgunned_plan([] as Array[StringName]),
		"with nothing urgent the same board banks for the list's md tank"
	)
	var command := _outgunned_plan([&"fighter", &"anti_air"] as Array[StringName])
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	assert_eq(
		(command as BuildCommand).unit_type.id,
		&"anti_air",
		"the fighter ranks better and fits the banked budget, but bombers do not wait"
	)


# --- the any-capture-unit floor, and where it stops ---------------------------


## Infantry are on no tier's build list, so once the capture roster is full the
## floor under this tier is the only thing that keeps them buyable at all.
func test_a_capture_unit_off_the_list_ranks_at_the_floor() -> void:
	var profile := AIProfile.new()
	profile.build_priority = ([&"md_tank", &"tank", &"mech"] as Array[StringName])
	var planner := AIProductionPlanner.new(profile)
	var full_roster := AIProductionPlanner.BuildWants.new()
	var floor_rank := AIProductionPlanner.TIER_STRIDE * 3

	assert_eq(planner._build_rank(unit_db.by_id(&"infantry"), full_roster), floor_rank)
	for id in profile.build_priority:
		assert_lt(
			planner._build_rank(unit_db.by_id(id), full_roster),
			floor_rank,
			"%s is on the list, so it must outrank a spare capturer" % id
		)
	for id in [&"t_copter", &"lander"]:
		assert_eq(
			planner._build_rank(unit_db.by_id(id), full_roster),
			AIProductionPlanner.RANK_NONE,
			"%s carries no rank at all — the planner cannot plan a ferry" % id
		)
	assert_gt(AIProductionPlanner.RANK_NONE, floor_rank, "a transport loses to a spare capturer")
