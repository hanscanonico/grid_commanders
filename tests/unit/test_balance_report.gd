extends GutTest
## The bytes a balance run writes, and the page it draws them on.
##
## The CSV half is the merge bar itself: touching the one match loop is cleared
## by a fixed-seed byte-diff of both committed reports (balance plan D1), so the
## column order, the separator, the line endings and how a value is rendered are
## the comparison rather than an implementation detail. `tests/fixtures/
## determinism/matches.csv` is the incumbent for the shape of a whole file; this
## pins the rules that produce it, one at a time.
##
## The HTML half is held to its own rule (plan BS4): it computes nothing and it
## is self-contained. What is tested here is escaping and the two formatters,
## because those are where a value can silently stop being the value.
##
## Both are RefCounted under tools/balance/, Node-free, so GUT drives them
## directly. Files are written under user:// and cleaned up: nothing here
## touches a report somebody generated.

const DIR := "user://test_balance_report"


func before_each() -> void:
	_clear()


func after_all() -> void:
	_clear()


func _path(file_name: String) -> String:
	return DIR.path_join(file_name)


func _written(file_name: String) -> String:
	return FileAccess.get_file_as_string(_path(file_name))


func _clear() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		return
	for file_name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(file_name)))


# --- the CSV -----------------------------------------------------------------


## The header is the requested columns in the requested order, and so is every
## row: the dictionary's own key order is not consulted, which is what lets a row
## be built in whatever order is convenient and still land in the committed one.
func test_the_columns_argument_is_the_column_order() -> void:
	var rows: Array[Dictionary] = [{"b": 2, "a": 1}, {"a": 3, "b": 4}]
	BalanceReportWriter.write_csv(_path("m.csv"), rows, ["a", "b"])
	assert_eq(_written("m.csv"), "a,b\n1,2\n3,4\n")


## A column the columns list does not name is not written, however present it is
## in the row — a runner that starts recording something new does not silently
## widen a committed report.
func test_a_column_that_was_not_asked_for_is_not_written() -> void:
	var rows: Array[Dictionary] = [{"a": 1, "spare": "x"}]
	BalanceReportWriter.write_csv(_path("m.csv"), rows, ["a"])
	assert_eq(_written("m.csv"), "a\n1\n")


## LF endings and a trailing newline, on an empty table as much as a full one:
## the byte-diff compares whole files, so the last byte is part of the format.
func test_a_table_with_no_rows_is_still_a_header_and_a_newline() -> void:
	BalanceReportWriter.write_csv(_path("m.csv"), [] as Array[Dictionary], ["a", "b"])
	assert_eq(_written("m.csv"), "a,b\n")


## How a value is rendered is `str()`, and the cells below are what that
## produces: a whole float keeps its `.0` and an integer never grows one, so the
## two are distinguishable in the file; a long fraction is cut at fourteen
## significant digits rather than at a rounding of the writer's own choosing.
## Every one of them is a byte the merge bar compares.
func test_values_are_rendered_the_way_the_committed_reports_carry_them() -> void:
	var rows: Array[Dictionary] = [
		{
			"int": 21,
			"whole": 50.0,
			"fraction": 1.75,
			"long": 1.0 / 3.0,
			"negative": -5.0,
			"flag": true,
			"text": "none-normal vs none-normal",
		}
	]
	var columns: Array[String] = ["int", "whole", "fraction", "long", "negative", "flag", "text"]
	BalanceReportWriter.write_csv(_path("m.csv"), rows, columns)
	var cells := _written("m.csv").split("\n")[1].split(",")
	assert_eq(cells[0], "21")
	assert_eq(cells[1], "50.0")
	assert_eq(cells[2], "1.75")
	assert_eq(cells[3], "0.33333333333333")
	assert_eq(cells[4], "-5.0")
	assert_eq(cells[5], "true")
	assert_eq(cells[6], "none-normal vs none-normal")


