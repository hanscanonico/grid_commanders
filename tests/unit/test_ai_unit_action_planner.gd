extends GutTest
## A named, discoverable home for AIUnitActionPlanner regressions found by
## constructing the planner directly, the way test_dive.gd:335 and
## test_ai_smarts.gd:395 already do, rather than only through AIController.
##
## Deliberately thin: the planner's behaviour is pinned in depth across
## test_ai_smarts.gd, test_ai_captures.gd, test_ai_join.gd, test_ai_withdrawal.gd
## and the rest of the AI capability suites. This file exists so a bug found by
## constructing AIUnitActionPlanner and AIPlanningContext directly has a home a
## grep for its class name finds, not to duplicate that coverage.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _context(map_text: String) -> AIPlanningContext:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	var context := AIPlanningContext.new(unit_db)
	context.begin(state)
	return context


## The direct-construction seam future regressions extend: a typed AIUnitPlan,
## scored, carrying a legal command — on the trivial board a tank standing next
## to an infantry it can simply shoot.
func test_best_unit_plan_returns_a_typed_plan_with_a_command() -> void:
	var context := _context("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	var planner := AIUnitActionPlanner.new(AIProfile.new())
	var unit := context.friendly_units[0]
	var plan := planner._best_unit_plan(context, unit)
	assert_true(plan is AIUnitPlan)
	assert_true(plan.command is AttackCommand, "the tank's only useful move is to fire")
	assert_gt(plan.score, -INF)
	assert_eq(plan.command.validate(context.state), "")


## The planner's own public entry, `plan_next`, called on a context built the
## same way — the seam AIController delegates to rather than a duplicate of it.
func test_plan_next_returns_the_best_scored_command() -> void:
	var context := _context("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	var planner := AIUnitActionPlanner.new(AIProfile.new())
	var command := planner.plan_next(context)
	assert_true(command is AttackCommand)
	assert_eq(command.validate(context.state), "")
