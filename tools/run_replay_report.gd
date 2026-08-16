extends SceneTree
## Reads a recorded match and reports what the sides playing it left on the table.
##
##   make replay-report REPLAY=<path to a .jsonl recording>
##   make replay-report REPLAY=<directory of recordings>
##
## Flags (after `--`):
##     --replay=<path>     the recording to read; also the bare first argument.
##                         A directory is surveyed: every .jsonl in it is read
##                         and the reports are folded into per-kind rates.
##     --team=<n>          report only this side's misses (default: every side)
##     --out=reports/...   output directory (default reports/replay/<name>)
##     --quiet             write the files without printing the summary
##
## Writes two files, gitignored with the rest of reports/:
##   findings.md   — the ranked list, to read
##   findings.json — the same, to grep or diff
## A survey writes survey.md and survey.json instead.
##
## The instrument observes (replay plan D6): every counterfactual comes from the
## rules — `AttackRange`, `MovementResolver`, `CombatResolver.forecast_at` — and
## nothing under `ai/` gained a hook for it. A finding is evidence rather than a
## verdict: several of them fire on a doctrine playing exactly as intended, which
## is why this is deliberately out of `make verify`.

const DEFAULT_OUT_ROOT := "reports/replay"
## How many findings the printed summary lists before saying how many are left,
## and how many of each kind the written report shows.
const PRINTED := 12
const PER_KIND := 6

var _path := ""
var _team := 0
var _out_dir := ""
var _quiet := false


func _init() -> void:
	if not _parse_args():
		quit(2)
		return
	if DirAccess.dir_exists_absolute(_path):
		quit(0 if _survey() else 2)
		return
	var report := _analyse(_path)
	if report == null:
		quit(2)  # ReplayFile has already said what is wrong with the file
		return
	var out := _out_dir if _out_dir != "" else DEFAULT_OUT_ROOT.path_join(_run_name())
	var dir := BalanceReportWriter.prepare_dir(out)
	BalanceReportWriter.write_text(dir.path_join("findings.md"), _markdown(report))
	BalanceReportWriter.write_json(dir.path_join("findings.json"), report.to_dict())
	if not _quiet:
		_print_summary(report, out)
	quit(0)


## Reads every recording in the named directory and writes one folded reading of
## the lot. A file that will not read is counted rather than fatal: a survey of
## twelve recordings is still worth having when one of them is stale, so long as
## it says so — which `ReplaySurvey.dropped_line` is for.
func _survey() -> bool:
	var files := _recordings_in(_path)
	if files.is_empty():
		push_error("replay-report: no %s recordings in '%s'" % [ReplayFile.EXTENSION, _path])
		return false
	var reports: Array[ReplayAnalysis.Report] = []
	var unreadable := 0
	for file in files:
		var report := _analyse(file)
		if report == null:
			unreadable += 1
			continue
		reports.append(report)
	var survey := ReplaySurvey.fold(reports, unreadable)
	var out := _out_dir if _out_dir != "" else DEFAULT_OUT_ROOT.path_join(_run_name())
	var dir := BalanceReportWriter.prepare_dir(out)
	if dir == "":
		return false
	var title := "Replay survey — %s" % _path
	BalanceReportWriter.write_text(dir.path_join("survey.md"), ReplaySurvey.markdown(survey, title))
	BalanceReportWriter.write_json(dir.path_join("survey.json"), survey)
	if not _quiet:
		_print_survey(survey, out)
	return true


func _analyse(file_path: String) -> ReplayAnalysis.Report:
	var recording := ReplayFile.read(file_path)
	if recording == null:
		return null
	var report := ReplayAnalysis.run(
		recording,
		TerrainDB.load_default(),
		UnitDB.load_default(),
		load(DamageChart.DEFAULT_PATH),
		CommanderDB.load_default()
	)
	if _team != 0:
		report.findings = _only(report.findings, _team)
	return report


## The recordings in a directory, in a stable order: no filesystem promises one,
## and a survey whose rows reshuffle between runs cannot be diffed.
static func _recordings_in(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(ReplayFile.EXTENSION):
			found.append(name)
	found.sort()
	var paths := PackedStringArray()
	for name in found:
		paths.append(dir.path_join(name))
	return paths


## Returns false on a bad flag rather than reading some other file: a mistyped
## path that quietly reported on the wrong match would look exactly like a run
## that worked.
func _parse_args() -> bool:
	for arg in CmdArgs.user():
		if arg.begins_with("--replay="):
			_path = arg.get_slice("=", 1).strip_edges()
		elif arg.begins_with("--team="):
			_team = int(arg.get_slice("=", 1))
		elif arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1).strip_edges()
		elif arg == "--quiet":
			_quiet = true
		elif not arg.begins_with("--") and _path == "":
			_path = arg.strip_edges()  # the bare form, so a pasted path just works
		else:
			push_error("replay-report: unknown flag '%s'" % arg)
			return false
	if _path == "":
		push_error("replay-report: name a recording — make replay-report REPLAY=<file>")
		return false
	if _out_dir != "":
		var resolved := BalanceReportWriter.resolve_out(_out_dir)
		if resolved == "":
			push_error("replay-report: --out is a directory under reports/ (got '%s')" % _out_dir)
			return false
		_out_dir = resolved
	return true


