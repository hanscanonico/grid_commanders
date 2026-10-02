extends GutTest
## A rematch is played on the board the match just finished on, even when that board
## is one the player drew and its file has since been renamed, deleted or saved over.
##
## A resumed save brings its board along (`SaveBoard`, playtest ED-02), so the match
## plays on whatever became of the file. The rematch request used to name the board
## by path alone, and `BattleSetup` fell back to the default board when that path had
## gone. Reachable without a scene, like test_resume_setup.gd: `BattleSetup` and
## `MatchRequest` are Node-free.

const NAME := "tub_rematch"
const RENAMED := "tub_rematch_moved"
## Not the default board, so a rematch that fell back to it cannot pass for this one.
const DRAWN := "res://maps/scrimmage.txt"
const OTHER := "res://maps/first_steps.txt"
const SLOT := "user://test_user_board_rematch.json"

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
	for path in [SLOT, SLOT + SaveGame.BACKUP_SUFFIX, SLOT + SaveGame.TEMP_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _build(request: MatchRequest) -> BattleSetup.BuiltMatch:
	return BattleSetup.build(request, terrain_db, unit_db, Fixture.commander_db(), SLOT)


## A match on the drawn board, saved on day 5 and then resumed from the slot.
func _resumed_after(change: Callable) -> BattleSetup.BuiltMatch:
	var state := GameState.create(UserMaps.load_map(NAME, terrain_db), unit_db, chart)
	state.map_path = UserMaps.path_for(NAME)
	state.day = 5
	assert_true(SaveGame.save(state, [2], SLOT))
	change.call()
	var resume := MatchRequest.from_menu(
		OTHER, [2] as Array[int], false, Difficulty.DEFAULT_ID, {}, true
	)
	var resumed := _build(resume)
	assert_not_null(resumed, "the save resumes on the board it carries")
	if resumed != null:
		assert_eq(resumed.map.source_text, FileAccess.get_file_as_string(DRAWN))
	return resumed


func _assert_rematch_on_the_played_board(resumed: BattleSetup.BuiltMatch) -> void:
	if resumed == null:
		return
	var rematch := _build(MatchRequest.from_match(resumed.game, [2] as Array[int], &"normal"))
	assert_not_null(rematch)
	if rematch == null:
		return
	assert_eq(rematch.map.source_text, resumed.map.source_text, "the board just played")
	assert_eq(rematch.game.map_path, UserMaps.path_for(NAME), "named as it was played")
	assert_eq(rematch.game.day, 1, "a rematch starts over")


func test_a_rematch_survives_the_board_being_deleted() -> void:
	_assert_rematch_on_the_played_board(
		_resumed_after(func() -> void: assert_eq(UserMaps.delete(NAME), ""))
	)


func test_a_rematch_survives_the_board_being_renamed() -> void:
	_assert_rematch_on_the_played_board(
		_resumed_after(func() -> void: assert_eq(UserMaps.rename(NAME, RENAMED), ""))
	)


func test_a_rematch_survives_the_board_being_saved_over() -> void:
	var other := FileAccess.get_file_as_string(OTHER)
	_assert_rematch_on_the_played_board(
		_resumed_after(func() -> void: assert_eq(UserMaps.save(NAME, other), ""))
	)


## A shipped board still travels by path, so a rematch follows that board's edits.
func test_a_shipped_board_rematches_by_path_alone() -> void:
	var game := GameState.create(MapData.load_from_file(OTHER, terrain_db), unit_db, chart)
	game.map_path = OTHER
	var request := MatchRequest.from_match(game, [2] as Array[int], &"normal")
	assert_eq(request.map_text, "")
	assert_eq(request.map_path, OTHER)


## A board named on the command line is that file, not the one a rematch carried.
func test_a_map_flag_drops_the_carried_board() -> void:
	var game := GameState.create(UserMaps.load_map(NAME, terrain_db), unit_db, chart)
	game.map_path = UserMaps.path_for(NAME)
	var request := MatchRequest.from_match(game, [2] as Array[int], &"normal")
	assert_eq(request.map_text, FileAccess.get_file_as_string(DRAWN))
	request.apply_cmdline(PackedStringArray(["--map=first_steps"]))
	assert_eq(request.map_path, OTHER)
	assert_eq(request.map_text, "")
