extends GutTest
## Seating an arbitrary candidate: the profile loader, and the records a shard
## hands back.
##
## The loader's refusals carry the milestone: a path that quietly fell back to
## the shipped defaults would measure the very tier the arena exists to beat, and
## nothing downstream could tell. The records are checked against the engine
## itself rather than against a transcription of them, because "the arena and the
## Lab play the same matches" is only true while the arena adds no schedule and
## no loop of its own.

const MAP := "clash"
const DEFAULT_PROFILE := "data/ai/default.tres"
const HARD_PROFILE := "data/ai/hard.tres"
## Short enough to play a handful of times in a suite; long enough that both
## sides act.
const DAYS := 4

var shard: ArenaShard
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	shard = ArenaShard.new(TerrainDB.load_default(), unit_db, chart)


func _pairing(red: String, blue: String, seeds: int = 1) -> ArenaRequest.Pairing:
	var args := PackedStringArray(
		[
			"--map=%s" % MAP,
			"--red-profile=%s" % red,
			"--blue-profile=%s" % blue,
			"--seeds=%d" % seeds,
			"--days=%d" % DAYS,
		]
	)
	var pairings: Array = ArenaRequest.parse(args).pairings("")
	return pairings[0]


# --- the profile loader ----------------------------------------------------------


func test_a_candidate_is_loaded_from_its_path() -> void:
	var profile := shard.profile(HARD_PROFILE)
	assert_not_null(profile)
	assert_eq(shard.error, "")
	assert_eq(profile, load("res://%s" % HARD_PROFILE), "res:// is the same file, spelled twice")
	assert_eq(shard.profile("res://%s" % HARD_PROFILE), profile)


func test_a_path_that_names_nothing_is_refused() -> void:
	assert_null(shard.profile("data/ai/champion.tres"))
	assert_string_contains(shard.error, "champion.tres")


func test_a_resource_that_is_not_a_profile_is_refused() -> void:
	# A difficulty tier is a resource that loads perfectly well and is not a
	# candidate. Handing one over used to be unsayable; now it has to be caught.
	assert_null(shard.profile("data/difficulty/normal.tres"))
	assert_string_contains(shard.error, "not an AIProfile")


func test_a_path_outside_the_project_is_refused() -> void:
	assert_null(shard.profile("/etc/hosts"))
	assert_string_contains(shard.error, "outside the project")


func test_an_unknown_board_is_refused() -> void:
	assert_null(shard.board("atlantis"))
	assert_string_contains(shard.error, "unknown map")


# --- the records -----------------------------------------------------------------


func test_a_pairing_is_played_from_both_seats_on_the_schedule_s_seeds() -> void:
	var records := shard.play([_pairing(DEFAULT_PROFILE, HARD_PROFILE, 2)])
	assert_eq(shard.error, "")
	assert_eq(records.size(), 4, "two seeds, both seatings")
	var expected := BalanceMatchSchedule.seed_at(MAP, 0)
	assert_eq(int(records[0]["seed"]), expected, "the seed the Lab would have played")
	assert_eq(int(records[0]["seat"]), 0)
	assert_eq(int(records[1]["seat"]), 1)
	assert_eq(records[0]["red"], DEFAULT_PROFILE)
	assert_eq(records[1]["red"], HARD_PROFILE, "the seat swap is who sits where")
	assert_eq(records[1]["blue"], DEFAULT_PROFILE)


func test_a_record_carries_the_outcome_the_engine_played() -> void:
	var pairing := _pairing(DEFAULT_PROFILE, HARD_PROFILE)
	var records := shard.play([pairing])
	assert_eq(records.size(), 2)
	var record: Dictionary = records[0]

	var setup := BalanceMatchEngine.Setup.new()
	setup.map = shard.board(MAP)
	setup.unit_db = unit_db
	setup.chart = chart
	setup.seed_val = int(record["seed"])
	setup.days_cap = DAYS
	setup.commanders = {1: CommanderType.neutral(), 2: CommanderType.neutral()}
	setup.planners = {
		1: AIController.new(setup.unit_db, shard.profile(DEFAULT_PROFILE)),
		2: AIController.new(setup.unit_db, shard.profile(HARD_PROFILE)),
	}
	var outcome := BalanceMatchEngine.play(setup)

	assert_eq(int(record["winner"]), outcome.winner)
	assert_eq(record["termination"], outcome.termination)
	assert_eq(int(record["day_ended"]), outcome.day_ended)
	assert_eq(int(record["commands"]), outcome.commands)
	assert_eq(int(record["rejected"]), outcome.rejected)
	assert_eq(bool(record["cap_stall"]), outcome.cap_stall)
	assert_eq(int(record["turn_cap_hits"]), outcome.turn_cap_hits)
	assert_eq(int(record["red_units"]), outcome.state.units_of(1).size())
	assert_eq(int(record["blue_props"]), outcome.state.properties_of(2).size())
	assert_eq(
		int(record["red_army_value"]),
		BalanceMatchEngine.army_value(outcome.state, 1),
		"the margin a fitness function ranks on"
	)


func test_a_candidate_against_itself_is_played_once() -> void:
	var records := shard.play([_pairing(DEFAULT_PROFILE, DEFAULT_PROFILE, 2)])
	assert_eq(records.size(), 2, "one seating per seed: the swap replays the same match")
	for record in records:
		assert_eq(int(record["seat"]), 0)


func test_a_pairing_nobody_can_play_stops_the_shard() -> void:
	var records := shard.play([_pairing(DEFAULT_PROFILE, "data/ai/champion.tres")])
	assert_true(records.is_empty(), "a skipped pairing would score over fewer matches")
	assert_ne(shard.error, "")


func test_a_flawed_match_is_counted_rather_than_scored() -> void:
	# What counts as one is `ArenaFitness`'s to say, so the run's exit code and
	# the leaderboard's `invalid` count cannot drift apart.
	assert_eq(ArenaShard.flawed([_outcome("rout", 0, false)] as Array[Dictionary]), 0)
	assert_eq(ArenaShard.flawed([_outcome("day_cap", 0, false)] as Array[Dictionary]), 0)
	assert_eq(ArenaShard.flawed([_outcome("rout", 1, false)] as Array[Dictionary]), 1)
	assert_eq(ArenaShard.flawed([_outcome("command_cap", 0, true)] as Array[Dictionary]), 1)


func _outcome(termination: String, rejected: int, cap_stall: bool) -> Dictionary:
	return {"termination": termination, "rejected": rejected, "cap_stall": cap_stall}
