extends GutTest
## The analyser's end-of-turn detectors, one board apiece. The per-command ones and
## the report itself are test_replay_detectors.gd — the seam this file's section
## comments already drew, split when the one file crossed the gdlintrc
## max-public-methods ceiling. `missed_capture` is test_replay_capture_chance.gd,
## split off the same ceiling once it grew a family of cases. All three carry their
## own copy of the fixture helpers, the same as the four save-codec suites.
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
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


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


## Every finding of a kind one side earned. A streak detector counts per side, and
## a board with two purses on it has two of them.
func _for_team(report: ReplayAnalysis.Report, kind: String, team: int) -> Array:
	var found: Array = []
	for finding in report.findings:
		if finding.kind == kind and finding.team == team:
			found.append(finding)
	return found


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


## One streak, one finding. Said every turn it was more than half of everything
## the analyser printed on a real match, and five copies of one sentence tell the
## reader nothing the first did not.
##
## Seat 2 is counted separately and only reported once it has earned its way into
## a purse of its own, which is why every case here reads one side.
func test_a_standing_hoard_is_reported_once_for_the_whole_streak() -> void:
	var state := _bare_state()
	state.funds[1] = 9000
	state.funds[2] = 0
	var report := _run(state, _idle_rounds(5))
	assert_eq(_for_team(report, "hoarding", 1).size(), 1)
	var finding: ReplayAnalysis.Finding = _for_team(report, "hoarding", 1)[0]
	assert_string_contains(finding.detail, "5 turns")
	assert_eq(finding.day, 1, "the finding is about where the streak began")


## Peak funds, not the funds it happened to end on: what the streak cost the side
## is the most it ever had sitting idle. Seat 1's two properties earn every turn,
## so the purse the walk sees only climbs away from the one it opened with.
func test_a_hoard_carries_the_peak_of_the_streak() -> void:
	var state := _bare_state()
	state.funds[1] = 9000
	state.funds[2] = 0
	var finding: ReplayAnalysis.Finding = _for_team(_run(state, _idle_rounds(3)), "hoarding", 1)[0]
	assert_gt(finding.magnitude, 9000, "the fixture must actually grow the purse")
	assert_string_contains(finding.detail, str(finding.magnitude))


## A streak that ends is released there, and a later one is a second finding.
func test_a_hoard_that_ends_and_starts_again_is_reported_twice() -> void:
	var state := _bare_state()
	state.funds[1] = 9000
	state.funds[2] = 0
	var entries: Array = [
		{"c": "end_turn"},  # day 1: the streak opens
		{"c": "end_turn"},
		# A turn the side spent something on is not a hoarding turn: the streak ends.
		{"c": "build", "cell": [1, 0], "unit": "infantry"},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "move", "path": [[1, 0], [2, 0]]},  # off the base, and it is idle again
		{"c": "end_turn"},
		{"c": "end_turn"},
	]
	assert_eq(_for_team(_run(state, entries), "hoarding", 1).size(), 2)


## The case the detector exists for: a growing purse and nothing bought out of it,
## turn after turn. Both numbers the reader needs are in the one line — how long it
## went on and the most that sat there while it did.
func test_a_rich_side_that_buys_nothing_is_the_reported_case() -> void:
	var state := _bare_state()
	state.funds[1] = 13000
	state.funds[2] = 0
	var report := _run(state, _idle_rounds(4))
	assert_eq(_for_team(report, "hoarding", 1).size(), 1)
	var finding: ReplayAnalysis.Finding = _for_team(report, "hoarding", 1)[0]
	assert_string_contains(finding.detail, "4 turns")
	assert_string_contains(finding.detail, str(finding.magnitude))
	assert_gte(finding.magnitude, 13000)


## Spare capacity is not refusal to spend. A side holding more production than it
## can fill every turn always has a free property, so a detector reading "something
## stood idle" reports the sides that were buying hardest — which is what it did on
## every multi-base board it was measured on. Seat 1 buys every turn here and the
## far base is free and affordable throughout.
func test_a_side_that_builds_every_turn_is_not_hoarding() -> void:
	var state := _bare_state()
	state.funds[1] = 50000
	state.funds[2] = 0
	state.set_owner(Vector2i(6, 4), 1)
	var entries: Array = [
		{"c": "build", "cell": [1, 0], "unit": "infantry"},
		{"c": "end_turn"},
		{"c": "end_turn"},
	]
	var walked: Array = [[1, 0]]
	for step in 3:
		walked.append([2 + step, 0])
		entries.append({"c": "move", "path": walked.duplicate()})
		entries.append({"c": "build", "cell": [1, 0], "unit": "infantry"})
		entries.append({"c": "end_turn"})
		entries.append({"c": "end_turn"})
	var report := _run(state, entries)
	assert_eq(_for_team(report, "hoarding", 1).size(), 0)


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


## The heaviest severity in the table, so a standing lapse said every turn would
## fill the printed summary with one sentence. Latched like `banked_power`.
func test_a_standing_undefended_hq_is_reported_once() -> void:
	var state := _bare_state()
	_stand(state, &"infantry", 2, Vector2i(1, 1))
	_stand(state, &"infantry", 1, Vector2i(4, 1))  # too far to answer for either HQ
	assert_eq(_count(_run(state, _idle_rounds(4)), "undefended_hq"), 1)


## Cleared the moment the side can answer for the HQ again, so a second lapse is a
## second finding.
func test_an_hq_covered_and_then_exposed_again_is_reported_twice() -> void:
	var state := _bare_state()
	_stand(state, &"infantry", 2, Vector2i(1, 1))
	_stand(state, &"infantry", 1, Vector2i(3, 1))
	var entries: Array = [
		{"c": "end_turn"},  # exposed: reported
		{"c": "end_turn"},
		{"c": "move", "path": [[3, 1], [2, 1]]},  # back in reach of home
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "move", "path": [[2, 1], [3, 1], [4, 1], [5, 1]]},  # and away again
		{"c": "end_turn"},
	]
	assert_eq(_count(_run(state, entries), "undefended_hq"), 2)
