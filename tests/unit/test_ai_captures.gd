extends GutTest
## COM-171 · a conquered home HQ must price like the city it now is.
##
## `_consider_captures` used to apply `hq_capture_multiplier` off the terrain id
## alone, so a cell that used to be somebody's HQ before a rival conquered it —
## owned by neither the fallen army nor recorded in `state.home_hq` any longer —
## still scored 3x a city to whoever eyed it next. `_defend_bonus` already asks
## the home-HQ authority for the same question twenty lines up; this pins
## `_consider_captures` asking it too.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var ai: AIController


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	ai = AIController.new(unit_db)


## A live home HQ still outranks a nearer city — the untouched behaviour.
func test_a_live_home_hq_still_outranks_a_nearer_city() -> void:
	var state := Fixture.state("[terrain]\nQC.\n[owners]\n2 0 0\n[units]\n1 i 2 0")
	assert_true(state.home_hq.has(2), "the fixture must actually seat a home HQ to prove anything")
	var command := ai.plan_next_command(state)
	assert_true(command is CaptureCommand, "expected a capture, got %s" % command)
	var path: Array[Vector2i] = (command as CaptureCommand).path
	assert_eq(path[path.size() - 1], Vector2i(0, 0), "a live home HQ still outbids the closer city")


## The same board, the HQ already conquered once — `state.home_hq` no longer
## names it, exactly as it stands once an army has fallen (`CaptureCommand`'s
## own comment: "an unowned HQ has no army behind it to fall"). It must now
## score like the plain city sitting one tile closer.
func test_a_conquered_home_hq_scores_as_a_plain_city() -> void:
	var state := Fixture.state("[terrain]\nQC.\n[owners]\n2 0 0\n[units]\n1 i 2 0")
	state.home_hq.erase(2)
	var command := ai.plan_next_command(state)
	assert_true(command is CaptureCommand, "expected a capture, got %s" % command)
	var path: Array[Vector2i] = (command as CaptureCommand).path
	assert_eq(
		path[path.size() - 1],
		Vector2i(1, 0),
		"with no home HQ recorded for it, the nearer plain city outbids it"
	)