static func _only(
	findings: Array[ReplayAnalysis.Finding], team: int
) -> Array[ReplayAnalysis.Finding]:
	var kept: Array[ReplayAnalysis.Finding] = []
	for finding in findings:
		if finding.team == team:
			kept.append(finding)
	return kept


func _run_name() -> String:
	var name := _path.get_file().trim_suffix(ReplayFile.EXTENSION)
	return name if name != "" else "replay"


func _markdown(report: ReplayAnalysis.Report) -> String:
	var lines: Array[String] = []
	lines.append("# Replay findings — %s" % (report.label if report.label != "" else _run_name()))
	lines.append("")
	(
		lines
		. append(
			(
				"%s · %d commands · %d days · %s"
				% [
					report.map_path,
					report.commands,
					report.days,
					"team %d won" % report.winner if report.winner != 0 else "undecided",
				]
			)
		)
	)
	if report.stopped != "":
		lines.append("")
		lines.append("> **Stopped early:** %s" % report.stopped)
	lines.append("")
	lines.append("## What each side left on the table")
	lines.append("")
	lines.append("| finding | count |")
	lines.append("| --- | ---: |")
	var counts := report.counts()
	for kind: String in counts:
		lines.append("| `%s` | %d |" % [kind, counts[kind]])
	if counts.is_empty():
		lines.append("| _nothing_ | 0 |")
	lines.append("")
	if report.findings.is_empty():
		lines.append("_Nothing to report._")
		lines.append("")
	# Grouped rather than one flat ranking: twenty hoarding lines in a row say the
	# same thing twenty times, and the reader wants the worst few of each kind.
	# `findings` is already sorted, so each group comes out worst-first for free.
	var grouped: Dictionary = {}
	for finding in report.findings:
		var bucket: Array = grouped.get(finding.kind, [])
		bucket.append(finding)
		grouped[finding.kind] = bucket
	for kind: String in grouped:
		var bucket: Array = grouped[kind]
		lines.append("## %s — %d" % [kind, bucket.size()])
		lines.append("")
		for i in mini(bucket.size(), PER_KIND):
			lines.append("- %s" % (bucket[i] as ReplayAnalysis.Finding).line())
		if bucket.size() > PER_KIND:
			lines.append("- _… and %d more_" % (bucket.size() - PER_KIND))
		lines.append("")
	lines.append(
		(
			"Every counterfactual above comes from the rules — `AttackRange`, "
			+ "`MovementResolver`, `CombatResolver.forecast_at` — never from the planner. "
			+ "A finding says what happened and what was available instead; some of them "
			+ "are a doctrine playing exactly as intended."
		)
	)
	lines.append("")
	return "\n".join(lines)


func _print_summary(report: ReplayAnalysis.Report, out: String) -> void:
	print("replay-report: %s" % (report.label if report.label != "" else _path.get_file()))
	print(
		(
			"replay-report: %d commands, %d days, %d findings"
			% [report.commands, report.days, report.findings.size()]
		)
	)
	if report.stopped != "":
		print("replay-report: stopped early — %s" % report.stopped)
	for i in mini(report.findings.size(), PRINTED):
		print("  %s" % report.findings[i].line())
	if report.findings.size() > PRINTED:
		print("  ... and %d more" % (report.findings.size() - PRINTED))
	print("replay-report: wrote findings.md and findings.json to %s" % out)


func _print_survey(survey: Dictionary, out: String) -> void:
	print(
		(
			"replay-report: surveyed %d recordings, %d commands, %d findings"
			% [int(survey["matches"]), int(survey["commands"]), int(survey["findings"])]
		)
	)
	print("replay-report: %s" % ReplaySurvey.dropped_line(survey))
	var kinds: Array = survey["kinds"]
	for i in mini(kinds.size(), PRINTED):
		var entry: Dictionary = kinds[i]
		print(
			(
				"  %s — %d (%.2f per 100 commands)"
				% [entry["kind"], int(entry["count"]), float(entry["per_100_commands"])]
			)
		)
	print("replay-report: wrote survey.md and survey.json to %s" % out)
