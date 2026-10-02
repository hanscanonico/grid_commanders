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

## test_dive.gd's OPEN_CHANNEL: a pocket wide enough to leave the battleship's
## ring, the sub at its far edge and one step west out of the guns. No property
## on it, so the dive is the only branch that can build the threat map at all.
const OPEN_CHANNEL := "[terrain]\nSSSSSSSS.SSSSSS\n[units]\n1 s 6 0\n2 B 12 0"

## Every tier a seat can be given, Brutal included.
const SHIPPED_TIERS: Array[String] = [
	"res://data/ai/easy.tres",
	"res://data/ai/default.tres",
	"res://data/ai/hard.tres",
	"res://data/ai/brutal.tres",
]

## TANK_VS_INFANTRY with a second enemy infantry across water the tank cannot
## cross, so killing the first one does not end the match.
const ONE_HP_NOT_LAST := "[terrain]\n..SS.\n[units]\n1 t 0 0\n2 i 1 0\n2 i 4 0"

## Our infantry between a neutral city and the enemy's infantry: capture or kill.
const KILL_OR_CAPTURE := "[terrain]\nC..SS.\n[units]\n1 i 1 0\n2 i 2 0"

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


## The direct-construction seam future regressions extend: a typed AIUnitPlan,
## scored, carrying a legal command — on the trivial board a tank standing next
## to an infantry it can simply shoot.
func test_best_unit_plan_returns_a_typed_plan_with_a_command() -> void:
	var context := _context(Fixture.TANK_VS_INFANTRY)
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
	var context := _context(Fixture.TANK_VS_INFANTRY)
	var planner := AIUnitActionPlanner.new(AIProfile.new())
	var command := planner.plan_next(context)
	assert_true(command is AttackCommand)
	assert_eq(command.validate(context.state), "")


## AIProfile.builds_threat_map is one authority for a reason: this file's subject
## kept a copy of the list with `capture_threat_aversion` missing from it, so a
## seated dial had _consider_captures build the map while the dive declined to
## read it — and the boat went under where it stood. Inert rather than absent,
## the dial being 0.0 on every shipped tier.
func test_a_lone_capture_threat_dial_pays_for_the_dive_s_map() -> void:
	var profile := AIProfile.new()
	profile.capture_threat_aversion = 1.0
	var context := _context(OPEN_CHANNEL)
	var command := AIUnitActionPlanner.new(profile).plan_next(context)
	assert_true(command is DiveCommand, "expected a dive, got %s" % command)
	assert_true(context.threat_map_built(), "the live dial pays for the refuge's ranking")
	if not (command is DiveCommand):
		return
	assert_eq(
		(command as DiveCommand).path,
		Fixture.path([Vector2i(6, 0), Vector2i(5, 0)]),
		"so the boat goes under out of the battleship's ring, not where it stood"
	)


## SK-06: the enemy's last unit, one HP from dead, beside our tank. Priced on the
## single HP the shot removes the kill was worth 16 against a min_useful_score of
## 40, so every tier walked past the shot that wins the match by rout.
func test_every_tier_takes_the_kill_that_wins_the_match() -> void:
	for path in SHIPPED_TIERS:
		var context := _context(Fixture.TANK_VS_INFANTRY)
		context.state.units_of(2)[0].hp = Unit.MIN_HP
		var command := AIUnitActionPlanner.new(load(path)).plan_next(context)
		assert_true(command is AttackCommand, "%s let the last unit live: %s" % [path, command])
		if command is AttackCommand:
			assert_eq((command as AttackCommand).target_cell, Vector2i(1, 0))


## The same 1-HP infantry when it is not the last of its army: still a unit that
## fights and captures as a full pip, so still a shot worth taking.
func test_a_one_hp_unit_is_still_worth_killing() -> void:
	for path in SHIPPED_TIERS:
		var context := _context(ONE_HP_NOT_LAST)
		context.state.unit_at(Vector2i(1, 0)).hp = Unit.MIN_HP
		var command := AIUnitActionPlanner.new(load(path)).plan_next(context)
		assert_true(command is AttackCommand, "%s ignored the 1-HP unit: %s" % [path, command])


## Winning outranks everything else a unit could do: the infantry beside a
## neutral city finishes the enemy's last unit rather than starting the capture.
## Give the enemy a second unit out of reach and the capture is worth more again.
func test_the_winning_kill_outranks_a_capture() -> void:
	var profile := AIProfile.load_default()
	var context := _context(KILL_OR_CAPTURE)
	context.state.unit_at(Vector2i(2, 0)).hp = Unit.MIN_HP
	var command := AIUnitActionPlanner.new(profile).plan_next(context)
	assert_true(command is AttackCommand, "expected the winning kill, got %s" % command)

	var spared := _context(KILL_OR_CAPTURE + "\n2 i 5 0")
	spared.state.unit_at(Vector2i(2, 0)).hp = Unit.MIN_HP
	var other := AIUnitActionPlanner.new(profile).plan_next(spared)
	assert_true(other is CaptureCommand, "only the match-ending kill is priced past it: %s" % other)
