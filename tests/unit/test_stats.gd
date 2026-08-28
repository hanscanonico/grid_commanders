extends GutTest
## The arithmetic every offline instrument reads its sample with
## (`tools/balance/stats.gd`).
##
## It lived four times over and the two percentiles had drifted apart, so what
## this pins is each convention by name on a hand-worked sample: which rank a
## report is on is a fact about that report, and a committed reading moved onto
## the other rank is a different number.
##
## Node-free like the rest of `tools/balance/`, so no scene is built.

## Five values, deliberately out of order: nothing here may depend on the order a
## caller collected its sample in.
const SAMPLE: Array = [5, 1, 3, 2, 4]


## An empty sample reports 0.0 rather than dividing by nothing — the count a
## report prints beside it is what tells that apart from a real average.
func test_an_empty_sample_reads_as_zero() -> void:
	assert_eq(Stats.mean([]), 0.0)
	assert_eq(Stats.median([]), 0.0)
	assert_eq(Stats.nearest_rank([], 0.25), 0.0)
	assert_eq(Stats.floor_rank([], 0.9), 0.0)


func test_the_mean_answers_ints_and_floats_alike() -> void:
	assert_almost_eq(Stats.mean([1, 2, 6]), 3.0, 0.001)
	assert_almost_eq(Stats.mean([1.5, 2.5]), 2.0, 0.001, "floats too")


func test_the_median_sorts_first_and_averages_an_even_sample() -> void:
	assert_almost_eq(Stats.median([6, 1, 2]), 2.0, 0.001, "sorted before the middle")
	assert_almost_eq(Stats.median([1, 2, 3, 6]), 2.5, 0.001, "the two middles, averaged")
	assert_almost_eq(Stats.median(SAMPLE), 3.0, 0.001)


## `ceil(fraction * n) - 1`, clamped: 0.9 of five values is the fifth.
func test_the_nearest_rank_is_a_value_the_sample_really_holds() -> void:
	assert_almost_eq(Stats.nearest_rank(SAMPLE, 0.25), 2.0, 0.001)
	assert_almost_eq(Stats.nearest_rank(SAMPLE, 0.5), 3.0, 0.001)
	assert_almost_eq(Stats.nearest_rank(SAMPLE, 0.9), 5.0, 0.001)
	assert_almost_eq(Stats.nearest_rank(SAMPLE, 1.0), 5.0, 0.001, "the top")
	assert_almost_eq(Stats.nearest_rank(SAMPLE, 0.0), 1.0, 0.001, "clamped to the bottom")


## `floor(fraction * (n - 1))`: 0.9 of the same five values is the fourth.
func test_the_floor_rank_reads_the_lower_place() -> void:
	assert_almost_eq(Stats.floor_rank(SAMPLE, 0.25), 2.0, 0.001)
	assert_almost_eq(Stats.floor_rank(SAMPLE, 0.5), 3.0, 0.001)
	assert_almost_eq(Stats.floor_rank(SAMPLE, 0.9), 4.0, 0.001)
	assert_almost_eq(Stats.floor_rank(SAMPLE, 1.0), 5.0, 0.001, "the top")
	assert_almost_eq(Stats.floor_rank(SAMPLE, 0.0), 1.0, 0.001)


## The whole reason both are here and both are named. They agree at the ends and
## on a middle rank, and part company in the tail a clock is read by — which is
## why an instrument moving between them owes its document a fresh run.
func test_the_two_ranks_part_company_in_the_tail() -> void:
	var ten: Array = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
	assert_almost_eq(Stats.nearest_rank(ten, 0.95), 10.0, 0.001)
	assert_almost_eq(Stats.floor_rank(ten, 0.95), 9.0, 0.001)
	assert_almost_eq(Stats.nearest_rank(ten, 1.0), Stats.floor_rank(ten, 1.0), 0.001, "the top")
	assert_almost_eq(Stats.nearest_rank(ten, 0.0), Stats.floor_rank(ten, 0.0), 0.001, "the bottom")


## A caller's sample is the order it collected its values in, and nothing here
## may reorder it under them.
func test_reading_a_sample_leaves_it_in_the_order_it_arrived() -> void:
	var sample: Array = [5, 1, 3, 2, 4]
	Stats.median(sample)
	Stats.nearest_rank(sample, 0.5)
	Stats.floor_rank(sample, 0.5)
	assert_eq(sample, [5, 1, 3, 2, 4] as Array)
