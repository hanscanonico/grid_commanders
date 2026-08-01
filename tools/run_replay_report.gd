extends SceneTree
## Reads a recorded match and reports what the sides playing it left on the table.
##
##   make replay-report REPLAY=<path to a .jsonl recording>
##
## Flags (after `--`):
##     --replay=<path>     the recording to read; also the bare first argument
##     --team=<n>          report only this side's misses (default: every side)
##     --out=reports/...   output directory (default reports/replay/<name>)
##     --quiet             write the files without printing the summary
##
## Writes two files, gitignored with the rest of reports/:
##   findings.md   — the ranked list, to read
##   findings.json — the same, to grep or diff
##
## The instrument observes (replay plan D6): every counterfactual comes from the
## rules — `AttackRange`, `MovementResolver`, `CombatResolver.forecast_at` — and
## nothing under `ai/` gained a hook for it. A finding is evidence rather than a
## verdict: several of them fire on a doctrine playing exactly as intended, which
## is why this is deliberately out of `make verify`.

const DEFAULT_OUT_ROOT := "reports/replay"
const DAMAGE_CHART_PATH := "res://data/damage_chart.tres"
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
	var recording := ReplayFile.read(_path)
	if recording == null:
		quit(2)  # ReplayFile has already said what is wrong with the file
		return
	var report := ReplayAnalysis.run(
		recording,
		TerrainDB.load_default(),
		UnitDB.load_default(),
		load(DAMAGE_CHART_PATH),
		CommanderDB.load_default()
	)
	if _team != 0:
		report.findings = _only(report.findings, _team)
	var out := _out_dir if _out_dir != "" else DEFAULT_OUT_ROOT.path_join(_run_name())
	var dir := BalanceReportWriter.prepare_dir(out)
	BalanceReportWriter.write_text(dir.path_join("findings.md"), _markdown(report))
	BalanceReportWriter.write_json(dir.path_join("findings.json"), report.to_dict())
	if not _quiet:
		_print_summary(report, out)
	quit(0)


## Returns false on a bad flag rather than reading some other file: a mistyped
## path that quietly reported on the wrong match would look exactly like a run
## that worked.
func _parse_args() -> bool:
	for arg in OS.get_cmdline_user_args():
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
