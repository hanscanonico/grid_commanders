extends GutTest

const TEST_PATH := "user://test_save.json"
const TEMP_PATH := TEST_PATH + SaveGame.TEMP_SUFFIX
const BACKUP_PATH := TEST_PATH + SaveGame.BACKUP_SUFFIX

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func after_each() -> void:
	# All three paths are cleared in both shapes — a file where a save landed, and the
	# directory a failure test parks in the way of the temp, the backup or the slot.
	_remove(TEST_PATH)
	_remove(TEMP_PATH)
	_remove(BACKUP_PATH)


func _remove(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)


## Exactly the state a machine that lost power between the swap's two renames leaves
## behind: the slot gone, the whole previous save standing at the backup.
func _interrupt_a_swap() -> void:
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEST_PATH), ProjectSettings.globalize_path(BACKUP_PATH)
	)


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


## COM-51. Where each unwritable target reachable without mounting a volume now stops,
## checked against the code rather than assumed: a directory that is not there at all
## and a read-only directory are refused by `FileAccess.open`, because the temp is
## opened in that directory — as is a directory standing where the *temp* belongs,
## which is how the sibling below stages a refused write. A directory standing where
## the *slot* belongs gets past the write and is refused by the swap instead. A
## read-only slot *file* is no longer refused anywhere and now saves: the temp opens in
## the writable parent, and a rename needs write permission on the containing directory
## rather than on the destination it replaces.
##
## The failure the ticket was actually filed about needs a volume with no space left,
## which is a thing to stage rather than a thing to assert: on one, every signal the
## handle offers reads clean while nothing lands, so `save` answers for itself by
## re-reading the temp. That is why none of the tests below stand on `store_string`'s
## bool or on `get_error()` — neither one sees a full disk.
func test_save_to_an_unwritable_path_reports_failure() -> void:
	var state := _first_steps_state()
	assert_false(SaveGame.save(state, [] as Array[int], "user://no_such_dir/save.json"))
	assert_push_error("cannot write")


## COM-51. What writing through a temp buys, stated as a promise: a save that cannot be
## written is a save the player still has. Standing a directory where the temp belongs
## refuses the write at the open, one step earlier than a full volume does — but both
## fail before anything has touched the slot, which is the guarantee under test.
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
## renamed over a slot it never described. A directory standing where the slot belongs
## is one of the two ways a test can push a save far enough to stage a temp at all —
## the write lands, the second rename is what is refused. Nothing is set aside on this
## path: `file_exists` is false of a directory, so there is no previous save to move —
## which is also why the restore beside it is the one branch left uncovered. Reaching it
## needs the swap refused *with* a previous save aside, and after the set-aside the only
## thing that can refuse the rename is a parent directory that turned unwritable between
## the two, which is not a thing a single in-process call can be interrupted to stage.
func test_a_failed_swap_leaves_no_temp_behind() -> void:
	var state := _first_steps_state()
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(TEST_PATH))
	assert_false(SaveGame.save(state, [] as Array[int], TEST_PATH))
	assert_push_error("cannot replace")
	assert_false(FileAccess.file_exists(TEMP_PATH), "the staged temp is discarded, not left")
	assert_false(FileAccess.file_exists(BACKUP_PATH), "and nothing was set aside to leave")


## COM-51. The other way, and the one that exercises the set-aside the swap opens with:
## a directory sitting where the backup belongs refuses the first of the two renames.
## What the swap promises is what this asserts — the previous save is still there, whole
## and loadable, and neither the temp nor a backup outlives the failure.
func test_a_failed_set_aside_keeps_the_previous_save() -> void:
	var state := _first_steps_state()
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	var good := FileAccess.get_file_as_string(TEST_PATH)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	state.day = 9
	assert_false(SaveGame.save(state, [] as Array[int], TEST_PATH))
	assert_push_error("cannot set")
	assert_eq(FileAccess.get_file_as_string(TEST_PATH), good, "the old save is byte-identical")
	assert_false(FileAccess.file_exists(TEMP_PATH), "the staged temp is discarded, not left")
	var loaded := SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.state.day, 1, "and it still loads, as the match it recorded")


func test_a_successful_save_leaves_no_temp_behind() -> void:
	var state := _first_steps_state()
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	assert_false(FileAccess.file_exists(TEMP_PATH), "the temp is renamed over the slot, not left")
	assert_false(FileAccess.file_exists(BACKUP_PATH), "and a first save sets nothing aside")


## COM-51. The swap's cost, and why the readers had to learn about the backup: between
## its two renames the slot does not exist, and a machine that dies there leaves the
## whole previous match at the sibling. A copy nothing looks at is not durability, so
## every reader resolves it — Continue is offered, named, and resumes that match instead
## of reporting none, which is the ticket's own harm arriving by a different route.
func test_an_interrupted_swap_is_still_the_save_every_reader_finds() -> void:
	var state := _first_steps_state()
	state.day = 6
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	_interrupt_a_swap()
	assert_false(FileAccess.file_exists(TEST_PATH), "the slot is where the crash left it: gone")
	assert_true(SaveGame.has_save(TEST_PATH), "Continue is offered rather than greyed out")
	var summary := SaveGame.peek(TEST_PATH)
	assert_not_null(summary)
	assert_eq(summary.day, 6, "and the menu names the match it will resume")
	var loaded := SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.state.day, 6, "which is the one it resumes")


## COM-51. Recovery is a read, and finishing it is the writer's: the backup stands until
## the game next saves, which takes the slot back and clears it. Left undone, a single
## interrupted save would keep a stale copy beside the slot for the rest of the match.
func test_the_next_save_reclaims_the_slot_from_a_recovered_backup() -> void:
	var state := _first_steps_state()
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	_interrupt_a_swap()
	state.day = 11
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	assert_true(FileAccess.file_exists(TEST_PATH), "the slot is a save again")
	assert_false(FileAccess.file_exists(BACKUP_PATH), "the recovered copy is cleared, not kept")
	assert_false(FileAccess.file_exists(TEMP_PATH))
	var loaded := SaveGame.load_game(terrain_db, unit_db, chart, TEST_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.state.day, 11, "and it holds the newer match")


## COM-51. Every save but a match's first one replaces a slot that is already there,
## which is the branch the set-aside exists for and the one a save-once test never
## reaches: were the swap to refuse an occupied destination, or to leave its backup
## standing, only the first save of a match would behave.
func test_a_later_save_replaces_the_one_before_it() -> void:
	var state := _first_steps_state()
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH))
	state.day = 7
	state.funds[1] = 8000
	assert_true(SaveGame.save(state, [] as Array[int], TEST_PATH), "saving over a slot works")
	assert_false(FileAccess.file_exists(TEMP_PATH))
	assert_false(FileAccess.file_exists(BACKUP_PATH), "the set-aside copy is removed, not left")
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
