extends GutTest
## Per-seat difficulty (COM-225): a four-army board may be one Easy opponent and
## two Difficult ones, rather than one tier for every computer at the table.
##
## Kept apart from test_match_request.gd for the reason its siblings
## test_seats_flag.gd and test_sides_flag.gd are: that file sits at the gdlintrc
## max-public-methods ceiling. Same shape as them too — the words the flag says,
## then what `BattleSetup` builds out of them, both without a scene.

const FOUR_ARMY_BOARD := "res://maps/compass.txt"
const TEST_PATH := "user://test_seat_difficulty.json"


func _built(request: MatchRequest) -> BattleSetup.BuiltMatch:
	return BattleSetup.build(
		request, Fixture.terrain_db(), Fixture.unit_db(), CommanderDB.load_default(), TEST_PATH
	)


## A four-army board with the last three seats played by the computer.
func _four_army_request() -> MatchRequest:
	return MatchRequest.from_menu(
		FOUR_ARMY_BOARD, [2, 3, 4] as Array[int], false, Difficulty.DEFAULT_ID, {}, false
	)


func after_each() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


# --- the words ----------------------------------------------------------------


## The flag's old meaning is its whole meaning until a seat is named: every
## computer seat, which is what every scenario, doc and balance row still says.
func test_a_plain_difficulty_flag_still_means_every_computer_seat() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--difficulty=hard"]))
	assert_eq(request.difficulty, &"hard")
	assert_true(request.seat_difficulty.is_empty(), "and tunes no seat on its own")


func test_a_seat_may_be_named_a_tier_of_its_own() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--difficulty=2:hard,4:easy"]))
	assert_eq(request.seat_difficulty, {2: &"hard", 4: &"easy"})
	assert_eq(request.difficulty, Difficulty.DEFAULT_ID, "the match's own tier is left alone")


func test_a_table_wide_tier_and_a_seat_may_be_written_together() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--difficulty=easy,2:brutal"]))
	assert_eq(request.difficulty, &"easy", "everyone")
	assert_eq(request.seat_difficulty, {2: &"brutal"}, "except this one")


## An empty flag is not an absent one — it clears the tier the menu picked, the
## same way `--co=` clears its commanders.
func test_an_empty_difficulty_flag_still_clears_the_tier() -> void:
	var request := MatchRequest.new()
	request.difficulty = &"hard"
	request.apply_cmdline(Fixture.args(["--difficulty="]))
	assert_eq(request.difficulty, &"")


func test_an_entry_naming_no_seat_is_refused_out_loud() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--difficulty=red:hard"]))
	assert_true(request.seat_difficulty.is_empty(), "nothing guessed at")
	assert_push_error("names no seat")


# --- the adapters -------------------------------------------------------------


func test_the_menu_adapter_carries_the_per_seat_tiers() -> void:
	var request := MatchRequest.from_menu(
		FOUR_ARMY_BOARD, [2] as Array[int], false, &"normal", {}, false, {}, [], {2: &"brutal"}
	)
	assert_eq(request.seat_difficulty, {2: &"brutal"})


func test_the_rematch_adapter_replays_the_tiers_the_seats_were_played_at() -> void:
	var map := MapData.load_from_file(FOUR_ARMY_BOARD, Fixture.terrain_db())
	var game := GameState.create(map, Fixture.unit_db(), Fixture.chart())
	game.map_path = FOUR_ARMY_BOARD
	var request := MatchRequest.from_match(game, [2, 3] as Array[int], &"normal", {3: &"easy"})
	assert_eq(request.seat_difficulty, {3: &"easy"}, "a rematch is that match again")


# --- what gets built ----------------------------------------------------------


## The point of the whole ticket: two computers at one table, playing at two
## tiers, weighing their moves with two profiles.
func test_two_computer_seats_can_be_given_two_tiers() -> void:
	var request := _four_army_request()
	request.seat_difficulty = {2: &"easy", 3: &"brutal"}
	var built := _built(request)
	assert_not_null(built)
	assert_eq(built.per_team_difficulty[2].id, &"easy")
	assert_eq(built.per_team_difficulty[3].id, &"brutal")
	assert_eq(built.planners[2].profile, built.per_team_difficulty[2].profile())
	assert_eq(built.planners[3].profile, built.per_team_difficulty[3].profile())
	assert_ne(built.planners[2].profile, built.planners[3].profile, "two tiers, two profiles")


