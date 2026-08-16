extends GutTest
## The fold that turns N per-match reports into rates.
##
## Hand-built reports rather than played matches: what is under test is the
## arithmetic and the ordering, and a real recording would make every number here
## depend on the detectors this file is not about.


func _finding(kind: String, subject: String) -> ReplayAnalysis.Finding:
	var finding := ReplayAnalysis.Finding.new()
	finding.kind = kind
	finding.subject = subject
	return finding


func _report(map_path: String, commands: int, days: int, kinds: Array) -> ReplayAnalysis.Report:
	var report := ReplayAnalysis.Report.new()
	report.map_path = map_path
	report.commands = commands
	report.days = days
	for pair: Array in kinds:
		report.findings.append(_finding(pair[0], pair[1]))
	return report


func _two_reports() -> Array[ReplayAnalysis.Report]:
	var first := _report(
		"res://maps/a.txt",
		60,
		6,
		[["hoarding", ""], ["idle_unit", "infantry"], ["idle_unit", "tank"]]
	)
	var second := _report(
		"res://maps/b.txt",
		140,
		9,
		[["idle_unit", "infantry"], ["idle_unit", "artillery"], ["worse_shot", "tank"]]
	)
	second.winner = 2
	var reports: Array[ReplayAnalysis.Report] = [first, second]
	return reports


func test_totals_sum_over_the_reports() -> void:
	var survey := ReplaySurvey.fold(_two_reports())
	assert_eq(int(survey["matches"]), 2)
	assert_eq(int(survey["boards"]), 2)
	assert_eq(int(survey["commands"]), 200)
	assert_eq(int(survey["days"]), 15)
	assert_eq(int(survey["findings"]), 6)


func test_kinds_rank_by_count_and_carry_three_rates() -> void:
	var survey := ReplaySurvey.fold(_two_reports())
	var kinds: Array = survey["kinds"]
	assert_eq(kinds.size(), 3)
	var idle: Dictionary = kinds[0]
	assert_eq(String(idle["kind"]), "idle_unit")
	assert_eq(int(idle["count"]), 4)
	assert_almost_eq(float(idle["share"]), 4.0 / 6.0, 0.0001)
	assert_almost_eq(float(idle["per_100_commands"]), 2.0, 0.0001)
	assert_almost_eq(float(idle["per_match"]), 2.0, 0.0001)
	# A tie between `hoarding` and `worse_shot` is broken by name, so the table
	# reads the same on every run.
	assert_eq(String((kinds[1] as Dictionary)["kind"]), "hoarding")
	assert_eq(String((kinds[2] as Dictionary)["kind"]), "worse_shot")


func test_subjects_are_ranked_per_kind_and_skip_the_side_wide_ones() -> void:
	var survey := ReplaySurvey.fold(_two_reports())
	var kinds: Array = survey["kinds"]
	var subjects: Array = (kinds[0] as Dictionary)["subjects"]
	assert_eq(subjects.size(), 3)
	assert_eq(String((subjects[0] as Dictionary)["subject"]), "infantry")
	assert_eq(int((subjects[0] as Dictionary)["count"]), 2)
	assert_eq(String((subjects[1] as Dictionary)["subject"]), "artillery")
	assert_eq(String((subjects[2] as Dictionary)["subject"]), "tank")
	assert_eq(((kinds[1] as Dictionary)["subjects"] as Array).size(), 0)


func test_rows_carry_one_line_per_recording() -> void:
	var survey := ReplaySurvey.fold(_two_reports())
	var rows: Array = survey["rows"]
	assert_eq(rows.size(), 2)
	var second: Dictionary = rows[1]
	assert_eq(String(second["map_path"]), "res://maps/b.txt")
	assert_eq(int(second["commands"]), 140)
	assert_eq(int(second["winner"]), 2)
	assert_eq(int(second["findings"]), 3)


func test_a_stopped_recording_is_counted_and_said_out_loud() -> void:
	var reports := _two_reports()
	reports[0].stopped = "board digest mismatch at command 12"
	var survey := ReplaySurvey.fold(reports, 1)
	assert_eq(int(survey["stopped"]), 1)
	assert_eq(int(survey["unreadable"]), 1)
	assert_string_contains(ReplaySurvey.dropped_line(survey), "1 recording(s) stopped early")
	assert_string_contains(ReplaySurvey.markdown(survey), "stopped early")


func test_a_clean_survey_says_nothing_was_dropped() -> void:
	var survey := ReplaySurvey.fold(_two_reports())
	assert_string_contains(ReplaySurvey.dropped_line(survey), "nothing was dropped")


func test_an_empty_survey_divides_by_nothing() -> void:
	var none: Array[ReplayAnalysis.Report] = []
	var survey := ReplaySurvey.fold(none)
	assert_eq(int(survey["findings"]), 0)
	assert_eq((survey["kinds"] as Array).size(), 0)
	assert_string_contains(ReplaySurvey.markdown(survey), "_nothing_")
