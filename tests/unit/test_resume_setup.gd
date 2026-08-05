extends GutTest
## The resume boundary: what `BattleSetup.build` does with a request that asked to
## continue a saved match.
##
## Three cases, and the middle one is what COM-121 added: a save that loads is the
## match, a save that will not load is a refusal, and no save at all is the fresh
## match the request also states. The middle used to fall through onto the last,
## which starts a match on whatever board the request happened to carry — the
## player asked for Day 12 and got day one somewhere else, silently.
##
## Reachable without a scene like its siblings test_seats_flag.gd and
## test_sides_flag.gd: `BattleSetup` is Node-free, and the slot it reads is a
## defaulted argument, so these name their own file rather than the player's.

const TEST_PATH := "user://test_resume_setup.json"
const FIRST_STEPS := "res://maps/first_steps.txt"
const SCRIMMAGE := "res://maps/scrimmage.txt"
## A board no file answers to, which is what a save whose map was renamed or
## deleted holds: `summarize` reads the path off the envelope and never opens it,
## so such a save is named on the menu and refused by `decode`.
const MISSING_BOARD := "res://maps/no_such_board.txt"

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


func _saved_match(map_path: String) -> void:
	var map := MapData.load_from_file(FIRST_STEPS, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = map_path
	state.day = 12
	assert_true(SaveGame.save(state, [2] as Array[int], TEST_PATH))


## The match a Continue press stages, built the way a boot builds it.
func _resumed() -> BattleSetup.BuiltMatch:
	var request := MatchRequest.from_menu(
		SCRIMMAGE, [2] as Array[int], false, Difficulty.DEFAULT_ID, {}, true
	)
	return BattleSetup.build(request, terrain_db, unit_db, CommanderDB.load_default(), TEST_PATH)


func test_a_resume_plays_the_saved_match() -> void:
	_saved_match(FIRST_STEPS)
	var built := _resumed()
	assert_not_null(built)
	assert_eq(built.game.day, 12)
	assert_eq(built.game.map_path, FIRST_STEPS, "the save's board, not the one the menu held")


## The save the menu named is real and unloadable, so there is no match to play.
## Building the fresh one the request also states hands the player a different
## match under the label of the one they asked for.
func test_a_resume_whose_save_cannot_be_read_refuses_the_match() -> void:
	_saved_match(MISSING_BOARD)
	assert_not_null(SaveGame.status(TEST_PATH).summary, "the menu could name it, so it is offered")
	assert_null(_resumed(), "and the boundary refuses it rather than starting something else")
	assert_push_error("cannot read map file")  # MapData, on the board the save names
	assert_push_error("the saved match cannot be read")


## A resume with nothing to resume is not damage: the request states a board too,
## and playing it is what every launch that found an empty slot has always done.
func test_a_resume_with_no_save_at_all_starts_the_fresh_match() -> void:
	assert_false(SaveGame.has_save(TEST_PATH))
	var built := _resumed()
	assert_not_null(built)
	assert_eq(built.game.map_path, SCRIMMAGE)
	assert_eq(built.game.day, 1)
