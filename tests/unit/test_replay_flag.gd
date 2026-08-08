extends GutTest
## The `--replay=user://replays/a.jsonl` grammar: which recording this launch is a
## viewing of, and whether it is a viewing at all.
##
## Kept apart from test_match_request.gd because that file sits at the gdlintrc
## max-public-methods ceiling — the same split, for the same reason, as its siblings
## test_seats_flag.gd and test_sides_flag.gd. Same subject, same shape: a pure
## answer over a flag list, checked without a scene.
##
## The flag has two facts, not one: the path, and whether a replay was *asked for*.
## `BattleSetup` reads the second — a viewing that named no file is refused out
## loud rather than quietly played as an ordinary match on the default board.


func test_replay_names_a_recording_to_watch() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--replay=  user://replays/a.jsonl  "]))
	assert_eq(request.replay_path, "user://replays/a.jsonl", "trimmed, not resolved")
	assert_true(request.replay_requested, "and this launch is a viewing")


## `make replay` with no `REPLAY=` passes exactly this, and a launch that fell
## back to an ordinary match on the default board would look just like the replay
## working. The flag is still a viewing; naming no file is what BattleSetup
## refuses.
func test_an_empty_replay_flag_still_asks_for_a_replay() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--replay="]))
	assert_eq(request.replay_path, "")
	assert_true(request.replay_requested)


func test_a_launch_naming_no_replay_is_not_a_viewing() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--fog"]))
	assert_false(request.replay_requested)


## The two look alike from the outside and are opposite instruments (replay plan
## D7): `--watch` re-plans a Balance Lab row from its seed and must keep diverging
## when the AI changes, and a replay cannot diverge because the decisions are in
## the file. Naming both is what a headless check of a recording does, so neither
## may quietly turn off the other.
func test_replay_and_watch_are_two_flags_not_one() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--replay=user://replays/a.jsonl", "--watch"]))
	assert_eq(request.replay_path, "user://replays/a.jsonl")
	assert_true(request.watching)
	var watched := MatchRequest.new()
	watched.apply_cmdline(Fixture.args(["--watch"]))
	assert_eq(watched.replay_path, "", "watch mode alone replays nothing off disk")
