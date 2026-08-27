extends GutTest
## The named home for ArenaLeaderboard regressions: `build()`'s ordering, and
## the two ways a run refuses to be read as a table (a pairing seen from one
## seat only, a pool a candidate never played). test_arena_fitness.gd already
## exercises the class in depth alongside the score it tallies; this file is
## where a future ArenaLeaderboard-only bug gets a test, discoverable by name.
##
## Node-free, so GUT tallies records without a process.

const RED := "data/ai/default.tres"
const BLUE := "data/ai/hard.tres"
const THIRD := "reports/ai_arena/gen1/c7.tres"
const BOARD := "scrimmage"
const HELD_OUT := "timberline"


func _record(
	map_name: String, index: int, seat: int, red: String, blue: String, winner: int
) -> Dictionary:
	return {
		"map": map_name,
		"seed": BalanceMatchSchedule.seed_at(map_name, index),
		"seat": seat,
		"red": red,
		"blue": blue,
		"winner": winner,
		"termination": "rout",
		"day_ended": 10,
		"rejected": 0,
		"cap_stall": false,
	}


## One matchup on one board at one seed, played from both seats, `red` winning
## each time — the shape a pairing must have to be reportable at all.
func _both_seats(map_name: String, red: String, blue: String, index: int) -> Array:
	var played: Array = []
	for seat in 2:
		var swapped := seat == 1
		played.append(
			_record(
				map_name,
				index,
				seat,
				blue if swapped else red,
				red if swapped else blue,
				ArenaFitness.BLUE_TEAM if swapped else ArenaFitness.RED_TEAM
			)
		)
	return played


## A small, fully-seated set of records orders the stronger candidate first,
## both a leader over a loser and a leader over a candidate it never met (a
## row's mean stands on its own pools, not on head-to-head play).
func test_build_orders_a_small_set_of_records() -> void:
	var records: Array = []
	records.append_array(_both_seats(BOARD, RED, BLUE, 0))
	records.append_array(_both_seats(BOARD, RED, BLUE, 1))
	var board := ArenaLeaderboard.build(records)
	assert_eq(board.problem(), "")
	assert_eq(board.rows.size(), 2)
	assert_eq(board.rows[0].candidate, RED, "won every match played")
	assert_gt(board.rows[0].mean(ArenaPools.TRAINING), board.rows[1].mean(ArenaPools.TRAINING))


## A malformed record is refused by name, and a pairing missing its mirrored
## seat is refused the same way — the run cannot be read as a leaderboard
## either way, because the seat can never cancel without both halves.
func test_a_half_seated_pairing_and_a_malformed_record_are_both_refused() -> void:
	var one_seat := [_record(BOARD, 0, 0, RED, BLUE, ArenaFitness.RED_TEAM)]
	var board := ArenaLeaderboard.build(one_seat)
	assert_string_contains(board.problem(), "one seat only")
	assert_eq(board.unpaired.size(), 1)

	var complete := _record(BOARD, 0, 0, RED, BLUE, ArenaFitness.RED_TEAM)
	assert_eq(ArenaLeaderboard.record_error(complete), "", "a full record reads clean")
	assert_string_contains(ArenaLeaderboard.record_error("not a dictionary"), "is an object")
	var short := complete.duplicate()
	short.erase("seat")
	assert_string_contains(ArenaLeaderboard.record_error(short), "seat")


## A mirror is a candidate against itself: the Balance Lab plays it from one
## seat on purpose to measure what the seat is worth, so it is refused by name
## rather than counted as a run that lost half its seatings.
func test_a_mirror_is_refused_as_a_calibration_not_as_a_missing_seat() -> void:
	var records: Array = []
	for seat in 2:
		records.append(_record(BOARD, 0, seat, RED, RED, ArenaFitness.RED_TEAM))
	var board := ArenaLeaderboard.build(records)
	assert_eq(board.mirrored.size(), 1)
	assert_true(board.unpaired.is_empty(), "a mirror is not a half-seated pairing")
	assert_string_contains(board.problem(), "against itself")
	assert_string_contains(board.problem(), "calibration")
	assert_eq(board.to_dict()["mirrored"], board.mirrored)


## A mirror-free run says nothing about mirrors: the report's JSON is what it
## always was, so an existing leaderboard.json is byte-identical.
func test_a_mirror_free_run_reports_no_mirror_key() -> void:
	var board := ArenaLeaderboard.build(_both_seats(BOARD, RED, BLUE, 0))
	assert_true(board.mirrored.is_empty())
	assert_false(board.to_dict().has("mirrored"))


## A candidate that never played the held-out pool is an absent measurement,
## never a mean of zero — standing zero in would sort it above a candidate that
## met the held-out boards and lost, which is the exact inversion the held-out
## reading exists to catch (plan D7/R1).
func test_a_pool_a_candidate_never_played_is_uncovered_not_scored() -> void:
	var records: Array = []
	records.append_array(_both_seats(BOARD, RED, BLUE, 0))
	records.append_array(_both_seats(HELD_OUT, RED, THIRD, ArenaPools.VALIDATION_OFFSET))
	var board := ArenaLeaderboard.build(records)
	assert_true(board.unpaired.is_empty(), "every pairing here was played from both seats")
	assert_string_contains(board.problem(), "never played a pool")
	assert_eq(
		board.uncovered,
		["%s in %s" % [BLUE, ArenaPools.VALIDATION], "%s in %s" % [THIRD, ArenaPools.TRAINING]]
	)
	var ranked: Array = board.to_dict()["ranked_on"]
	assert_true(ranked.is_empty(), "an unreadable run orders nothing")
