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
## The aimed-power run's own cap. Hammerfall is the dearest meter in the game at
## 24,000, so it needs a longer match than the plain fidelity run to reach a
## firing at all — and it has to be the shipped commander at the shipped price,
## because playback rebuilds him from `CommanderDB` and a doctored copy would be
## re-issued against a meter it never filled.
const AIMED_DAYS := 12
## The mission the scripted-beat run plays, and the beat it has to reach: Ferrow
## picking his lane on day three. A shipped mission rather than a fixture, for the
## board's own reason — a replay stores its board by path — and because what the
## header carries is the pair of ids `CampaignDB` resolves.
const CAMPAIGN := &"six_marshals"
const MISSION := &"sm02_ambush_pass"
const EVENT_DAYS := 4

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB
var campaign_db: CampaignDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()
	campaign_db = CampaignDB.load_default()


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


## Walks a recording back through the sim, checkpoint by checkpoint, and returns
## the board it lands on. Null when a line refused to rebuild or to apply — each
## of which fails here rather than silently shortening the walk.
func _re_issue(replay: ReplayCodec.Replay, expected_commands: int) -> GameState:
	var player := ReplayPlayer.new(replay, unit_db, campaign_db)
	assert_eq(player.mission_error(), "", "the mission this recording names must still ship")
	# The commander registry is handed over exactly as BattleSetup and the analyser
	# hand it over: without it every seat decodes neutral, and a doctrine's match
	# would be re-issued against rules nobody played it under.
	var loaded := player.opening(terrain_db, chart, commander_db)
	assert_not_null(loaded, "the opening envelope must rebuild")
	if loaded == null:
		return null
	var state := loaded.state
	assert_eq(player.length(), expected_commands, "every applied command is one line")
	while not player.finished():
		var command := player.next_command(state)
		assert_not_null(command, "line %d must rebuild" % player.played())
		if command == null:
			return null
		assert_eq(
			command.validate(state),
			"",
			"line %d (%s) must still be legal" % [player.played(), ReplayCodec.name_of(command)]
		)
		command.apply(state)
		assert_eq(
			player.drift(state), "", "line %d must land on the recorded board" % player.played()
		)
	return state


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
	replay.campaign = StringName(String(round_tripped[0].get("campaign", "")))
	replay.mission = StringName(String(round_tripped[0].get("mission", "")))
	replay.entries = round_tripped.slice(1)
	return replay


func _mission() -> MissionDefinition:
	var campaign := campaign_db.by_id(CAMPAIGN)
	assert_not_null(campaign, "the fixture campaign has to ship")
	var mission := campaign.mission(MISSION) if campaign != null else null
	assert_not_null(mission, "the fixture mission has to ship")
	return mission


## A mission played headlessly, with the recorder observing at the two moments
## the live pipeline hands it and the mission's beats fired at the boundary
## `Battle.conclude_command` fires them at.
##
## Its own loop rather than `BalanceMatchEngine`'s, because that engine plays a
## skirmish and has no campaign in it (balance D2) — so the only place a recorded
## event line can come from is a walk that fires one. What it must match is the
## *order*: every beat due lands after the command that made it due and before
## anything else (campaign-depth D3).
func _play_mission(
	mission: MissionDefinition, recorder: ReplayRecorder, seed_val: int, days: int
) -> GameState:
	var state := GameState.create(
		MapData.load_from_file(mission.map_path, terrain_db),
		unit_db,
		chart,
		_commanders_of(mission),
		mission.seats
	)
	assert_not_null(state, "the mission's board has to build")
	state.map_path = mission.map_path
	for team: int in mission.sides:
		state.sides[team] = int(mission.sides[team])
	state.rng.seed = seed_val
	recorder.begin(state, state.teams, Difficulty.DEFAULT_ID, "", "", CAMPAIGN, MISSION)
	var tally := MissionProgress.new()
	tally.observe(state, mission.player_team)
	var planners: Dictionary = {}
	for team in state.teams:
		planners[team] = AIController.new(unit_db)
	_fire_due(state, mission, tally, recorder)
	while state.winner == 0 and state.day <= days:
		var planner: AIController = planners[state.current_team]
		var command: Command = planner.plan_next_command(state)
		if command.validate(state) != "":
			command = EndTurnCommand.new()
		_apply(state, command, recorder)
		tally.observe(state, mission.player_team)
		_fire_due(state, mission, tally, recorder)
	return state


func _commanders_of(mission: MissionDefinition) -> Dictionary:
	var commanders: Dictionary = {}
	for team: int in mission.commanders:
		commanders[team] = commander_db.by_id(mission.commanders[team])
	return commanders


