extends GutTest
## `spent_power`: a Command Power fired into a board it could not move.
##
## Its own file for the reason `test_replay_detectors.gd` and
## `test_replay_capture_chance.gd` are theirs — `test_replay_analysis.gd` is at
## the gdlintrc max-public-methods ceiling — and it carries its own copy of the
## fixture helpers, the same as the four save-codec suites.
##
## The detector reads the *board*, never the log: a power buys a hit, ground, a
## top-up or a cell out of normal reach, and any one of those and nothing is
## said. Every case below is one of those four, or one of the three exclusions,
## because a false positive here names a doctrine that was playing correctly.

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


## The board with `id` seated on team 1 and their meter full.
func _charged_state(id: StringName) -> GameState:
	var state := _bare_state()
	state.set_commander(1, commander_db.by_id(id))
	var co_state := state.commander_state(1)
	co_state.charge = co_state.type.power_cost
	assert_true(co_state.is_ready(), "the fixture must actually hold a charged power")
	return state


func _stand(state: GameState, id: StringName, team: int, cell: Vector2i) -> Unit:
	var unit := Unit.create(unit_db.by_id(id), team, cell)
	state.units.append(unit)
	return unit


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


func _first(report: ReplayAnalysis.Report, kind: String) -> ReplayAnalysis.Finding:
	for finding in report.findings:
		if finding.kind == kind:
			return finding
	return null


## Fire the meter at (0, 0) and hand the board over, with `entries` in between.
func _power_turn(entries: Array = []) -> Array:
	var log: Array = [{"c": "power", "target": [0, 0]}]
	log.append_array(entries)
	log.append({"c": "end_turn"})
	return log


# --- the reported case ---------------------------------------------------------


## The maximally wasted activation, and the board `banked_power` is deliberately
## silent about: firing zeroes that streak whatever the power achieved, so this
## was the one mistake the instrument could not see.
func test_a_power_fired_into_an_empty_board_is_reported() -> void:
	var report := _run(_charged_state(&"alina_ward"), _power_turn())
	assert_eq(_count(report, "spent_power"), 1)
	assert_eq(_count(report, "banked_power"), 0, "firing still ends the banked streak")
	var finding := _first(report, "spent_power")
	assert_eq(finding.team, 1)
	assert_eq(finding.day, 1)
	assert_string_contains(finding.detail, "Coordinated Push")


# --- the four things a power can buy --------------------------------------------


func test_a_power_followed_by_a_kill_is_not_reported() -> void:
	var state := _charged_state(&"alina_ward")
	_stand(state, &"tank", 1, Vector2i(3, 1))
	_stand(state, &"infantry", 2, Vector2i(2, 1)).hp = 10
	_stand(state, &"infantry", 2, Vector2i(7, 3))  # so the kill does not end the match
	var entries := _power_turn([{"c": "attack", "path": [[3, 1]], "target": [2, 1]}])
	assert_eq(_count(_run(state, entries), "spent_power"), 0)


func test_a_power_followed_by_a_capture_is_not_reported() -> void:
	var state := _charged_state(&"alina_ward")
	_stand(state, &"infantry", 1, Vector2i(2, 3))
	var entries := _power_turn([{"c": "capture", "path": [[2, 3], [2, 2]]}])
	assert_eq(_count(_run(state, entries), "spent_power"), 0)


## Open the Depots buys HP, fuel and ammo and nothing else, so a refit doctrine
## is the case a detector reading hits and ground alone would report every time.
func test_a_power_that_repaired_the_army_is_not_reported() -> void:
	var state := _charged_state(&"gideon_holt")
	_stand(state, &"infantry", 1, Vector2i(3, 1)).hp = 50
	assert_eq(_count(_run(state, _power_turn()), "spent_power"), 0)


## Popular Uprising buys a tile of movement, so the fourth criterion is the only
## one that can see it. The control is the same turn one step shorter: ground the
## infantry's own legs already covered, and the finding comes back.
func test_a_power_that_bought_a_cell_out_of_normal_reach_is_not_reported() -> void:
	var bought := _power_turn([{"c": "move", "path": [[0, 1], [1, 1], [2, 1], [3, 1], [4, 1]]}])
	var state := _charged_state(&"tomas_reed")
	_stand(state, &"infantry", 1, Vector2i(0, 1))
	assert_eq(_count(_run(state, bought), "spent_power"), 0)
	var within := _power_turn([{"c": "move", "path": [[0, 1], [1, 1], [2, 1], [3, 1]]}])
	var walked := _charged_state(&"tomas_reed")
	_stand(walked, &"infantry", 1, Vector2i(0, 1))
	assert_eq(_count(_run(walked, within), "spent_power"), 1)


# --- the three exclusions --------------------------------------------------------


## Hold the Line buys the *opponent's* turn, so the owner's turn produces nothing
## by construction. Reporting the roster's one defensive power on every
## activation is the worst false positive available.
func test_a_round_power_is_never_reported() -> void:
	var state := _charged_state(&"mara_voss")
	_stand(state, &"infantry", 1, Vector2i(3, 1))
	_stand(state, &"infantry", 2, Vector2i(4, 1))
	assert_eq(_count(_run(state, _power_turn()), "spent_power"), 0)


## Hammerfall takes a unit off the board with no `AttackCommand` behind it, which
## is why the first criterion counts the enemy census rather than the log. The
## second enemy is there so the blast does not rout seat 2 and end the match
## before the turn can be handed over.
func test_hammerfall_that_cleared_a_square_is_not_reported() -> void:
	var state := _charged_state(&"radek_morn")
	_stand(state, &"infantry", 1, Vector2i(0, 1))
	_stand(state, &"tank", 2, Vector2i(4, 1))
	_stand(state, &"infantry", 2, Vector2i(7, 3))
	var entries: Array = [{"c": "power", "target": [4, 1]}, {"c": "end_turn"}]
	assert_eq(_count(_run(state, entries), "spent_power"), 0)


## Judged on the board the side hands over, so a recording that stops before it
## does says nothing: the turn the meter was meant to buy may be off the end of
## the file, and `Report.stopped` is what tells the reader that.
func test_a_power_on_the_last_recorded_turn_is_not_reported() -> void:
	var state := _charged_state(&"alina_ward")
	assert_eq(_count(_run(state, [{"c": "power", "target": [0, 0]}]), "spent_power"), 0)


# --- ranking ---------------------------------------------------------------------


## The two are opposite readings of one meter, and a mistimed spend is the
## cheaper mistake — so a report that holds both puts the banked one first.
func test_a_reported_spend_ranks_below_a_banked_meter() -> void:
	var spent := _first(_run(_charged_state(&"alina_ward"), _power_turn()), "spent_power")
	var idle: Array = []
	for i in 6:
		idle.append({"c": "end_turn"})
	var banked := _first(_run(_charged_state(&"alina_ward"), idle), "banked_power")
	assert_not_null(banked, "the control must actually bank a meter")
	assert_lt(spent.severity, banked.severity)
