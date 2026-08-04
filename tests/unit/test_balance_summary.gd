extends GutTest
## The verdicts a Balance Lab run reports: which band a win rate falls in, how
## much the first seat is worth, and how much of either to believe.
##
## Worth pinning because these are quoted as findings — docs/commander_balance.md
## and docs/difficulty_check.md read a WARN, a bias figure and a confidence note
## as the run's answer — while every one of them is a threshold comparison that
## can be off by one boundary and still look plausible on the page.
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