func _fire_due(
	state: GameState, mission: MissionDefinition, tally: MissionProgress, recorder: ReplayRecorder
) -> void:
	for event: MissionEvent in mission.events:
		if not event.is_due(state, mission.player_team, tally):
			continue
		var command := MissionEventCommand.new(event, mission.player_team)
		if command.validate(state) != "":
			continue
		_apply(state, command, recorder)
		tally.record_fired(event.id)


func _apply(state: GameState, command: Command, recorder: ReplayRecorder) -> void:
	recorder.before_apply(state, command)
	command.apply(state)
	recorder.after_apply(state)


# --- the bar -------------------------------------------------------------------


func test_a_recorded_match_re_issues_to_the_same_board() -> void:
	var recorder := ReplayRecorder.new()
	var outcome := BalanceMatchEngine.play(_setup(4242, recorder))
	assert_gt(outcome.commands, 30, "the fixture match has to actually play out")

	var state := _re_issue(_replay_of(recorder.lines()), outcome.commands)
	assert_not_null(state)
	if state == null:
		return
	assert_eq(
		ReplayCodec.checkpoint(state),
		ReplayCodec.checkpoint(outcome.state),
		"the replayed board must be the played one"
	)
	assert_eq(state.winner, outcome.state.winner)
	assert_eq(state.day, outcome.state.day)
	assert_eq(state.units.size(), outcome.state.units.size())


## The merge bar for format 2 (more-commanders MC4). A power that names a cell is
## the one command whose meaning is not recoverable from the board it was applied
## to, so a log that dropped the target would replay as a strike on the origin —
## which on this board is water, lands on nothing, and would still reach the end
## of the recording. The digest is what refuses it, and the assertion below is
## what proves an aimed line was in the log at all.
func test_a_recorded_aimed_power_re_issues_to_the_same_board() -> void:
	var recorder := ReplayRecorder.new()
	var setup := _setup(4242, recorder)
	setup.days_cap = AIMED_DAYS
	setup.commanders = {1: commander_db.by_id(&"radek_morn"), 2: commander_db.by_id(&"tomas_reed")}
	var outcome := BalanceMatchEngine.play(setup)

	var aimed := 0
	for line in recorder.lines():
		if (
			String(line.get("c", "")) == "power"
			and ReplayCodec.decode_cell(line["target"]) != Vector2i.ZERO
		):
			aimed += 1
	assert_gt(aimed, 0, "Hammerfall never went off, so this proves nothing about its line")

	var state := _re_issue(_replay_of(recorder.lines()), outcome.commands)
	assert_not_null(state)
	if state == null:
		return
	assert_eq(
		ReplayCodec.checkpoint(state),
		ReplayCodec.checkpoint(outcome.state),
		"the replayed board must be the played one, square of ground included"
	)
	assert_eq(state.units.size(), outcome.state.units.size())


## The merge bar for format 3 (campaign-depth CD3). A scripted beat is a command
## whose meaning is *entirely* off the board: the line names an event id and
## nothing else, so a header that lost the mission, or a build that lost the
## event, replays a match with the reinforcement column missing. The digest is
## what refuses that; the assertion below is what proves an event line was in the
## log at all.
func test_a_recorded_mission_re_issues_its_scripted_beats() -> void:
	var mission := _mission()
	var recorder := ReplayRecorder.new()
	var played := _play_mission(mission, recorder, 4242, EVENT_DAYS)

	var lines := recorder.lines()
	var beats := 0
	for line in lines:
		if String(line.get("c", "")) == "event":
			beats += 1
			assert_eq(String(line["event"]), "he_commits", "the line names the beat by id")
	assert_eq(beats, 1, "the mission's day-three beat has to have landed exactly once")

	var state := _re_issue(_replay_of(lines), lines.size() - 1)
	assert_not_null(state)
	if state == null:
		return
	assert_eq(
		ReplayCodec.checkpoint(state),
		ReplayCodec.checkpoint(played),
		"the replayed board must be the played one, scripted column included"
	)
	assert_eq(state.units.size(), played.units.size())


## A recording whose mission this build no longer has is refused by name, before
## a single command is handed out — never played up to its first scripted beat and
## then stopped with a message about the board.
func test_a_recording_of_a_mission_that_has_gone_is_refused_by_name() -> void:
	var replay := ReplayCodec.Replay.new()
	replay.campaign = &"six_marshals"
	replay.mission = &"sm99_a_mission_that_never_shipped"
	assert_string_contains(ReplayPlayer.new(replay, unit_db, campaign_db).mission_error(), "sm99")
	replay.campaign = &"a_war_nobody_fought"
	assert_string_contains(
		ReplayPlayer.new(replay, unit_db, campaign_db).mission_error(), "a_war_nobody_fought"
	)


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
