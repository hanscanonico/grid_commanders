extends GutTest
## The legibility ratchet's arithmetic: which cell a row names, what the
## committed digest holds, and which of the four differences between a run and
## its baseline is a failure.
##
## Pure and static like the metric beside it, so the rule the offline sweep is
## held to — fail on a PASS that became a FAIL, and on nothing else — is checked
## without rendering the matrix.


func _row(unit: String, verdict: String, overlay := "none") -> Dictionary:
	return {
		"view": "board",
		"frame": "idle_a",
		"unit": unit,
		"faction": "iron",
		"state": "ready",
		"terrain": "woods",
		"variant": "atlas",
		"overlay": overlay,
		"edge_steps": 1.5,
		"verdict": verdict,
	}


## The sweep hands the baseline a typed array; these build one inline.
func _rows(rows: Array) -> Array[Dictionary]:
	var typed: Array[Dictionary] = []
	for row: Dictionary in rows:
		typed.append(row)
	return typed


func test_key_leaves_the_variant_out() -> void:
	var row := _row("tank", "PASS")
	var other := _row("tank", "PASS")
	other["variant"] = "n_e"
	assert_eq(LegibilityBaseline.key_of(row), "board:idle_a:tank:iron:ready:woods:none")
	assert_eq(LegibilityBaseline.key_of(other), LegibilityBaseline.key_of(row), "same cell")


func test_digest_keeps_the_verdict_and_drops_the_readings() -> void:
	var digested := LegibilityBaseline.digest(_rows([_row("tank", "FAIL")]))
	assert_eq(digested.size(), 1)
	assert_eq(digested[0].keys(), LegibilityBaseline.COLUMNS, "only the named columns")
	assert_eq(str(digested[0]["verdict"]), "FAIL")


func test_csv_round_trips() -> void:
	var rows := _rows([_row("tank", "PASS"), _row("apc", "FAIL", "fog")])
	var verdicts := LegibilityBaseline.parse(LegibilityBaseline.to_csv(rows))
	assert_eq(verdicts.size(), 2)
	assert_eq(verdicts[LegibilityBaseline.key_of(rows[0])], "PASS")
	assert_eq(verdicts[LegibilityBaseline.key_of(rows[1])], "FAIL")


func test_a_pass_that_fails_is_the_only_failure() -> void:
	var baseline := LegibilityBaseline.parse(
		LegibilityBaseline.to_csv(_rows([_row("tank", "PASS"), _row("apc", "FAIL")]))
	)
	var diff := LegibilityBaseline.compare(baseline, _rows([_row("tank", "FAIL")]))
	assert_true(LegibilityBaseline.regressed(diff), "the tank cell fell out of passing")
	assert_eq(diff["regressed"], ["board:idle_a:tank:iron:ready:woods:none"])
	assert_string_contains(
		LegibilityBaseline.report(diff), "board:idle_a:tank:iron:ready:woods:none"
	)


func test_a_recovered_or_new_cell_is_reported_not_failed() -> void:
	var baseline := LegibilityBaseline.parse(
		LegibilityBaseline.to_csv(_rows([_row("apc", "FAIL")]))
	)
	var diff := LegibilityBaseline.compare(
		baseline, _rows([_row("apc", "PASS"), _row("tank", "FAIL")])
	)
	assert_false(LegibilityBaseline.regressed(diff), "the ratchet never demands improvement")
	assert_eq(diff["recovered"], ["board:idle_a:apc:iron:ready:woods:none"])
	assert_eq(diff["added"], ["board:idle_a:tank:iron:ready:woods:none"])


func test_a_cell_the_run_no_longer_measures_is_reported() -> void:
	var baseline := LegibilityBaseline.parse(
		LegibilityBaseline.to_csv(_rows([_row("apc", "PASS")]))
	)
	var diff := LegibilityBaseline.compare(baseline, _rows([]))
	assert_false(LegibilityBaseline.regressed(diff))
	assert_eq(diff["missing"], ["board:idle_a:apc:iron:ready:woods:none"])


func test_a_corrupt_baseline_parses_to_nothing() -> void:
	assert_eq(LegibilityBaseline.parse("unit,verdict\ntank,PASS\n").size(), 0, "wrong header")
	var doubled := LegibilityBaseline.to_csv(_rows([_row("tank", "PASS"), _row("tank", "FAIL")]))
	assert_eq(LegibilityBaseline.parse(doubled).size(), 0, "one cell, two verdicts")
	assert_push_error_count(2, "each corrupt file says what is wrong with it")
