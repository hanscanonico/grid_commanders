extends GutTest
## A recording of a match on a board the player drew replays on that board, whatever
## has happened to the map file since: renamed, deleted, or saved over.
##
## A recording opens on a `SaveCodec` envelope (replay plan D1), so it carries the
## board exactly as a save does (`SaveBoard`, playtest ED-02). These cases hold the
## recording to it: the whole match re-issues command for command, checkpoint for
## checkpoint, onto the board it was played on.
##
## Every case writes into the real `user://maps` and its own replay directory, and
## takes both back out again.

const NAME := "tub_replay"
const RENAMED := "tub_replay_moved"
## The board the player drew, as text. Not the default board, so a playback that
## fell back to `MatchRequest.DEFAULT_MAP_PATH` could not pass for this one.
const DRAWN := "res://maps/scrimmage.txt"
const OTHER := "res://maps/first_steps.txt"
const DIR := "user://test_user_board_replays"
const DAYS := 4

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	assert_eq(UserMaps.save(NAME, FileAccess.get_file_as_string(DRAWN)), "")


func after_each() -> void:
	for name in [NAME, RENAMED]:
		if UserMaps.exists(name):
			UserMaps.delete(name)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)):
		for file in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))


## A seeded computer match on the drawn board, recorded to a file the way the live
## scene records one.
func _record() -> Dictionary:
	var file := ReplayFile.open_slot("0001", DIR)
	assert_not_null(file, "the slot must open")
	var recorder := ReplayRecorder.new(func() -> ReplayFile: return file)
	var setup := BalanceMatchEngine.Setup.new()
	setup.map = UserMaps.load_map(NAME, terrain_db)
	setup.unit_db = unit_db
	setup.chart = chart
	setup.seed_val = 31
	setup.days_cap = DAYS
	setup.tiers = {1: &"normal", 2: &"normal"}
	setup.planners = {1: AIController.new(unit_db), 2: AIController.new(unit_db)}
	setup.replay = recorder
	var outcome := BalanceMatchEngine.play(setup)
	recorder.close()
	assert_gt(outcome.commands, 10, "the match has to actually play out")
	return {"path": file.path(), "state": outcome.state, "commands": outcome.commands}


## Walks the recording on disk back through the sim and returns where it lands.
func _replayed(path: String, expected_commands: int) -> GameState:
	var replay := ReplayFile.read(path)
	assert_not_null(replay, "the recording still reads")
	if replay == null:
		return null
	var player := ReplayPlayer.new(replay, unit_db)
	var loaded := player.opening(terrain_db, chart)
	assert_not_null(loaded, "the opening still rebuilds")
	if loaded == null:
		return null
	var state := loaded.state
	assert_eq(state.map.source_text, FileAccess.get_file_as_string(DRAWN), "the drawn board")
	assert_eq(state.map_path, UserMaps.path_for(NAME), "still named as it was recorded")
	assert_eq(player.length(), expected_commands)
	while not player.finished():
		var command := player.next_command(state)
		assert_not_null(command, "line %d must rebuild" % player.played())
		if command == null:
			return null
		assert_eq(command.validate(state), "", "line %d must still be legal" % player.played())
		command.apply(state)
		assert_eq(player.drift(state), "", "line %d lands on its board" % player.played())
	return state


func _assert_replays_as_recorded(recorded: Dictionary) -> void:
	var state := _replayed(recorded["path"], recorded["commands"])
	assert_not_null(state)
	if state == null:
		return
	var played: GameState = recorded["state"]
	assert_eq(ReplayCodec.checkpoint(state), ReplayCodec.checkpoint(played), "the played board")
	assert_eq(state.day, played.day)


func test_a_recording_survives_its_board_being_renamed() -> void:
	var recorded := _record()
	assert_eq(UserMaps.rename(NAME, RENAMED), "")
	_assert_replays_as_recorded(recorded)


func test_a_recording_survives_its_board_being_deleted() -> void:
	var recorded := _record()
	assert_eq(UserMaps.delete(NAME), "")
	_assert_replays_as_recorded(recorded)


func test_a_recording_survives_its_board_being_saved_over() -> void:
	var recorded := _record()
	assert_eq(UserMaps.save(NAME, FileAccess.get_file_as_string(OTHER)), "")
	_assert_replays_as_recorded(recorded)


## The launch route a Replays-page pick takes, on a board that is gone.
func test_a_watched_recording_opens_on_its_board_after_the_file_is_gone() -> void:
	var recorded := _record()
	assert_eq(UserMaps.delete(NAME), "")
	var request := MatchRequest.from_replay(recorded["path"])
	var built := BattleSetup.build(request, terrain_db, unit_db, Fixture.commander_db())
	assert_not_null(built)
	if built == null:
		return
	assert_eq(built.map.source_text, FileAccess.get_file_as_string(DRAWN))
	assert_eq(built.game.map_path, UserMaps.path_for(NAME))
