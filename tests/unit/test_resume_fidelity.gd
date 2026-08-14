extends GutTest
## The merge bar for saves, the shape `test_replay_fidelity.gd` is for recordings:
## a match that stopped and resumed must play out exactly as one that never
## stopped.
##
## The save format is ten versions of additive sections, and every one of them is
## checked field by field elsewhere. What nothing checked is the class of bug the
## format is most exposed to — a piece of sim state nobody remembered to write —
## because a missing field looks like nothing at all until the match carries on
## and diverges: a half-captured city resets, a wounded unit is whole, a roll
## lands differently. So this plays a real seeded AI-versus-AI match, cuts it in
## half through `SaveCodec.encode`/`decode` (and through JSON, which is the shape
## a save reaches the disk in), and asserts the second half is the same match.
##
## `ReplayCodec.checkpoint` is the digest, for the reason it exists: it is the
## board, in one integer, and it is already the authority on what "the same board"
## means. What it deliberately does not read is `Unit.tag` and the RNG stream
## position, so those are asserted separately — the stream because a save that
## dropped it would replay the same commands and roll different luck, and the tag
## because a name that did not survive is a mission that can no longer find its
## unit.
##
## The board is a shipped file rather than an inline fixture, because a save
## stores its board by path and reloads it from `res://`.

const BOARD := "res://maps/first_steps.txt"
const SEED := 4242
## Far enough in that both sides have built, captured and traded shots, so the
## boundary cuts a match with something in every section of the envelope.
const SAVE_AT := 40
## And far enough past it that a piece of dropped state has room to show. Both
## halves are small on purpose: this is a gate, not a measurement.
const AFTER := 40

## Seated on both sides so that whichever seat holds the boundary, it holds a
## general with a ROUND-duration power — one that outlives the save rather than
## coming down with the turn that fired it.
const COMMANDERS := {1: &"sable_wren", 2: &"sable_wren"}

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


## What one run of the same match left behind: every board it passed through
## after the boundary, and the one it stopped on.
class Run:
	var checkpoints: Array[int] = []
	var state: GameState
	var staged_power := false
	var staged_capture := false


func _open(commanders: Dictionary) -> GameState:
	var map := MapData.load_from_file(BOARD, terrain_db)
	var seats: Dictionary = {}
	for team: int in commanders:
		seats[team] = commander_db.by_id(commanders[team])
	var state := GameState.create(map, unit_db, chart, seats)
	state.map_path = map.source_path
	state.rng.seed = SEED
	return state


func _planners(state: GameState) -> Dictionary:
	var planners: Dictionary = {}
	for team in state.teams:
		planners[team] = AIController.new(unit_db)
	return planners


func _step(state: GameState, planners: Dictionary) -> void:
	var planner: AIController = planners[state.current_team]
	var command: Command = planner.plan_next_command(state)
	if command.validate(state) != "":
		command = EndTurnCommand.new()
	command.apply(state)


## The save as it actually travels: encoded, through JSON and back, decoded.
## The commander registry is handed over because without it every seat decodes
## neutral, and the second half would be played under rules nobody played the
## first half under.
func _round_trip(state: GameState) -> GameState:
	var json := JSON.new()
	assert_eq(
		json.parse(JSON.stringify(SaveCodec.encode(state, state.teams))),
		OK,
		"a save has to be JSON — that is how it reaches the disk"
	)
	var loaded := SaveCodec.decode(json.data, terrain_db, unit_db, chart, commander_db)
	assert_not_null(loaded, "the save has to rebuild")
	return loaded.state if loaded != null else null


## One playing of the match. `resume` cuts it at the boundary and carries on from
## the decoded save with freshly built planners — which is what a player who
## quits and comes back gets — and `stage` puts a capture and a power on the
## board first, so the boundary has something in the fields nobody would miss.
func _play(stage: bool, resume: bool) -> Run:
	var run := Run.new()
	var state := _open(COMMANDERS)
	var planners := _planners(state)
	for _i in SAVE_AT:
		if state.winner != 0:
			break
		_step(state, planners)
	assert_eq(state.winner, 0, "the boundary has to fall inside a match still being played")
	if stage:
		run.staged_power = _stage_power(state)
		run.staged_capture = _stage_capture(state)
	if resume:
		state = _round_trip(state)
		if state == null:
			return run
		planners = _planners(state)
	while run.checkpoints.size() < AFTER and state.winner == 0:
		_step(state, planners)
		run.checkpoints.append(ReplayCodec.checkpoint(state))
	run.state = state
	return run