## Nothing quotes and nothing escapes: the writer's own header says so, and the
## reason it is safe is upstream — the tally fields that could hold a separator
## are semicolon-joined at the source. So a comma in a value really does become
## a column break, and that is pinned rather than left to be discovered by a
## spreadsheet. A writer that started quoting would move every committed byte.
func test_a_separator_in_a_value_is_written_through_rather_than_quoted() -> void:
	var rows: Array[Dictionary] = [{"a": "x,y", "b": 'say "no"', "c": "one\ntwo"}]
	BalanceReportWriter.write_csv(_path("m.csv"), rows, ["a", "b", "c"])
	assert_eq(_written("m.csv"), 'a,b,c\nx,y,say "no",one\ntwo\n')


## One compact object per line, and an empty log is an empty file rather than a
## lone newline — a run that logged nothing writes nothing.
func test_jsonl_is_one_object_a_line() -> void:
	var entries: Array[Dictionary] = [{"a": 1}, {"b": "two"}]
	BalanceReportWriter.write_jsonl(_path("log.jsonl"), entries)
	assert_eq(_written("log.jsonl"), '{"a":1}\n{"b":"two"}\n')
	BalanceReportWriter.write_jsonl(_path("empty.jsonl"), [] as Array[Dictionary])
	assert_eq(_written("empty.jsonl"), "")


## summary.json is read by people as well as by the HTML, so it is indented —
## with tabs, like everything else in the repo.
func test_json_is_written_indented() -> void:
	BalanceReportWriter.write_json(_path("s.json"), {"a": [1, 2]})
	assert_eq(_written("s.json"), '{\n\t"a": [\n\t\t1,\n\t\t2\n\t]\n}')


## A path that cannot be opened is reported rather than dropped: a run that
## wrote nowhere must not look like a run that wrote nothing.
func test_an_unwritable_path_is_reported() -> void:
	BalanceReportWriter.write_text("user://no_such_dir_here/report.html", "x")
	assert_push_error_count(1, "the failed path is named in the log")


# --- the page ----------------------------------------------------------------


## Everything a value could carry into the markup goes through the escape, so a
## swept value or a board name that looks like a tag is drawn rather than parsed.
func test_a_value_that_looks_like_markup_is_escaped() -> void:
	var page := BalanceReportHtml.render(_summary_of('<b>&"x"</b>'), [] as Array[Dictionary])
	assert_string_contains(page, "&lt;b&gt;&amp;&quot;x&quot;&lt;/b&gt;")
	assert_false(page.contains("<b>&"), "the raw form must not reach the page")


## The report opens off disk beside the CSVs it renders, so it may reach for
## nothing: no script, no stylesheet, no image, no server.
func test_the_page_is_self_contained() -> void:
	var page := BalanceReportHtml.render(_summary_of("plain"), [] as Array[Dictionary])
	assert_string_contains(page, "<!doctype html>")
	assert_false(page.contains("<script"), "no script")
	assert_false(page.contains("http://"), "nothing fetched")
	assert_false(page.contains("https://"), "nothing fetched")


## The em dash is the missing denominator, printed the same way on the page and
## in the console summary — a number there would read as a measurement.
func test_an_exchange_ratio_with_no_denominator_prints_as_a_dash() -> void:
	assert_eq(BalanceReportHtml.ratio(-1.0), "—")
	assert_eq(BalanceReportHtml.ratio(0.0), "0.00")
	assert_eq(BalanceReportHtml.ratio(1.756), "1.76")


## One swept value's summary, built through BalanceRunSummary so the page is
## rendered from the shape the runner really hands it.
func _summary_of(label: String) -> Dictionary:
	var matches: Array[Dictionary] = [
		{
			"match_id": "m1",
			"sweep_axis": "matchup",
			"sweep_value": label,
			"map": label,
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
	]
	var summary := BalanceRunSummary.build(
		{"label": label, "seeds": 1, "days_cap": 30}, matches, [] as Array[Dictionary]
	)
	return summary
