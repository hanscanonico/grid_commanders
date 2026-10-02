extends GutTest
## A launch that cannot be built: which refusals fall back to a board and which
## refuse outright, and the sentence the player is handed either way.
##
## `BattleSetup` is Node-free and the sentence it composes is a plain string on a
## `Failure`, so both halves are checkable without a scene. What the scene does
## with that sentence — the card on its own always-processing CanvasLayer — is
## presentation, verified by playing it.

## A board no file answers to, and deliberately not under `res://maps/campaign`:
## the campaign guard is a typed fact on the request, so a mission's board that
## was relocated or authored by hand must refuse exactly as an authored one does.
const MISSING_BOARD := "res://maps/no_such_board.txt"

## A duel that loads clean and seats nobody: a Cruiser parked on a field.
const STRANDED_HULL := """[terrain]
..........
.QB....BQ.
..........
..........
..........
[owners]
1 1 1
2 8 1
[units]
2 c 9 2
"""


func _built(request: MatchRequest, failure: BattleSetup.Failure) -> BattleSetup.BuiltMatch:
	return BattleSetup.build(
		request,
		Fixture.terrain_db(),
		Fixture.unit_db(),
		Fixture.commander_db(),
		SaveGame.SAVE_PATH,
		failure
	)


func _mission(map_path: String) -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.id = &"probe"
	mission.map_path = map_path
	return mission


## The skirmish half, unchanged: the launch asked for a match and any board is
## one, so a board that will not load is stood in for by the default.
func test_a_skirmish_falls_back_to_the_default_board() -> void:
	var request := MatchRequest.new()
	request.map_path = MISSING_BOARD
	var built := _built(request, null)
	assert_not_null(built, "the fallback still builds a match")
	assert_eq(built.game.map_path, MatchRequest.DEFAULT_MAP_PATH)
	assert_push_error("cannot read map file")  # MapData, on the board the request named
	assert_push_error("falling back to")


## The mission half. Its board, its objectives and its scripted beats are one
## authored thing, so a substituted board is a mission nobody wrote — which the
## player reports as an unwinnable mission rather than as a missing file.
func test_a_campaign_mission_refuses_a_board_it_cannot_load() -> void:
	var failure := BattleSetup.Failure.new()
	assert_null(_built(_mission(MISSING_BOARD).to_request(), failure))
	assert_string_contains(failure.message, "No Such Board", "and it names the board")
	assert_false(failure.message.contains("://"), "by its name, never its file")
	assert_push_error("cannot read map file")  # MapData, and no second read after it
	assert_push_error("cannot be loaded. (%s)" % MISSING_BOARD)


## A board that loads and still seats nobody — a hull on a field, saved before
## the editor refused one — says which board and why, not where its file is (ED-11).
func test_a_board_that_cannot_seat_says_why_by_name() -> void:
	var path := "user://test_launch_stranded_hull.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(STRANDED_HULL)
	file.close()
	var request := MatchRequest.new()
	request.map_path = path
	var failure := BattleSetup.Failure.new()
	assert_null(_built(request, failure))
	DirAccess.remove_absolute(path)
	assert_eq(
		failure.message,
		(
			"No match can be seated on Test Launch Stranded Hull. "
			+ "A Cruiser cannot stand on plains at (9, 2)."
		)
	)
	assert_push_error("cruiser cannot stand on plains")  # GameState
	assert_push_error("No match can be seated")


## The guard reads one fact, set by the one conversion — never the board's path.
func test_a_mission_launch_says_it_is_one() -> void:
	assert_true(_mission(MISSING_BOARD).to_request().campaign_mission)
	assert_false(MatchRequest.new().campaign_mission, "and a menu launch does not")


## The sentence exists for the export build, where `push_error` reaches only a
## log the player never opens. Every refusal fills it, so no launch can fail with
## a card that has nothing to say.
func test_every_refusal_composes_a_sentence() -> void:
	var failure := BattleSetup.Failure.new()
	var seatless := MatchRequest.new()
	seatless.seats = [7] as Array[int]
	assert_null(_built(seatless, failure), "a seating no board deals builds nothing")
	assert_false(failure.message.is_empty())
	assert_push_error("does not deal")  # GameState, on the seating it refused
	assert_push_error("No match can be seated")

	var replay := MatchRequest.from_replay("")
	failure = BattleSetup.Failure.new()
	assert_null(_built(replay, failure), "and neither does a --replay= naming no file")
	assert_false(failure.message.is_empty())
	assert_push_error("no match to play")