## Fires the current side's Command Power, banking its cost first. Wren's Vanish
## lasts a round, so it is still up on the far side of the boundary.
func _stage_power(state: GameState) -> bool:
	var team := state.current_team
	if state.commander_state(team).power_active:
		return true
	return Fixture.fire_power(state, team) == ""


## Leaves a capture half-finished on the board. Usually the match has already put
## one there, and then there is nothing to stage; otherwise a capture-capable unit
## is walked onto ground its side does not hold and chips at it, choosing a
## property the chip cannot finish — a completed capture leaves no progress
## behind, and progress across the boundary is the point.
func _stage_capture(state: GameState) -> bool:
	if not state.capture_progress.is_empty():
		return true
	for unit in state.units_of(state.current_team):
		if unit.acted or not unit.type.can_capture:
			continue
		var reach := MovementResolver.reachable(state, unit)
		var strength := CaptureCommand.capture_strength(state, unit)
		for cell: Vector2i in reach.costs:
			if state.capture_progress.get(cell, state.rules_config.capture_points) <= strength:
				continue
			var command := CaptureCommand.new(unit, reach.path_to(cell))
			if command.validate(state) != "":
				continue
			command.apply(state)
			return not state.capture_progress.is_empty()
	return false


## The first board the two runs disagreed on, spelled out. Empty when they played
## the same match all the way through.
func _divergence(played: Run, resumed: Run) -> String:
	if played.checkpoints.size() != resumed.checkpoints.size():
		return (
			"the resumed match is %d commands long, the played one %d"
			% [resumed.checkpoints.size(), played.checkpoints.size()]
		)
	for i in played.checkpoints.size():
		if played.checkpoints[i] != resumed.checkpoints[i]:
			return (
				"command %d after the save: %d played, %d resumed"
				% [i + 1, played.checkpoints[i], resumed.checkpoints[i]]
			)
	return ""


func _assert_same_match(played: Run, resumed: Run) -> void:
	assert_not_null(played.state)
	assert_not_null(resumed.state)
	if played.state == null or resumed.state == null:
		return
	assert_gt(played.checkpoints.size(), 0, "the run past the boundary has to play something")
	assert_eq(_divergence(played, resumed), "", "a resumed match is the match it resumed")
	# Neither is in the digest, and both would replay a board that looks right and
	# then stop being right: the stream on the next shot fired, the names the moment
	# a mission goes looking for one.
	assert_eq(
		played.state.rng.state, resumed.state.rng.state, "the luck stream picks up where it stopped"
	)
	assert_eq(_tags(played.state), _tags(resumed.state), "a named unit keeps its name")
	for team in played.state.teams:
		assert_eq(
			int(resumed.state.funds.get(team, -1)),
			int(played.state.funds.get(team, -1)),
			"team %d's treasury" % team
		)


func _tags(state: GameState) -> Array[String]:
	var names: Array[String] = []
	for unit in state.units:
		names.append(String(unit.tag))
	return names


# --- the bar -------------------------------------------------------------------


func test_a_saved_match_plays_out_as_the_one_that_never_stopped() -> void:
	_assert_same_match(_play(false, false), _play(false, true))


## The same bar over the three fields a boundary is most likely to lose, because
## nothing on the board says they are missing: a capture halfway through, a meter
## with charge on it, and a power that is still up.
func test_a_match_saved_mid_capture_and_mid_power_resumes_on_the_same_board() -> void:
	var played := _play(true, false)
	assert_true(played.staged_power, "the boundary has to carry a power that is still up")
	assert_true(played.staged_capture, "the boundary has to carry a capture in progress")
	_assert_same_match(played, _play(true, true))
