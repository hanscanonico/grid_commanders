class_name Stats
extends RefCounted
## The arithmetic every offline instrument reads a sample with. It lived four
## times over — a median in `FourArmyLoop`, another in `LegibilityMetric`, a
## third in `tools/run_campaign_difficulty.gd` — and the two percentiles had
## drifted into two different ranks, so two committed reports said "the p95"
## meaning two different numbers.
##
## The two ranks are both here and both named, because which one a report is on
## is a fact about that report rather than a preference: `nearest_rank` returns a
## value the sample really holds at `ceil(fraction * n)`, and `floor_rank` the
## one at `floor(fraction * (n - 1))`. A committed reading is on exactly one of
## them, so moving an instrument between the two owes a regenerated document.
##
## Node-free like the rest of `tools/balance/`. An empty sample reports 0.0 —
## the count a report prints beside it is what tells that apart from a real
## average.


static func mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


## The middle of the sorted sample, an even one averaging its two middles.
## Sorts a copy: a caller's sample is the order it collected its values in and
## nothing may depend on that.
static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[middle])
	return 0.5 * (float(sorted[middle - 1]) + float(sorted[middle]))


## The value `fraction` of the way through the sorted sample by nearest rank —
## never an interpolation between two, so the number reported is one the sample
## really holds. `docs/sprite_legibility.md`'s edge readings are this rank.
static func nearest_rank(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var rank := clampi(ceili(fraction * float(sorted.size())) - 1, 0, sorted.size() - 1)
	return float(sorted[rank])


## The same reading taken at `floor(fraction * (n - 1))` — a lower rank than
## `nearest_rank` on almost every sample size. `docs/mobile_soak.md`'s planner
## clock is this rank.
static func floor_rank(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var rank := clampi(int(floor(fraction * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return float(sorted[rank])
