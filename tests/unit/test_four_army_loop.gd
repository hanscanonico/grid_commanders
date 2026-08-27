extends GutTest
## The loop the two four-army instruments share (`tools/balance/four_army_loop.gd`).
##
## `tools/run_bulwark_measure.gd` and `tools/run_mobile_soak.gd` each carried a
## copy of it and the copies had drifted — one refused an illegal command out
## loud and counted it, the other swallowed it — so what this pins is the
## contract both drivers now read their reports off: the row `play` hands back,
## the callback the soak's clock hangs on, and the arithmetic and the refusal
## that came with them. Node-free like the rest of `tools/balance/`, so no scene
## is built.

## The four-army fixture the alliance soak plays: small enough to run a handful
## of days per test, seated for every grouping.
const FIXTURE := "res://maps/fixtures/quartet.txt"
## A few days is enough for four planners to build, move and end turns, which is
## all these assertions read.
const DAYS := 3
## A caller's own list of what `--grouping` takes, which the refusal quotes back.
const OPTIONS := "ffa or a grouping like 1+2+3v4"

var _harness: BalanceHarness
var _map: MapData
var _profile: AIProfile


func before_each() -> void:
	_harness = BalanceHarness.new()
	_harness.unit_db = Fixture.unit_db()
	_harness.chart = Fixture.chart()
	_map = MapData.load_from_file(FIXTURE, Fixture.terrain_db())
	_profile = AIProfile.new()


func _play(seed_val: int, on_command: Callable = Callable()) -> Dictionary:
	var sides: Dictionary[int, int] = {}
	return FourArmyLoop.play(
		_map, _harness, _profile, sides, seed_val, DAYS, "free-for-all", on_command
	)


## The row a report is written from, and the claim the whole extraction rests
## on: the shipped board issues no command the rules refuse.
func test_a_played_match_reports_its_commands_and_refuses_nothing() -> void:
	var played := _play(7)
	assert_false(played.is_empty(), "the fixture seats four armies")
	assert_gt(played["commands"], 0, "the planners issued commands")
	assert_eq(played["rejected"], 0, "no command the rules turned down")
	assert_eq(played["turn_cap_hits"], 0, "no turn ran into the per-turn cut")
	assert_eq(played["cap_stall"], 0, "the day advanced")
	var state: GameState = played["state"]
	assert_eq(state.teams.size(), 4, "four armies played")


## The soak reads its clock off this callback, so it has to fire once per
## command applied — no more (a swallowed rejection would double-count) and no
## fewer — and end-of-turn has to be visible in it, or a turn total is never
## banked.
func test_the_callback_fires_once_per_command_and_names_the_turn_boundary() -> void:
	var calls: Array[int] = []
	# A lambda captures a local by value, so the turn count is banked in an array
	# the closure and this test share.
	var turns: Array[int] = [0]
	var clock := func(spent_usec: int, ends_turn: bool) -> void:
		calls.append(spent_usec)
		if ends_turn:
			turns[0] += 1
	var played := _play(7, clock)
	assert_eq(calls.size(), played["commands"], "one call per issued command")
	assert_gt(turns[0], 0, "at least one turn ended")
	for spent in calls:
		assert_gte(spent, 0, "the planning time handed over is a duration")


## Same seed, same match — the property every number both instruments publish
## rests on.
func test_the_same_seed_replays_the_same_match() -> void:
	var first := _play(11)
	var second := _play(11)
	assert_eq(first["commands"], second["commands"], "the same commands were issued")
	var a: GameState = first["state"]
	var b: GameState = second["state"]
	assert_eq(a.day, b.day, "the same day")
	assert_eq(a.winner, b.winner, "the same verdict")


## A refusal is loud and it names the caller's own alternatives, a driver with a
## preset of its own offering more of them than the shared loop knows about.
func test_a_grouping_is_read_or_refused_out_loud() -> void:
	assert_true(FourArmyLoop.grouping_readable("t", "ffa", OPTIONS))
	assert_true(FourArmyLoop.grouping_readable("t", "1+2+3v4", OPTIONS))
	assert_true(FourArmyLoop.grouping_readable("t", "1v2", OPTIONS))
	assert_false(FourArmyLoop.grouping_readable("t", "north v south", OPTIONS))
	assert_push_error("t: --grouping is %s (got 'north v south')" % OPTIONS)
	assert_false(FourArmyLoop.grouping_readable("t", "alliance", OPTIONS))
	assert_push_error("t: --grouping is %s (got 'alliance')" % OPTIONS)


## An empty sample reports 0.0 rather than dividing by nothing — the count a
## report prints beside it is what tells that apart from a real average.
func test_the_arithmetic_reads_an_empty_sample_as_zero() -> void:
	assert_eq(FourArmyLoop.mean([]), 0.0)
	assert_eq(FourArmyLoop.median([]), 0.0)


func test_the_mean_and_median_answer_both_sample_sizes() -> void:
	assert_almost_eq(FourArmyLoop.mean([1, 2, 6]), 3.0, 0.001)
	assert_almost_eq(FourArmyLoop.median([6, 1, 2]), 2.0, 0.001, "sorted before the middle")
	assert_almost_eq(FourArmyLoop.median([1, 2, 3, 6]), 2.5, 0.001, "the two middles, averaged")
	assert_almost_eq(FourArmyLoop.mean([1.5, 2.5]), 2.0, 0.001, "floats too")
