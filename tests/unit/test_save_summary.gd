extends GutTest
## Naming a saved match without rebuilding it: SaveCodec's Summary and describe,
## and the SaveGame.peek that reads them off disk.
##
## Its own file rather than a section of the codec's, because the subject is one
## feature spread over both halves of the save layer — the pure read and the
## storage query the menu actually calls.

const TEST_PATH := "user://test_save_summary.json"
const FIRST_STEPS := "res://maps/first_steps.txt"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func after_each() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _first_steps_state(day: int = 1) -> GameState:
	var map := MapData.load_from_file(FIRST_STEPS, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = FIRST_STEPS
	state.day = day
	return state


# --- the summary itself -------------------------------------------------------


func test_summarize_reads_the_board_and_day_off_the_envelope() -> void:
	var data := SaveCodec.encode(_first_steps_state(7), [] as Array[int])
	var summary := SaveCodec.summarize(data)
	assert_not_null(summary)
	assert_eq(summary.day, 7)
	assert_eq(summary.map_path, FIRST_STEPS)


## A summary must never name a save the loader would then refuse: the menu uses
## it to decide whether Continue is offered at all.
func test_summarize_refuses_what_decode_refuses() -> void:
	var data := SaveCodec.encode(_first_steps_state(), [] as Array[int])
	data.erase("day")
	assert_null(SaveCodec.summarize(data))
	assert_null(SaveCodec.decode(data, terrain_db, unit_db, chart))
	assert_push_error("is missing 'day'")


func test_describe_names_the_match_the_way_the_map_picker_does() -> void:
	assert_eq(SaveCodec.describe(4, "res://maps/scrimmage.txt"), "Day 4 · Scrimmage")
	assert_eq(
		SaveCodec.describe(12, "res://maps/the_straits.txt"),
		"Day 12 · %s" % MapCatalog.display_name("res://maps/the_straits.txt"),
		"the board's name is MapCatalog's, never a second spelling of it"
	)


## The menu's Continue caption and the in-battle Saved banner are the same words,
## which is only true while both go through describe().
func test_summary_label_is_describe() -> void:
	var state := _first_steps_state(2)
	var summary := SaveCodec.summarize(SaveCodec.encode(state, [] as Array[int]))
	assert_eq(summary.label(), SaveCodec.describe(state.day, state.map_path))
	assert_eq(summary.label(), "Day 2 · First Steps")


# --- reading it off disk ------------------------------------------------------


func test_peek_names_the_saved_match() -> void:
	assert_true(SaveGame.save(_first_steps_state(4), [2] as Array[int], TEST_PATH))
	var summary := SaveGame.peek(TEST_PATH)
	assert_not_null(summary)
	assert_eq(summary.day, 4)
	assert_eq(summary.map_path, FIRST_STEPS)
	assert_eq(summary.label(), "Day 4 · First Steps")


## The menu asks this on every boot and having saved nothing is the ordinary
## answer, so unlike load_game it stays quiet about it.
func test_peek_returns_null_without_a_save() -> void:
	assert_false(SaveGame.has_save(TEST_PATH))
	assert_null(SaveGame.peek(TEST_PATH))


func test_peek_returns_null_for_a_file_that_is_not_a_save() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("this is not json")
	file.close()
	assert_null(SaveGame.peek(TEST_PATH))


func test_peek_returns_null_for_a_malformed_save() -> void:
	assert_true(SaveGame.save(_first_steps_state(), [] as Array[int], TEST_PATH))
	var text := FileAccess.get_file_as_string(TEST_PATH)
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text.replace('"fuel"', '"petrol"'))
	file.close()
	assert_null(SaveGame.peek(TEST_PATH), "a save Continue could not load must not be named")