## A seat the launch names no tier for plays the match's own, which is what every
## match played before a seat could carry one.
func test_a_seat_with_no_tier_of_its_own_plays_the_match_tier() -> void:
	var request := _four_army_request()
	request.difficulty = &"hard"
	request.seat_difficulty = {2: &"easy"}
	var built := _built(request)
	assert_not_null(built)
	assert_false(built.per_team_difficulty.has(4))
	assert_eq(built.planners[4].profile, built.difficulty.profile(), "the match's tier")


## A tier for a seat the computer is not playing tunes a planner that never
## plans, so it is dropped rather than carried into the save and the rematch.
func test_a_tier_for_a_seat_nobody_computes_is_dropped() -> void:
	var request := _four_army_request()
	request.seat_difficulty = {1: &"brutal", 2: &"easy"}
	var built := _built(request)
	assert_not_null(built)
	assert_eq(built.seat_difficulty, {2: &"easy"} as Dictionary[int, StringName])


# --- across a save ------------------------------------------------------------


## A resumed match plays the tiers it was saved at: without them the hardest
## opponent at the table quietly drops to the match's own tier on the way back in.
func test_a_resumed_match_keeps_each_seat_at_its_own_tier() -> void:
	var map := MapData.load_from_file(FOUR_ARMY_BOARD, Fixture.terrain_db())
	var state := GameState.create(map, Fixture.unit_db(), Fixture.chart())
	state.map_path = FOUR_ARMY_BOARD
	var seat_tiers: Dictionary[int, StringName] = {3: &"brutal"}
	assert_true(
		SaveGame.save(state, [2, 3] as Array[int], TEST_PATH, &"easy", {}, seat_tiers),
		"the match goes to disk with its seats' tiers"
	)
	var request := _four_army_request()
	request.resume = true
	var built := _built(request)
	assert_not_null(built)
	assert_eq(built.difficulty.id, &"easy", "the match's own tier, as before")
	assert_eq(built.seat_difficulty, seat_tiers)
	assert_eq(built.per_team_difficulty[3].id, &"brutal")
	assert_ne(built.planners[3].profile, built.planners[2].profile)


## Every save written before a seat could carry a tier resumes with its computer
## seats on the one tier it records — the match those saves actually played.
func test_a_save_older_than_per_seat_tiers_resumes_on_one_tier() -> void:
	var map := MapData.load_from_file(FOUR_ARMY_BOARD, Fixture.terrain_db())
	var state := GameState.create(map, Fixture.unit_db(), Fixture.chart())
	state.map_path = FOUR_ARMY_BOARD
	var data := SaveCodec.encode(state, [2, 3] as Array[int], &"hard")
	data.erase("seat_tiers")
	data["version"] = 10
	assert_eq(SaveCodec.validate(data), "", "version 10 knew no such key")
	var loaded := SaveCodec.decode(data, Fixture.terrain_db(), Fixture.unit_db(), Fixture.chart())
	assert_not_null(loaded)
	assert_true(loaded.seat_tiers.is_empty())
	assert_eq(loaded.difficulty, &"hard")


## A tier for a team the save does not hand to the computer describes a match it
## could not have recorded — the rule its Auto sibling already carries.
func test_a_seat_tier_for_a_team_not_played_by_the_computer_is_refused() -> void:
	var map := MapData.load_from_file(FOUR_ARMY_BOARD, Fixture.terrain_db())
	var state := GameState.create(map, Fixture.unit_db(), Fixture.chart())
	state.map_path = FOUR_ARMY_BOARD
	var data := SaveCodec.encode(state, [2] as Array[int], &"normal")
	data["seat_tiers"] = {"3": "brutal"}
	assert_string_contains(SaveCodec.validate(data), "a tier of its own")
