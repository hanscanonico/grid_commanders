extends GutTest
## The merge bar for replays (plan RP1): a match recorded and then re-issued must
## arrive at the same board, command for command.
##
## Everything else about the feature — the runner, the menu, the analyser — is
## worth nothing if this fails, because all three are reading a log that claims to
## be a match that was played. So it is checked the only way that means anything:
## play a real seeded AI-versus-AI match through the shipped engine with a
## recorder attached, then rebuild the opening from the recording alone and put
## every recorded command back through the sim.
##
## The board is a shipped map rather than an inline fixture, because a replay
## stores its board by path and reloads it from `res://` — an inline board has no
## path to store.

const BOARD := "res://maps/first_steps.txt"
## Long enough to build, trade, capture and fire a power; short enough to run a
## few times in a suite.
const DAYS := 8

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _setup(seed_val: int, recorder: ReplayRecorder) -> BalanceMatchEngine.Setup:
	var setup := BalanceMatchEngine.Setup.new()
	setup.map = MapData.load_from_file(BOARD, terrain_db)
	setup.unit_db = unit_db
	setup.chart = chart
	setup.seed_val = seed_val
	setup.days_cap = DAYS
	setup.tiers = {1: &"normal", 2: &"normal"}
	setup.planners = {1: AIController.new(unit_db), 2: AIController.new(unit_db)}
	setup.replay = recorder
	return setup


## The recorded lines as a replay, having been through JSON and back — which is
## the shape playback actually reads, and where a number too wide for a double
## would quietly lose its tail.
func _replay_of(lines: Array[Dictionary]) -> ReplayCodec.Replay:
	var round_tripped: Array[Dictionary] = []
	for line in lines:
		var json := JSON.new()
		assert_eq(json.parse(JSON.stringify(line)), OK, "every line must be JSON")
		round_tripped.append(json.data)
	var replay := ReplayCodec.Replay.new()
	replay.format = int(round_tripped[0]["replay"])
	replay.opening = round_tripped[0]["opening"]
	replay.entries = round_tripped.slice(1)
	return replay


# --- the bar -------------------------------------------------------------------


func test_a_recorded_match_re_issues_to_the_same_board() -> void:
	var recorder := ReplayRecorder.new()
	var outcome := BalanceMatchEngine.play(_setup(4242, recorder))
	assert_gt(outcome.commands, 30, "the fixture match has to actually play out")

	var player := ReplayPlayer.new(_replay_of(recorder.lines()), unit_db)
	var loaded := player.opening(terrain_db, chart)
	assert_not_null(loaded, "the opening envelope must rebuild")
	var state := loaded.state
	assert_eq(player.length(), outcome.commands, "every applied command is one line")

	while not player.finished():
		var command := player.next_command(state)
		assert_not_null(command, "line %d must rebuild" % player.played())
		if command == null:
			return
		assert_eq(
			command.validate(state),
			"",
			"line %d (%s) must still be legal" % [player.played(), ReplayCodec.name_of(command)]
		)
		command.apply(state)
		assert_eq(
			player.drift(state), "", "line %d must land on the recorded board" % player.played()
		)

	assert_eq(
		ReplayCodec.checkpoint(state),
		ReplayCodec.checkpoint(outcome.state),
		"the replayed board must be the played one"
	)
	assert_eq(state.winner, outcome.state.winner)
	assert_eq(state.day, outcome.state.day)
	assert_eq(state.units.size(), outcome.state.units.size())


## The recording says nothing about who was thinking — only what was done — so two
## different seeds produce two different logs, and the same seed produces the same
## one. Without this, a log that silently recorded nothing would still pass the
## test above.
func test_two_seeds_record_two_matches() -> void:
	var first := ReplayRecorder.new()
	var second := ReplayRecorder.new()
	BalanceMatchEngine.play(_setup(1, first))
	BalanceMatchEngine.play(_setup(2, second))
	assert_ne(
		JSON.stringify(first.lines()), JSON.stringify(second.lines()), "two seeds, two recordings"
	)

	var again := ReplayRecorder.new()
	BalanceMatchEngine.play(_setup(1, again))
	assert_eq(
		JSON.stringify(first.lines()),
		JSON.stringify(again.lines()),
		"one seed, one recording — a replay carries no clock and no wall time"
	)


# --- the self-check (plan D3) --------------------------------------------------


## The whole point of the digest: a board that is not the recorded one is *said*,
## at the command where it stopped being it, rather than played on in silence.
func test_a_board_that_drifts_is_named_and_not_played_on() -> void:
	var recorder := ReplayRecorder.new()
	BalanceMatchEngine.play(_setup(77, recorder))
	var player := ReplayPlayer.new(_replay_of(recorder.lines()), unit_db)
	var state := player.opening(terrain_db, chart).state

	var command := player.next_command(state)
	command.apply(state)
	assert_eq(player.drift(state), "", "an untouched board does not drift")

	# Stand in for the retuned .tres this exists to catch: the same commands, a
	# board that answered them differently.
	state.funds[state.teams[0]] += 1
	assert_string_contains(player.drift(state), "different build")


func test_the_digest_notices_a_unit_that_moved() -> void:
	var map := MapData.load_from_file(BOARD, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	var before := ReplayCodec.checkpoint(state)
	state.units[0].cell += Vector2i.RIGHT
	assert_ne(ReplayCodec.checkpoint(state), before)


func test_the_digest_survives_json() -> void:
	var map := MapData.load_from_file(BOARD, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	var digest := ReplayCodec.checkpoint(state)
	var json := JSON.new()
	json.parse(JSON.stringify({"ck": digest}))
	assert_eq(
		int(json.data["ck"]),
		digest,
		"JSON has one number type; a digest wider than a double is a false alarm on every replay"
	)
