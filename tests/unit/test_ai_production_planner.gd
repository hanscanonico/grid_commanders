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
