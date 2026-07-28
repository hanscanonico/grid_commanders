extends GutTest

const TEST_PATH := "user://test_save.json"
const TEMP_PATH := TEST_PATH + ".tmp"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func after_each() -> void:
	# Both paths are cleared in both shapes — a file where a save landed, and the
	# directory a failure test parks in the way of the temp or of the slot itself.
	_remove(TEST_PATH)
	_remove(TEMP_PATH)


func _remove(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)


func _first_steps_state() -> GameState:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = "res://maps/first_steps.txt"
	return state


func test_roundtrip_restores_the_match() -> void:
	var state := _first_steps_state()
	state.fog_enabled = true
	state.day = 3
	state.current_team = 2
	state.funds[1] = 4200
	state.funds[2] = 1300
	state.set_owner(Vector2i(3, 4), 1)
	state.capture_progress[Vector2i(3, 4)] = 10
	var infantry := state.unit_at(Vector2i(4, 3))
	var apc := state.unit_at(Vector2i(3, 3))
	infantry.hp = 55
	infantry.acted = true
	infantry.carrier = apc
	infantry.cell = apc.cell
	apc.fuel = 33
	assert_true(SaveGame.save(state, [2] as Array[int], TEST_PATH))
	var loaded := SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH)
	assert_not_null(loaded)
	var copy := loaded.state
	assert_eq(loaded.ai_teams, [2] as Array[int])
	assert_eq(copy.day, 3)
	assert_eq(copy.current_team, 2)
	assert_true(copy.fog_enabled)
	assert_eq(copy.funds[1], 4200)
	assert_eq(copy.funds[2], 1300)
	assert_eq(copy.owner_at(Vector2i(3, 4)), 1)
	assert_eq(copy.capture_progress[Vector2i(3, 4)], 10)
	assert_eq(copy.units.size(), state.units.size())
	var copy_apc := copy.unit_at(Vector2i(3, 3))
	assert_eq(copy_apc.type.id, &"apc")
	assert_eq(copy_apc.fuel, 33)
	var passengers := copy.cargo_of(copy_apc)
	assert_eq(passengers.size(), 1)
	assert_eq(passengers[0].type.id, &"infantry")
	assert_eq(passengers[0].hp, 55)
	assert_true(passengers[0].acted)


func test_roundtrip_preserves_rng_sequence() -> void:
	var state := _first_steps_state()
	state.rng.seed = 987654321
	state.rng.randi()  # advance the stream a little
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	var loaded := SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH)
	assert_eq(
		loaded.state.rng.randi(),
		state.rng.randi(),
		"combat luck must continue identically after loading"
	)


## COM-51. Every unwritable target this platform can stage — a read-only file, a
## read-only directory, a directory standing where the file should be, a directory
## that is not there at all — is refused by `FileAccess.open`, so this is the branch
## a test can reach and it is now guarded rather than merely believed. The other
## half of the fix is the one no in-process test can induce: a write that fails
## *after* a successful open, which is what a full disk does, and what the explicit
## close and error check exist for.
func test_save_to_an_unwritable_path_reports_failure() -> void:
	var state := _first_steps_state()
	assert_false(SaveGame.save(state, [] as Array[int], "user://no_such_dir/save.json"))
	assert_push_error("cannot write")


## COM-51. The half of the fix a test *can* stage: a save that cannot be written is
## a save the player still has. Standing a directory where the temp belongs is the
## one unwritable target reachable in-process, and it fails at the same place a full
## disk does — before anything has touched the slot.
func test_a_failed_write_leaves_the_previous_save_intact() -> void:
	var state := _first_steps_state()
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	var good := FileAccess.get_file_as_string(TEST_PATH)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(TEMP_PATH))
	state.day = 9
	assert_false(SaveGame.save(state, [] as Array[int], TEST_PATH))
	assert_push_error("cannot write")
	assert_eq(FileAccess.get_file_as_string(TEST_PATH), good, "the old save is byte-identical")
	var loaded := SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.state.day, 1, "and it still loads, as the match it recorded")


## COM-51. A temp that outlives its failure is the *next* save's disaster: it would be
## renamed over a slot it never described. This is the one failure path a test can push
## far enough to stage a temp at all — the write lands, the swap is what is refused —
## and nothing is left behind there either.
func test_a_failed_swap_leaves_no_temp_behind() -> void:
	var state := _first_steps_state()
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(TEST_PATH))
	assert_false(SaveGame.save(state, [] as Array[int], TEST_PATH))
	assert_push_error("cannot replace")
	assert_false(FileAccess.file_exists(TEMP_PATH), "the staged temp is discarded, not left")


func test_a_successful_save_leaves_no_temp_behind() -> void:
	var state := _first_steps_state()
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	assert_false(FileAccess.file_exists(TEMP_PATH), "the temp is renamed over the slot, not left")


## COM-51. Every save but a match's first one renames over a slot that is already
## there, which is the branch the swap exists for and the one a save-once test never
## reaches: were it to refuse an occupied destination, only the first save of a match
## would answer `true`.
func test_a_later_save_replaces_the_one_before_it() -> void:
	var state := _first_steps_state()
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	state.day = 7
	state.funds[1] = 8000
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH), "saving over a slot works")
	assert_false(FileAccess.file_exists(TEMP_PATH))
	var loaded := SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.state.day, 7, "the slot holds the later save, whole")
	assert_eq(loaded.state.funds[1], 8000)


func test_missing_file_returns_null() -> void:
	assert_false(SaveGame.has_save(TEST_PATH))
	assert_null(SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH))
	assert_push_error("cannot read")


func test_corrupted_file_returns_null() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("this is not json")
	file.close()
	assert_null(SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH))
	assert_push_error("not a valid save")


func test_missing_required_key_returns_null() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": SaveGame.VERSION, "day": 2}))
	file.close()
	assert_null(SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH))
	assert_push_error("is missing 'map_path'")


func test_malformed_unit_entry_returns_null() -> void:
	var state := _first_steps_state()
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	var text := FileAccess.get_file_as_string(TEST_PATH)
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text.replace('"fuel"', '"petrol"'))
	file.close()
	assert_null(SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH))
	assert_push_error("unit entry is missing 'fuel'")


func test_missing_team_funds_returns_null() -> void:
	var state := _first_steps_state()
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	var text := FileAccess.get_file_as_string(TEST_PATH)
	var data: Dictionary = JSON.parse_string(text)
	(data["funds"] as Dictionary).erase("2")
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	assert_null(SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH))
	assert_push_error("no funds for team 2")


func test_unknown_unit_type_returns_null() -> void:
	var state := _first_steps_state()
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	var text := FileAccess.get_file_as_string(TEST_PATH)
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text.replace('"infantry"', '"bogus_unit"'))
	file.close()
	assert_null(SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH))
	assert_push_error("unknown unit type")
