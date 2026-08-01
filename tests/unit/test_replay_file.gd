extends GutTest
## The replay slot on disk: appending, reading back, the rotation, and the one
## damaged file that is read anyway.
##
## Every case writes into its own directory rather than `ReplayFile.DIR`, which
## is the player's — a test that pruned that one would delete recordings somebody
## wanted.

const DIR := "user://test_replays"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	_clear()


func after_all() -> void:
	_clear()


func _clear() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)):
		return
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [DIR, name]))


func _state() -> GameState:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = "res://maps/first_steps.txt"
	state.day = 4
	return state


func _opening() -> Dictionary:
	return SaveCodec.encode(_state(), [2] as Array[int])


## A slot holding a header and two moves, closed.
func _write_one(name: String, label: String = "a match") -> String:
	var file := ReplayFile.open_slot(name, DIR)
	assert_not_null(file, "the slot must open")
	file.append(ReplayCodec.header(_opening(), label, name))
	file.append({"n": 0, "c": "move", "path": [[1, 1], [2, 1]], "ck": 11})
	file.append({"n": 1, "c": "end_turn", "ck": 22})
	file.close()
	return file.path()


# --- writing and reading -------------------------------------------------------


func test_a_slot_round_trips_through_disk() -> void:
	var path := _write_one("0001")
	var replay := ReplayFile.read(path)
	assert_not_null(replay)
	assert_eq(replay.format, ReplayCodec.FORMAT)
	assert_eq(replay.label, "a match")
	assert_eq(replay.entries.size(), 2)
	assert_eq(replay.entries[0]["c"], "move")
	assert_eq(String(replay.opening["map_path"]), "res://maps/first_steps.txt")


func test_the_opening_rebuilds_into_the_board_it_recorded() -> void:
	var replay := ReplayFile.read(_write_one("0001"))
	var loaded := ReplayPlayer.new(replay, unit_db).opening(terrain_db, chart)
	assert_not_null(loaded, "a replay's opening is a save envelope, and loads like one")
	assert_eq(loaded.state.day, 4)
	assert_eq(loaded.state.map_path, "res://maps/first_steps.txt")


func test_a_file_that_is_not_a_replay_is_refused() -> void:
	var handle := FileAccess.open("%s/junk%s" % [DIR, ReplayFile.EXTENSION], FileAccess.WRITE)
	handle.store_line("not json at all")
	handle.close()
	assert_null(ReplayFile.read("%s/junk%s" % [DIR, ReplayFile.EXTENSION]))
	assert_push_error("does not open with a header")


func test_a_missing_file_is_refused() -> void:
	assert_null(ReplayFile.read("%s/nothing%s" % [DIR, ReplayFile.EXTENSION]))
	assert_push_error("cannot read")


# --- the interrupted write -----------------------------------------------------


## What a crash mid-match leaves behind. The match up to that point really
## happened, so it plays back one command shorter rather than being thrown away.
func test_a_replay_cut_off_mid_line_is_read_one_command_shorter() -> void:
	var path := _write_one("0001")
	var text := FileAccess.get_file_as_string(path)
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(text + '{"n": 2, "c": "mov')
	handle.close()

	var replay := ReplayFile.read(path)
	assert_not_null(replay, "a torn tail costs the last line, never the file")
	assert_eq(replay.entries.size(), 2)


## A bad line anywhere else is a corrupt file: dropping it silently would play a
## different match, which is the whole thing a replay must not do.
func test_a_replay_damaged_in_the_middle_is_refused() -> void:
	var path := _write_one("0001")
	var lines := FileAccess.get_file_as_string(path).split("\n", false)
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string("%s\ntorn\n%s\n" % [lines[0], lines[1]])
	handle.close()

	assert_null(ReplayFile.read(path))
	assert_push_error("unreadable line")


# --- the rotation --------------------------------------------------------------


func test_summarize_names_a_replay_without_parsing_a_command() -> void:
	var summary := ReplayFile.summarize(_write_one("0001", "Ironworks · a duel"))
	assert_not_null(summary)
	assert_eq(summary.label, "Ironworks · a duel")
	assert_eq(summary.map_path, "res://maps/first_steps.txt")
	assert_eq(summary.day, 4)


func test_listing_puts_the_newest_first() -> void:
	_write_one("0001", "first")
	_write_one("0002", "second")
	_write_one("0003", "third")
	var listed := ReplayFile.list(DIR)
	assert_eq(listed.size(), 3)
	assert_eq(listed[0].label, "third", "slot names sort chronologically, so the list is free")
	assert_eq(listed[2].label, "first")


func test_pruning_keeps_the_newest_and_drops_the_rest() -> void:
	for i in 5:
		_write_one("%04d" % i, "match %d" % i)
	ReplayFile.prune(2, DIR)
	var listed := ReplayFile.list(DIR)
	assert_eq(listed.size(), 2)
	assert_eq(listed[0].label, "match 4")
	assert_eq(listed[1].label, "match 3")


## The budget is what the directory holds *after* the new slot opens, not before.
func test_opening_a_slot_makes_room_for_itself() -> void:
	for i in ReplayFile.KEEP + 3:
		_write_one("%04d" % i)
	assert_eq(ReplayFile.list(DIR).size(), ReplayFile.KEEP)


## The slots rotate and there are few of them, so a boot that claimed one and was
## left before a single move would evict a match somebody played and leave a
## header nobody can watch. The recorder therefore holds the opener until there is
## a line worth writing.
func test_a_match_with_no_commands_claims_no_slot() -> void:
	var state := _state()
	var recorder := ReplayRecorder.new(func() -> ReplayFile: return ReplayFile.open_slot("9", DIR))
	recorder.begin(state, [2] as Array[int])
	recorder.close()
	assert_eq(ReplayFile.list(DIR).size(), 0, "an abandoned boot evicts nothing")


func test_the_first_command_opens_the_slot_and_writes_the_header_ahead_of_it() -> void:
	var state := _state()
	var recorder := ReplayRecorder.new(func() -> ReplayFile: return ReplayFile.open_slot("9", DIR))
	recorder.begin(state, [2] as Array[int], Difficulty.DEFAULT_ID, "a match")
	recorder.before_apply(state, EndTurnCommand.new())
	recorder.after_apply(state)
	recorder.close()

	var listed := ReplayFile.list(DIR)
	assert_eq(listed.size(), 1)
	var replay := ReplayFile.read(listed[0].path)
	assert_not_null(replay, "the header must have gone down before the command")
	assert_eq(replay.label, "a match")
	assert_eq(replay.entries.size(), 1)


func test_pruning_a_directory_that_is_not_there_is_not_an_error() -> void:
	ReplayFile.prune(3, "user://test_replays_absent")
	assert_eq(ReplayFile.list("user://test_replays_absent").size(), 0)
