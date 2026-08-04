extends GutTest
## The analyser's end-of-turn detectors, one board apiece. The per-command ones and
## the report itself are test_replay_detectors.gd — the seam this file's section
## comments already drew, split when the one file crossed the gdlintrc
## max-public-methods ceiling. Both carry their own copy of the fixture helpers,
## the same as the four save-codec suites.
##
## Each case stands exactly the units its detector is about and hands the walk a
## recording made by hand, so a finding here can only come from the thing the test
## is named after. A detector with no fixture is a detector nobody can trust: the
## whole instrument's value is that a report says something true about the match,
## and a false positive costs more than a miss — it sends the reader looking at a
## doctrine that was playing correctly.
##
## The board is a file rather than an inline one because a replay stores its
## opening as a save envelope, which names its map by path.

const BOARD := "res://maps/fixtures/analysis.txt"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


## The fixture board with no units on it, ready for a test to stand its own.
func _bare_state() -> GameState:
	var map := MapData.load_from_file(BOARD, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = BOARD
	state.units.clear()
	return state


func _stand(state: GameState, id: StringName, team: int, cell: Vector2i) -> Unit:
	var unit := Unit.create(unit_db.by_id(id), team, cell)
	state.units.append(unit)
	return unit


## A recording of `entries` played from `state`. No checkpoints: a hand-made
## fixture is not describing a board some other build produced, and `drift` takes
## a line with none on trust for exactly that reason.
func _replay(state: GameState, entries: Array) -> ReplayCodec.Replay:
	var replay := ReplayCodec.Replay.new()
	replay.opening = SaveCodec.encode(state, [] as Array[int])
	for entry: Dictionary in entries:
		replay.entries.append(entry)
	return replay


func _run(state: GameState, entries: Array) -> ReplayAnalysis.Report:
	var report := ReplayAnalysis.run(
		_replay(state, entries), terrain_db, unit_db, chart, commander_db
	)
	assert_eq(report.stopped, "", "the fixture recording must re-issue cleanly")
	return report


func _count(report: ReplayAnalysis.Report, kind: String) -> int:
	return int(report.counts().get(kind, 0))


## The first finding of a kind. Asked for by name rather than by index because a
## board that trips one detector usually trips another — a side with a purse has a
## purse whatever else is being tested.
func _first(report: ReplayAnalysis.Report, kind: String) -> ReplayAnalysis.Finding:
	for finding in report.findings:
		if finding.kind == kind:
			return finding
	return null


## `turns` full rounds of both sides doing nothing but ending their turn.
func _idle_rounds(turns: int) -> Array:
	var entries: Array = []
	for i in turns * 2:
		entries.append({"c": "end_turn"})
	return entries


# --- end-of-turn detectors -----------------------------------------------------


func test_hoarding_is_money_left_on_an_idle_factory() -> void:
	var state := _bare_state()
	state.funds[1] = 9000
	# Seat 2 owns nothing it could spend on, so only seat 1 can be reported.
	state.funds[2] = 0
	var report := _run(state, [{"c": "end_turn"}])
	assert_eq(_count(report, "hoarding"), 1)
	assert_string_contains(_first(report, "hoarding").detail, "9000")


## The purse is measured against what this side is actually charged. A doctrine
## that marks production up leaves money on the table that buys nothing, and a
## detector reading the sticker price would send the reader after a build order
## that was already doing the only thing it could.
func test_a_purse_short_of_a_marked_up_price_is_not_hoarding() -> void:
	var short := _bare_state()
	short.set_commander(1, commander_db.by_id(&"konrad_vale"))
	short.funds[1] = 1100
	short.funds[2] = 0
	assert_eq(_count(_run(short, [{"c": "end_turn"}]), "hoarding"), 0)
	var enough := _bare_state()
	enough.set_commander(1, commander_db.by_id(&"konrad_vale"))
	enough.funds[1] = 1200
	enough.funds[2] = 0
	var report := _run(enough, [{"c": "end_turn"}])
	assert_eq(_count(report, "hoarding"), 1)
	assert_string_contains(_first(report, "hoarding").detail, "1200")


func test_a_purse_too_small_for_anything_is_not_hoarding() -> void:
	var state := _bare_state()
	state.funds[1] = 100
	state.funds[2] = 100
	assert_eq(_count(_run(state, [{"c": "end_turn"}]), "hoarding"), 0)


func test_missed_capture_is_ground_a_footsoldier_could_have_stood_on() -> void:
	var state := _bare_state()
	_stand(state, &"infantry", 1, Vector2i(2, 3))  # one step off the neutral city at (2, 2)
	var report := _run(state, [{"c": "end_turn"}])
	assert_eq(_count(report, "missed_capture"), 1)
	assert_string_contains(_first(report, "missed_capture").detail, "(2, 2)")


func test_a_unit_that_did_capture_is_not_reported() -> void:
	var state := _bare_state()
	_stand(state, &"infantry", 1, Vector2i(2, 3))
	var report := _run(state, [{"c": "capture", "path": [[2, 3], [2, 2]]}, {"c": "end_turn"}])
	assert_eq(_count(report, "missed_capture"), 0)


## Three of its owner's turns, not three end-turns: the streak is per side, and a
## detector that counted rounds would report a unit twice as fast as it says.
func test_idle_unit_needs_three_of_its_owners_turns() -> void:
	var state := _bare_state()
	_stand(state, &"infantry", 1, Vector2i(3, 1))
	_stand(state, &"infantry", 2, Vector2i(4, 1))  # in reach, so there is something to do
	assert_eq(_count(_run(state, _idle_rounds(2)), "idle_unit"), 0, "two turns is patience")
	# Two, one per side: each infantry has the other in reach, so both are idle and
	# both are reported. What the case is about is the third turn, not the count.
	assert_eq(_count(_run(state, _idle_rounds(3)), "idle_unit"), 2, "three is nobody playing")


func test_a_unit_with_nothing_in_reach_is_not_idle() -> void:
	var state := _bare_state()
	# A lone tank: it cannot capture, and there is no enemy anywhere to shoot.
	_stand(state, &"tank", 1, Vector2i(4, 1))
	assert_eq(_count(_run(state, _idle_rounds(4)), "idle_unit"), 0)


func test_banked_power_counts_a_full_meter_nobody_fires() -> void:
	var state := _bare_state()
	var db := CommanderDB.load_default()
	state.set_commander(1, db.by_id(&"alina_ward"))
	var co_state := state.commander_state(1)
	co_state.charge = co_state.type.power_cost
	assert_true(co_state.is_ready(), "the fixture must actually hold a charged power")
	assert_eq(_count(_run(state, _idle_rounds(2)), "banked_power"), 0)
	assert_eq(_count(_run(state, _idle_rounds(3)), "banked_power"), 1)


func test_a_power_that_goes_off_resets_the_count() -> void:
	var state := _bare_state()
	var db := CommanderDB.load_default()
	state.set_commander(1, db.by_id(&"alina_ward"))
	state.commander_state(1).charge = state.commander_state(1).type.power_cost
	var entries: Array = [{"c": "power", "target": [0, 0]}, {"c": "end_turn"}]
	entries.append_array(_idle_rounds(2))
	assert_eq(_count(_run(state, entries), "banked_power"), 0)


func test_stranded_transport_is_cargo_nobody_puts_down() -> void:
	var state := _bare_state()
	var apc := _stand(state, &"apc", 1, Vector2i(4, 1))
	var rider := _stand(state, &"infantry", 1, Vector2i(4, 1))
	rider.carrier = apc
	assert_eq(_count(_run(state, _idle_rounds(2)), "stranded_transport"), 0)
	assert_eq(_count(_run(state, _idle_rounds(3)), "stranded_transport"), 1)


func test_an_empty_transport_is_not_stranded() -> void:
	var state := _bare_state()
	_stand(state, &"apc", 1, Vector2i(4, 1))
	assert_eq(_count(_run(state, _idle_rounds(4)), "stranded_transport"), 0)


func test_undefended_hq_is_an_enemy_in_reach_of_home_with_no_answer() -> void:
	var state := _bare_state()
	# Seat 2's infantry a step from seat 1's home HQ at (0, 0); seat 1 has nothing
	# anywhere near it.
	_stand(state, &"infantry", 2, Vector2i(1, 1))
	_stand(state, &"infantry", 1, Vector2i(7, 1))
	var report := _run(state, [{"c": "end_turn"}])
	assert_eq(_count(report, "undefended_hq"), 1)
	assert_string_contains(_first(report, "undefended_hq").detail, "(0, 0)")


func test_an_hq_something_can_get_back_to_is_not_undefended() -> void:
	var state := _bare_state()
	_stand(state, &"infantry", 2, Vector2i(1, 1))
	_stand(state, &"infantry", 1, Vector2i(0, 1))  # standing on the doorstep
	assert_eq(_count(_run(state, [{"c": "end_turn"}]), "undefended_hq"), 0)
