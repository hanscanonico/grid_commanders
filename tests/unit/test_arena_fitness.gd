extends GutTest
## What "better" means: the per-match score, and the tally that turns scored
## matches into a leaderboard.
##
## The three properties the whole instrument rests on are pinned here — the
## class ordering (a decisive win beats an unresolved match beats a loss), the
## zero-sum shape that makes the seat cancel when both seatings are counted, and
## the refusal to report a pairing that was played from one seat only.

const RED := "data/ai/default.tres"
const BLUE := "data/ai/hard.tres"
## A training board and its first seed, so a record lands in a pool without the
## test restating the split.
const BOARD := "scrimmage"


func _seed_at(index: int) -> int:
	return BalanceMatchSchedule.seed_at(BOARD, index)


func _record(
	winner: int, termination: String, day: int, seat: int = 0, index: int = 0
) -> Dictionary:
	var swapped := seat == 1
	return {
		"map": BOARD,
		"seed": _seed_at(index),
		"seat": seat,
		"red": BLUE if swapped else RED,
		"blue": RED if swapped else BLUE,
		"winner": winner,
		"termination": termination,
		"day_ended": day,
		"rejected": 0,
		"cap_stall": false,
	}


# --- the score -------------------------------------------------------------------


func test_a_decisive_win_is_worth_a_point_and_a_half_at_most() -> void:
	var quick := _record(1, "rout", 1)
	assert_almost_eq(ArenaFitness.score(quick, 1), 1.495, 0.001, "a win on day one")
	var slow := _record(1, "rout", 100)
	assert_almost_eq(ArenaFitness.score(slow, 1), 1.0, 0.001, "a win at the horizon")


func test_the_loser_scores_exactly_the_negative_of_the_winner() -> void:
	# Zero-sum is what makes counting both seatings cancel the seat instead of
	# reporting it, so it is a property rather than a coincidence of the weights.
	for day: int in [3, 17, 64, 100]:
		var record := _record(2, "hq", day)
		assert_almost_eq(ArenaFitness.score(record, 1) + ArenaFitness.score(record, 2), 0.0, 0.0001)


func test_an_earlier_win_outranks_a_later_one() -> void:
	assert_gt(
		ArenaFitness.score(_record(1, "rout", 12), 1),
		ArenaFitness.score(_record(1, "rout", 40), 1),
		"speed grades inside the decisive class"
	)


func test_a_win_at_the_horizon_still_outranks_every_unresolved_match() -> void:
	# The base has to dominate the speed term, or the gradient underneath the
	# ordering would invert the ordering the game cares about.
	assert_gt(
		ArenaFitness.score(_record(1, "rout", ArenaFitness.HORIZON), 1),
		ArenaFitness.score(_record(1, "day_cap", 20), 1)
	)
	assert_gt(
		ArenaFitness.score(_record(1, "day_cap", 20), 1),
		ArenaFitness.score(_record(2, "rout", 3), 1),
		"and an unresolved match still outranks a loss"
	)


func test_the_day_cap_tiebreak_never_reaches_the_score() -> void:
	# The engine fills `winner` in from properties, then units, then funds when a
	# match runs out of days. Scoring that pays whoever hoards better (D6), so
	# both sides get nothing whatever it says.
	var record := _record(1, "day_cap", 100)
	assert_eq(ArenaFitness.result_of(record), ArenaFitness.Result.UNRESOLVED)
	assert_eq(ArenaFitness.score(record, 1), 0.0)
	assert_eq(ArenaFitness.score(record, 2), 0.0)


func test_a_match_the_rules_disagreed_with_is_not_a_result() -> void:
	var rejected := _record(1, "rout", 10)
	rejected["rejected"] = 1
	assert_eq(ArenaFitness.result_of(rejected), ArenaFitness.Result.INVALID)
	assert_eq(ArenaFitness.score(rejected, 1), 0.0)
	var stalled := _record(0, "command_cap", 100)
	stalled["cap_stall"] = true
	assert_eq(ArenaFitness.result_of(stalled), ArenaFitness.Result.INVALID)


# --- the leaderboard ---------------------------------------------------------------


func test_both_seatings_of_two_identical_vectors_score_level() -> void:
	# The measured +50 pp first-seat edge on a mirror, cancelled rather than
	# reported: the same match is played from both seats, red wins both, and each
	# candidate holds the winning seat exactly once.
	var board := ArenaLeaderboard.build([_record(1, "rout", 9, 0), _record(1, "rout", 9, 1)])
	assert_eq(board.problem(), "")
	assert_eq(board.rows.size(), 2)
	for row: ArenaLeaderboard.Row in board.rows:
		assert_almost_eq(row.mean(ArenaPools.TRAINING), 0.0, 0.0001, row.candidate)
		assert_eq(row.pools[ArenaPools.TRAINING].wins, 1)
		assert_eq(row.pools[ArenaPools.TRAINING].losses, 1)


func test_a_pairing_played_from_one_seat_only_is_refused() -> void:
	# The Lab plays a mirror from one seat on purpose and that reading is a bias
	# measurement. A leaderboard built on it would credit whichever side drew the
	# first seat, which is exactly what D5 forbids.
	var board := ArenaLeaderboard.build([_record(1, "rout", 9, 0)])
	assert_string_contains(board.problem(), "one seat only")
	assert_eq(board.unpaired.size(), 1)


func test_a_candidate_is_tallied_in_the_pool_it_played() -> void:
	var records: Array = [
		_record(1, "rout", 10, 0, 0),
		_record(1, "rout", 10, 1, 0),
		_record(1, "rout", 30, 0, 500),
		_record(1, "rout", 30, 1, 500),
	]
	var board := ArenaLeaderboard.build(records)
	var row: ArenaLeaderboard.Row = board.rows[0]
	assert_eq(row.matches(ArenaPools.TRAINING), 2, "the pool's own seeds")
	assert_eq(row.matches(ArenaPools.OFF_POOL), 2, "and a seed outside it, counted apart")


func test_an_invalid_match_is_counted_and_never_scored() -> void:
	var broken := _record(1, "rout", 10, 0)
	broken["cap_stall"] = true
	var board := ArenaLeaderboard.build([broken, _record(1, "rout", 10, 1)])
	assert_eq(board.invalid, 1)
	assert_string_contains(board.problem(), "would not resolve")
	for row: ArenaLeaderboard.Row in board.rows:
		assert_eq(row.matches(ArenaPools.TRAINING), 1, "only the sound match was tallied")


func test_the_stronger_candidate_leads_the_table() -> void:
	var records: Array = []
	for index in 3:
		records.append(_record(2, "rout", 10, 0, index))
		records.append(_record(1, "rout", 10, 1, index))
	var board := ArenaLeaderboard.build(records)
	assert_eq(board.rows[0].candidate, BLUE, "won every match from either seat")
	assert_gt(board.rows[0].mean(ArenaPools.TRAINING), 0.0)
	assert_lt(board.rows[1].mean(ArenaPools.TRAINING), 0.0)
