extends GutTest
## The analyser's `abandoned_capture` detector: a property started and then walked
## away from.
##
## Nothing carries a capture across turns, so the mistake is structurally
## available to every planner and nothing else in the instrument measures it. What
## the cases here are mostly about is the detector staying quiet — a unit that
## finished, one that died on the cell and one that broke off to fight all look
## alike from a board diff, and a false positive costs more than a miss.
##
## Its own suite rather than a case in test_replay_analysis.gd, which sits at the
## gdlintrc max-public-methods ceiling; the fixture helpers are duplicated across
## the replay suites rather than hoisted, as they already are in three of them.

const BOARD := "res://maps/fixtures/analysis.txt"
## The neutral city at the centre of every case, one step off the unit's opening
## cell.
const CITY := Vector2i(2, 2)

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


func _run(state: GameState, entries: Array) -> ReplayAnalysis.Report:
	var replay := ReplayCodec.Replay.new()
	replay.opening = SaveCodec.encode(state, [] as Array[int])
	for entry: Dictionary in entries:
		replay.entries.append(entry)
	var report := ReplayAnalysis.run(replay, terrain_db, unit_db, chart, commander_db)
	assert_eq(report.stopped, "", "the fixture recording must re-issue cleanly")
	return report


func _count(report: ReplayAnalysis.Report, kind: String) -> int:
	return int(report.counts().get(kind, 0))


func _first(report: ReplayAnalysis.Report, kind: String) -> ReplayAnalysis.Finding:
	for finding in report.findings:
		if finding.kind == kind:
			return finding
	return null


## A full-HP footsoldier one step off the neutral city, which its capture takes
## exactly half of.
func _capturer(state: GameState) -> Unit:
	return _stand(state, &"infantry", 1, Vector2i(2, 3))


func test_a_started_capture_the_unit_walks_off_is_reported() -> void:
	var state := _bare_state()
	_capturer(state)
	var entries: Array = [
		{"c": "capture", "path": [[2, 3], [2, 2]]},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "move", "path": [[2, 2], [3, 2]]},
		{"c": "end_turn"},
	]
	var report := _run(state, entries)
	assert_eq(_count(report, "abandoned_capture"), 1)
	var finding := _first(report, "abandoned_capture")
	assert_string_contains(finding.detail, "(2, 2)")
	assert_eq(finding.magnitude, 10, "half a 20-point city, at a full-HP footsoldier's strength")


## The turn the capture started on is not the turn it could be abandoned on, and
## the unit standing on its own unfinished work is doing exactly the right thing.
func test_a_capture_still_being_worked_is_not_reported() -> void:
	var state := _bare_state()
	_capturer(state)
	var entries: Array = [
		{"c": "capture", "path": [[2, 3], [2, 2]]},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "end_turn"},
	]
	assert_eq(_count(_run(state, entries), "abandoned_capture"), 0)


func test_a_capture_the_unit_finishes_is_not_reported() -> void:
	var state := _bare_state()
	_capturer(state)
	var entries: Array = [
		{"c": "capture", "path": [[2, 3], [2, 2]]},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "capture", "path": [[2, 2]]},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "move", "path": [[2, 2], [3, 2]]},
		{"c": "end_turn"},
	]
	assert_eq(_count(_run(state, entries), "abandoned_capture"), 0)


## A unit killed on the cell left nothing on the table it could have picked up,
## and the board diff between the two boundaries cannot tell the two apart on its
## own.
func test_a_capturer_killed_on_the_cell_is_not_reported() -> void:
	var state := _bare_state()
	var prey := _capturer(state)
	prey.hp = 1
	var tank := _stand(state, &"tank", 2, Vector2i(2, 1))
	_stand(state, &"infantry", 1, Vector2i(0, 4))  # so the kill does not end the match
	# The recording is re-issued against a rebuilt board, so the kill is checked
	# here as a forecast rather than read off the state this test holds.
	var shot := CombatResolver.forecast_at(state, tank, Vector2i(2, 1), prey, CITY)
	assert_true(shot.attack_damage >= prey.hp, "the tank has to actually kill the capturer")
	var entries: Array = [
		{"c": "capture", "path": [[2, 3], [2, 2]]},
		{"c": "end_turn"},
		{"c": "attack", "path": [[2, 1]], "target": [2, 2]},
		{"c": "end_turn"},
		{"c": "end_turn"},
	]
	assert_eq(_count(_run(state, entries), "abandoned_capture"), 0)


## The trade guard the sibling detectors take: a unit that broke off the capture
## to take a shot made an exchange this instrument cannot price.
func test_a_capturer_that_fought_instead_is_not_reported() -> void:
	var state := _bare_state()
	_capturer(state)
	_stand(state, &"infantry", 2, Vector2i(4, 2))
	var entries: Array = [
		{"c": "capture", "path": [[2, 3], [2, 2]]},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "attack", "path": [[2, 2], [3, 2]], "target": [4, 2]},
		{"c": "end_turn"},
	]
	assert_eq(_count(_run(state, entries), "abandoned_capture"), 0)


## A sibling taking the ground over does not excuse the walk-off, and this is why:
## the board forgets the points the moment the first unit steps off, so the
## sibling starts the property from twenty and the first unit's half really was
## thrown away.
func test_a_sibling_restarting_the_property_is_still_an_abandonment() -> void:
	var state := _bare_state()
	_capturer(state)
	_stand(state, &"infantry", 1, Vector2i(2, 1))
	var entries: Array = [
		{"c": "capture", "path": [[2, 3], [2, 2]]},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "move", "path": [[2, 2], [3, 2]]},
		{"c": "capture", "path": [[2, 1], [2, 2]]},
		{"c": "end_turn"},
	]
	assert_eq(_count(_run(state, entries), "abandoned_capture"), 1)
