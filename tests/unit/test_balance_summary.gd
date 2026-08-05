extends GutTest
## The verdicts a balance run reports: which band a win rate falls in, how much
## the first seat is worth, how much of either to believe — and whether the
## difficulty ladder passed.
##
## Worth pinning because these are quoted as findings — docs/commander_balance.md
## and docs/difficulty_check.md read a WARN, a bias figure and a confidence note
## as the run's answer — while every one of them is a threshold comparison that
## can be off by one boundary and still look plausible on the page. The ladder's
## gate is the one that fails a build, and it used to live in a SceneTree runner
## where nothing could drive it at all.
##
## Node-free (a RefCounted under tools/balance/), so the boundaries are driven
## directly rather than inferred from a sweep.

## A decisive, resolved, non-mirror match row. Every test below states only what
## it is about and takes the rest from here, because the summary reads a dozen
## columns and spelling them out each time hides the one that matters.
const MATCH := {
	"match_id": "m1",
	"sweep_axis": "matchup",
	"sweep_value": "none-normal vs none-normal",
	"map": "clash",
	"seed": 1000,
	"seat": 0,
	"mirror": 0,
	"naval": 0,
	"subject_side": "red",
	"subject_won": 1,
	"winner": 1,
	"termination": "rout",
	"day_ended": 10,
	"rejected": 0,
	"cap_stall": 0,
}

const TIMELINE := {
	"match_id": "m1",
	"team": 1,
	"spent": 0,
	"built_value": 0,
	"captures": 0,
	"killed_value": 0,
	"lost_value": 0,
}


