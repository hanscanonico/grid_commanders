extends GutTest
## A match saved on a board the player drew resumes on that board, whatever has
## happened to the map file since: renamed, deleted, or saved over from the editor.
##
## A shipped board is stored by path and follows its own edits; a board the player
## drew is theirs to rename and delete from Match Setup, so the save carries it
## (playtest ED-02, where renaming the map greyed Continue out for good).
##
## Every case writes into the real `user://maps` and its own save slot, and takes
## both back out again.

const NAME := "test_save_user_board"
const RENAMED := "test_save_user_board_renamed"
const SHIPPED := "res://maps/first_steps.txt"
const SLOT := "user://test_save_user_board.json"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	assert_eq(UserMaps.save(NAME, FileAccess.get_file_as_string(SHIPPED)), "")


func after_each() -> void:
	for name in [NAME, RENAMED]:
		if UserMaps.exists(name):
			UserMaps.delete(name)
	for path in [SLOT, SLOT + SaveGame.BACKUP_SUFFIX, SLOT + SaveGame.TEMP_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _state_on(map: MapData) -> GameState:
	var state := GameState.create(map, unit_db, chart)
	state.map_path = map.source_path
	state.day = 3
	return state


func _saved_on_the_user_board() -> Dictionary:
	return SaveCodec.encode(_state_on(UserMaps.load_map(NAME, terrain_db)), [2] as Array[int])


func _decode(data: Dictionary) -> SaveCodec.LoadedMatch:
	return SaveCodec.decode(data, terrain_db, unit_db, chart)


func _assert_resumes_on_the_board_it_was_played_on(data: Dictionary) -> void:
	var loaded := _decode(data)
	assert_not_null(loaded, "the saved match still opens")
	if loaded == null:
		return
	var original := MapData.load_from_file(SHIPPED, terrain_db)
	assert_eq(loaded.state.map.size(), original.size(), "the board it was played on")
	assert_eq(loaded.state.day, 3)
	assert_eq(loaded.state.map_path, UserMaps.path_for(NAME), "still named as it was saved")


func test_a_save_survives_its_board_being_renamed() -> void:
	var data := _saved_on_the_user_board()
	assert_eq(UserMaps.rename(NAME, RENAMED), "")
	_assert_resumes_on_the_board_it_was_played_on(data)


func test_a_save_survives_its_board_being_deleted() -> void:
	var data := _saved_on_the_user_board()
	assert_eq(UserMaps.delete(NAME), "")
	_assert_resumes_on_the_board_it_was_played_on(data)


func test_a_save_survives_its_board_being_saved_over() -> void:
	var data := _saved_on_the_user_board()
	var other := FileAccess.get_file_as_string(MapCatalog.TUTORIAL_MAP_PATH)
	assert_eq(UserMaps.save(NAME, other), "")
	_assert_resumes_on_the_board_it_was_played_on(data)


## The round trip through the disk, and a resumed match saved again after its file
## went away still carries the board — it never re-reads the file it no longer has.
func test_a_resumed_match_saved_again_still_carries_its_board() -> void:
	assert_true(SaveGame.save(_state_on(UserMaps.load_map(NAME, terrain_db)), [2], SLOT))
	assert_eq(UserMaps.delete(NAME), "")
	var loaded := SaveGame.load_game(terrain_db, unit_db, chart, SLOT)
	assert_not_null(loaded)
	if loaded == null:
		return
	var again := SaveCodec.encode(loaded.state, loaded.ai_teams)
	_assert_resumes_on_the_board_it_was_played_on(again)
	assert_eq(SaveGame.status(SLOT).state, SaveGame.Slot.State.READABLE)


## A shipped board is not carried: it is stored by path and follows its own edits.
func test_a_shipped_board_is_stored_by_path_alone() -> void:
	var state := _state_on(MapData.load_from_file(SHIPPED, terrain_db))
	assert_false(SaveCodec.encode(state, [2] as Array[int]).has(SaveBoard.KEY))


## A save written before boards were carried names its board by path only. Once that
## file is gone the slot is not offered as a match to continue.
func test_an_older_save_whose_board_is_gone_is_not_offered() -> void:
	assert_true(SaveGame.save(_state_on(UserMaps.load_map(NAME, terrain_db)), [2], SLOT))
	var text := FileAccess.get_file_as_string(SLOT)
	var data: Dictionary = JSON.parse_string(text)
	data.erase(SaveBoard.KEY)
	var file := FileAccess.open(SLOT, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	assert_eq(SaveGame.status(SLOT).state, SaveGame.Slot.State.READABLE, "board still there")
	assert_eq(UserMaps.rename(NAME, RENAMED), "")
	var slot := SaveGame.status(SLOT)
	assert_eq(slot.state, SaveGame.Slot.State.UNREADABLE)
	assert_false(slot.reason.contains("user://"), "said in player words")


func test_a_carried_board_that_is_not_text_is_refused() -> void:
	var data := _saved_on_the_user_board()
	data[SaveBoard.KEY] = 7
	assert_ne(SaveCodec.validate(data), "")