func _row(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var row := base.duplicate()
	for key: String in overrides:
		row[key] = overrides[key]
	return row


func _summary_of(matches: Array[Dictionary], timeline: Array[Dictionary] = []) -> Dictionary:
	return BalanceRunSummary.build({"label": "test"}, matches, timeline)


## The economy block of the one swept value MATCH belongs to.
func _economy_of(timeline: Array[Dictionary]) -> Dictionary:
	return _summary_of([MATCH] as Array[Dictionary], timeline)["values"][0]["economy"]


## `n` matches of one swept value, `wins` of them won by the first seat and the
## rest by the second — the shape every bias and band assertion below needs.
func _decisive(wins: int, losses: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in wins:
		rows.append(_row(MATCH, {"match_id": "red%d" % i, "winner": 1, "subject_won": 1}))
	for i in losses:
		rows.append(_row(MATCH, {"match_id": "blue%d" % i, "winner": 2, "subject_won": 0}))
	return rows


## The bands, at every edge. Both are inclusive of the band they name — 40.0 is
## not yet a WARN and 45.0 is already preferred — which is the half a reader
## cannot check against the document.
func test_band_flag_at_every_edge() -> void:
	var cases := {
		39.9: "WARN",
		40.0: "watch",
		44.9: "watch",
		45.0: "ok",
		55.0: "ok",
		55.1: "watch",
		60.0: "watch",
		60.1: "WARN",
	}
	for rate: float in cases:
		assert_eq(BalanceRunSummary.band_flag(rate), cases[rate], "%.1f%%" % rate)


## A mirror pairing is labelled for what it is rather than banded: with both
## sides identical the win rate is the first seat's, and banding it would mark
## every mirror board WARN for being a mirror.
func test_a_mirror_is_labelled_rather_than_banded() -> void:
	var rows: Array[Dictionary] = []
	for row in _decisive(9, 1):
		rows.append(_row(row, {"mirror": 1}))
	var summary := _summary_of(rows)
	var entry: Dictionary = summary["values"][0]
	assert_eq(entry["win_rate"], 90.0)
	assert_eq(entry["flag"], "mirror", "90% would be a WARN on any other run")
	assert_eq(BalanceRunSummary.band_flag(90.0), "WARN", "and the band itself still says so")


## The threshold is inclusive, and it is the one number that decides whether a
## reported bias is a finding. Reached through build() rather than by calling
## _bias_of directly: the private helper is what the report reads, but the
## summary dictionary is what a reader reads, so the boundary is asserted where
## it is published.
func test_first_seat_bias_is_within_threshold_at_exactly_the_threshold() -> void:
	var summary := _summary_of(_decisive(21, 19))
	var bias: Dictionary = summary["bias"]["overall"]
	assert_eq(bias["decisive"], 40)
	assert_almost_eq(float(bias["bias_pp"]), 5.0, 0.001)
	assert_true(bias["ok"], "exactly the threshold is still within it")

	var mirrored: Dictionary = _summary_of(_decisive(19, 21))["bias"]["overall"]
	assert_almost_eq(float(mirrored["bias_pp"]), -5.0, 0.001)
	assert_true(mirrored["ok"], "the threshold is two-sided")

	var over: Dictionary = _summary_of(_decisive(22, 18))["bias"]["overall"]
	assert_almost_eq(float(over["bias_pp"]), 10.0, 0.001)
	assert_false(over["ok"])


## A draw has no seat to credit, so it belongs in neither half of the bias and
## must not dilute the denominator either.
func test_a_draw_is_no_seats_win() -> void:
	var rows := _decisive(2, 1)
	rows.append(_row(MATCH, {"match_id": "drawn", "winner": 0, "subject_won": 0}))
	var summary := _summary_of(rows)
	assert_eq(summary["totals"]["draws"], 1)
	assert_eq(summary["totals"]["decisive"], 3)
	assert_eq(summary["bias"]["overall"]["decisive"], 3, "the draw is out of the denominator")


## Confidence is what says a value's ordering was settled on the board rather
## than by the day-cap tiebreak, which can turn over on noise (plan R2). At
## exactly the threshold it is still believed.
func test_confidence_at_the_resolved_threshold() -> void:
	var half: Array[Dictionary] = [
		_row(MATCH, {"match_id": "a", "termination": "rout"}),
		_row(MATCH, {"match_id": "b", "termination": "hq"}),
		_row(MATCH, {"match_id": "c", "termination": "day_cap"}),
		_row(MATCH, {"match_id": "d", "termination": "command_cap"}),
	]
	var entry: Dictionary = _summary_of(half)["values"][0]
	assert_almost_eq(float(entry["resolved_pct"]), BalanceRunSummary.MIN_RESOLVED_PCT, 0.001)
	assert_eq(entry["confidence"], "ok", "exactly the threshold is believed")

	var thinner: Array[Dictionary] = half.duplicate()
	thinner[1] = _row(MATCH, {"match_id": "b", "termination": "day_cap"})
	var low: Dictionary = _summary_of(thinner)["values"][0]
	assert_almost_eq(float(low["resolved_pct"]), 25.0, 0.001)
	assert_eq(low["confidence"], "low")


## The notes are the reading rules, emitted as data rather than left in a
## document nobody has open — so a low-confidence value has to be named in one.
func test_a_low_confidence_value_is_named_in_a_note() -> void:
	var rows: Array[Dictionary] = [
		_row(MATCH, {"match_id": "a", "sweep_value": "shaky", "termination": "day_cap"}),
		_row(MATCH, {"match_id": "b", "sweep_value": "shaky", "termination": "day_cap"}),
	]
	var notes: Array = _summary_of(rows)["notes"]
	var text := "\n".join(notes)
	assert_string_contains(text, "Low confidence")
	assert_string_contains(text, "shaky")


## The two hard invariants: a rejected command means the planner and the rules
## disagree, a cap stall means a match that will not resolve. Either one fails
## the run, and the note says to fix it before reading anything else.
func test_a_rejected_command_or_a_stall_fails_the_run() -> void:
	assert_true(_summary_of(_decisive(1, 1))["totals"]["invariants_clean"])
	var rejected := _summary_of([_row(MATCH, {"rejected": 2})] as Array[Dictionary])
	assert_false(rejected["totals"]["invariants_clean"])
	assert_eq(rejected["totals"]["total_rejected"], 2)
	assert_string_contains(String(rejected["notes"][0]), "before reading anything else")
	var stalled := _summary_of([_row(MATCH, {"cap_stall": 1})] as Array[Dictionary])
	assert_false(stalled["totals"]["invariants_clean"])
	assert_eq(stalled["totals"]["total_cap_stalls"], 1)


## Kills and losses are read from *both* sides' timeline rows, because a row
## records what happened during that side's turn: my unit shot down on the
## opponent's turn is in their `killed`, not in my `lost`. Summing one side's
## columns alone compares my kills against my counter-fire deaths, which is not
## an exchange ratio at all.
func test_the_exchange_ratio_reads_both_sides_of_the_timeline() -> void:
	var timeline: Array[Dictionary] = [
		_row(
			TIMELINE,
			{"team": 1, "spent": 1000, "built_value": 800, "killed_value": 50, "lost_value": 10}
		),
		_row(TIMELINE, {"team": 2, "spent": 9999, "killed_value": 30, "lost_value": 20}),
	]
	var economy := _economy_of(timeline)
	assert_eq(economy["spent"], 1000, "the opponent's spending is not the subject's")
	assert_eq(economy["killed_value"], 70, "50 on my turn plus 20 that died attacking me")
	assert_eq(economy["lost_value"], 40, "10 on my turn plus 30 killed on theirs")
	assert_almost_eq(float(economy["exchange_ratio"]), 1.75, 0.001)
	assert_almost_eq(float(economy["killed_per_1000_spent"]), 70.0, 0.001)


## An undefined ratio is reported as one rather than as a huge number, which
## would read as a measurement instead of a missing denominator. Spending
## nothing is the other missing denominator, and it is guarded differently: the
## divisor floors at 1, so a side that never built reports its kills times a
## thousand. That is the shipped reading, pinned here as it is.
func test_a_side_that_lost_or_spent_nothing_has_no_denominator() -> void:
	var idle: Array[Dictionary] = [_row(TIMELINE, {"team": 1})]
	var quiet: Dictionary = _economy_of(idle)
	assert_eq(quiet["exchange_ratio"], -1.0, "losing nothing has no ratio")
	assert_eq(quiet["killed_per_1000_spent"], 0.0)

	var killed: Array[Dictionary] = [_row(TIMELINE, {"team": 1, "killed_value": 50})]
	var unbought: Dictionary = _economy_of(killed)
	assert_eq(unbought["exchange_ratio"], -1.0)
	assert_almost_eq(float(unbought["killed_per_1000_spent"]), 50000.0, 0.001)


## Worst first: the table is read top-down for what is out of band, so the order
## is part of the verdict.
func test_swept_values_are_listed_worst_first() -> void:
	var rows: Array[Dictionary] = []
	for row in _decisive(3, 1):
		rows.append(_row(row, {"sweep_value": "strong"}))
	for row in _decisive(1, 3):
		rows.append(_row(row, {"match_id": "w" + row["match_id"], "sweep_value": "weak"}))
	var values: Array = _summary_of(rows)["values"]
	assert_eq(values.size(), 2)
	assert_eq(values[0]["value"], "weak")
	assert_eq(values[1]["value"], "strong")


## And by name within a tie, because the sort is not a stable one: a short sweep
## is mostly ties (0/50/100%), so without the second key adding one swept value
## reshuffles rows of a table somebody has already read.
func test_values_on_the_same_rate_are_ordered_by_name() -> void:
	var rows: Array[Dictionary] = []
	for value in ["pear", "apple", "cherry"]:
		for row in _decisive(1, 1):
			rows.append(_row(row, {"match_id": value + row["match_id"], "sweep_value": value}))
	var values: Array = _summary_of(rows)["values"]
	assert_eq(
		[values[0]["value"], values[1]["value"], values[2]["value"]], ["apple", "cherry", "pear"]
	)


# --- first-seat bias: the same word, two measurements -------------------------


## `n` mirror rows the first seat won and `losses` it lost — the pairing a
## commander matrix plays as its control and a Lab mirror sweep plays as its
## whole question.
func _mirrors(wins: int, losses: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in _decisive(wins, losses):
		rows.append(_row(row, {"match_id": "m" + row["match_id"], "mirror": 1}))
	return rows


## The two tools mean different things by "bias", so the caller says which — and
## both spell their answer out in the label they print it under. Excluding is the
## commander matrix's reading (its win rates come from the non-mirror games);
## counting them is the Lab's (a mirror sweep has nothing else to measure).
func test_the_seat_bias_counts_mirrors_only_when_the_caller_asks() -> void:
	var rows := _decisive(3, 3)
	rows.append_array(_mirrors(4, 0))

	var matrix := BalanceRunSummary.bias(rows, true)
	assert_eq(matrix["decisive"], 6, "the mirrors are out of the denominator")
	assert_almost_eq(float(matrix["bias_pp"]), 0.0, 0.001)
	assert_true(matrix["ok"])

	var lab := BalanceRunSummary.bias(rows, false)
	assert_eq(lab["decisive"], 10)
	assert_almost_eq(float(lab["bias_pp"]), 40.0, 0.001, "7 red to 3 blue")
	assert_false(lab["ok"])


## And the Lab's own summary is built on the counting one: a run of nothing but
## mirrors must still report a bias, since that is the number it was run for.
func test_a_mirror_only_run_still_reports_its_bias() -> void:
	var bias: Dictionary = _summary_of(_mirrors(9, 1))["bias"]["overall"]
	assert_eq(bias["decisive"], 10)
	assert_almost_eq(float(bias["bias_pp"]), 80.0, 0.001)


# --- the difficulty ladder's gate (difficulty plan DF4) -----------------------

## One tier-versus-tier row, the shape the ladder writes to its matches.csv.
const LADDER := {
	"map": "scrimmage",
	"seed": 1000,
	"low_tier": "normal",
	"high_tier": "hard",
	"high_side": "red",
	"winner": 1,
	"high_won": 1,
	"termination": "rout",
	"day_ended": 10,
	"commands": 40,
	"rejected": 0,
	"cap_stall": 0,
}

const LADDER_MAPS: Array[String] = ["scrimmage", "ironworks"]
const LADDER_PAIRINGS: Array = [["normal", "hard"]]


## `wins` matches the higher tier took and `losses` it dropped, all on one board.
func _ladder(map_name: String, wins: int, losses: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in wins:
		rows.append(_row(LADDER, {"map": map_name, "high_won": 1}))
	for i in losses:
		rows.append(_row(LADDER, {"map": map_name, "high_won": 0}))
	return rows


## The gate is inclusive: exactly 70% passes. It is the number a whole feature's
## "smarter, not cheating" claim is answered with, and it decides a build.
func test_the_ladder_gate_is_inclusive_at_exactly_the_gate() -> void:
	assert_eq(BalanceRunSummary.DIFFICULTY_GATE_PCT, 70.0)
	assert_false(BalanceRunSummary.gate_ok(69.9))
	assert_true(BalanceRunSummary.gate_ok(70.0))
	assert_true(BalanceRunSummary.gate_ok(70.1))

	var short_of_it := BalanceRunSummary.difficulty(
		_ladder("scrimmage", 13, 7), LADDER_PAIRINGS, LADDER_MAPS
	)
	assert_almost_eq(float(short_of_it["pairings"][0]["win_rate"]), 65.0, 0.001)
	assert_false(short_of_it["passed"])

	var exactly_it := BalanceRunSummary.difficulty(
		_ladder("scrimmage", 14, 6), LADDER_PAIRINGS, LADDER_MAPS
	)
	assert_almost_eq(float(exactly_it["pairings"][0]["win_rate"]), 70.0, 0.001)
	assert_true(exactly_it["passed"])


## Overall and per board, because the gate asks whether the extra thinking pays
## with room to manoeuvre as well as without — and a pairing can clear the gate
## overall on one board's strength alone, which is a reading the ladder's two
## committed documents make.
func test_the_ladder_reports_each_pairing_on_each_board() -> void:
	var rows := _ladder("scrimmage", 2, 8)
	rows.append_array(_ladder("ironworks", 10, 0))
	var pairing: Dictionary = (
		BalanceRunSummary.difficulty(rows, LADDER_PAIRINGS, LADDER_MAPS)["pairings"][0]
	)
	assert_eq(pairing["played"], 20)
	assert_almost_eq(float(pairing["win_rate"]), 60.0, 0.001)
	var maps: Array = pairing["maps"]
	assert_eq([maps[0]["map"], maps[1]["map"]], ["scrimmage", "ironworks"], "the run's own order")
	assert_almost_eq(float(maps[0]["win_rate"]), 20.0, 0.001)
	assert_almost_eq(float(maps[1]["win_rate"]), 100.0, 0.001)


## A pairing nobody played is not a pass. Its rate divides by a floored
## denominator, so it comes out 0% rather than undefined — and 0% fails, which is
## the safe direction for a gate whose rows went missing.
func test_a_pairing_that_played_nothing_does_not_pass() -> void:
	var empty := BalanceRunSummary.difficulty([] as Array[Dictionary], LADDER_PAIRINGS, LADDER_MAPS)
	assert_eq(empty["matches"], 0)
	assert_eq(empty["pairings"][0]["played"], 0)
	assert_almost_eq(float(empty["pairings"][0]["win_rate"]), 0.0, 0.001)
	assert_false(empty["passed"])


## Every gate clear and the run still fails: a rejected command means the planner
## and the rules disagree, a cap stall means a match that would not resolve.
## Both are bugs, and they fail the ladder as they fail the commander matrix.
func test_a_rejected_command_or_a_stall_fails_the_ladder_whatever_the_rate() -> void:
	var clean := BalanceRunSummary.difficulty(
		_ladder("scrimmage", 10, 0), LADDER_PAIRINGS, LADDER_MAPS
	)
	assert_true(clean["passed"])
	assert_true(clean["pairings"][0]["gate_ok"])

	var rows := _ladder("scrimmage", 10, 0)
	rows[0] = _row(rows[0], {"rejected": 1})
	var rejected := BalanceRunSummary.difficulty(rows, LADDER_PAIRINGS, LADDER_MAPS)
	assert_eq(rejected["total_rejected"], 1)
	assert_true(rejected["pairings"][0]["gate_ok"], "the ladder itself was cleared")
	assert_false(rejected["passed"], "and the run still fails")

	var stalled_rows := _ladder("scrimmage", 10, 0)
	stalled_rows[0] = _row(stalled_rows[0], {"cap_stall": 1})
	var stalled := BalanceRunSummary.difficulty(stalled_rows, LADDER_PAIRINGS, LADDER_MAPS)
	assert_eq(stalled["total_cap_stalls"], 1)
	assert_false(stalled["passed"])
