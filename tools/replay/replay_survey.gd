class_name ReplaySurvey
extends RefCounted
## Folds many per-match `ReplayAnalysis.Report`s into one reading.
##
## A single report says what one side left on the table in one match, which is
## an anecdote. A survey says how *often* each kind of miss turns up — as a share
## of all findings, as a rate per 100 commands, and as a count per match — and
## which unit types it is usually about. That is a number with a reproducible
## command behind it, which is what `docs/replay_survey.md` records.
##
## It only counts what the analyser already found: no counterfactual is taken
## here and no detector is re-run, so the survey inherits the analyser's D6
## boundary whole — a rate is evidence about the game, never a verdict on it.
##
## A recording the analyser could not re-issue to its end, and a file it could
## not read at all, are both counted and both said out loud: a survey that
## silently dropped input reads exactly like one that had nothing to drop.
##
## Node-free, like the rest of the offline toolchain.

## How many unit types a kind's "most often" column names before it stops.
const TOP_SUBJECTS := 3


## Everything the survey knows, ready for `markdown` or a JSON dump.
## `unreadable` is the caller's count of files that never became a report.
static func fold(reports: Array[ReplayAnalysis.Report], unreadable: int = 0) -> Dictionary:
	var commands := 0
	var days := 0
	var findings := 0
	var stopped := 0
	var boards: Dictionary = {}
	var rows: Array[Dictionary] = []
	var counts: Dictionary = {}
	var subjects: Dictionary = {}
	for report in reports:
		commands += report.commands
		days += report.days
		findings += report.findings.size()
		boards[report.map_path] = true
		if report.stopped != "":
			stopped += 1
		rows.append(_row(report))
		for finding in report.findings:
			counts[finding.kind] = int(counts.get(finding.kind, 0)) + 1
			if finding.subject != "":
				var per_kind: Dictionary = subjects.get(finding.kind, {})
				per_kind[finding.subject] = int(per_kind.get(finding.subject, 0)) + 1
				subjects[finding.kind] = per_kind
	return {
		"matches": reports.size(),
		"boards": boards.size(),
		"commands": commands,
		"days": days,
		"findings": findings,
		"stopped": stopped,
		"unreadable": unreadable,
		"kinds": _kinds(counts, subjects, findings, commands, reports.size()),
		"rows": rows,
	}


static func markdown(survey: Dictionary, title: String = "Replay survey") -> String:
	var lines: Array[String] = []
	lines.append("# %s" % title)
	lines.append("")
	(
		lines
		. append(
			(
				"%d recordings · %d boards · %d commands · %d days · %d findings"
				% [
					int(survey["matches"]),
					int(survey["boards"]),
					int(survey["commands"]),
					int(survey["days"]),
					int(survey["findings"]),
				]
			)
		)
	)
	lines.append("")
	lines.append("> **%s**" % dropped_line(survey))
	lines.append("")
	lines.append_array(_kind_table(survey))
	lines.append_array(_row_table(survey))
	lines.append(
		(
			"A rate above is how often a detector fired, not how badly a side played: "
			+ "several of them fire on a doctrine playing exactly as intended. Every "
			+ "counterfactual behind them comes from the rules — `AttackRange`, "
			+ "`MovementResolver`, `CombatResolver.forecast_at` — never from the planner."
		)
	)
	lines.append("")
	return "\n".join(lines)


## What the survey says about its own input, in one line the reader cannot miss.
static func dropped_line(survey: Dictionary) -> String:
	var stopped := int(survey["stopped"])
	var unreadable := int(survey["unreadable"])
	if stopped == 0 and unreadable == 0:
		return "Every recording re-issued to its end; nothing was dropped."
	return (
		"%d recording(s) stopped early and %d could not be read at all — " % [stopped, unreadable]
		+ "every rate below is under-counted by whatever they held."
	)


static func _row(report: ReplayAnalysis.Report) -> Dictionary:
	return {
		"label": report.label,
		"map_path": report.map_path,
		"commands": report.commands,
		"days": report.days,
		"winner": report.winner,
		"findings": report.findings.size(),
		"stopped": report.stopped,
	}


## One entry per kind seen, worst-first, each priced three ways because the three
## disagree: a kind can be common per match and rare per command, and which of
## those a reader wants depends on whether they are asking about the board or
## about the planner.
static func _kinds(
	counts: Dictionary, subjects: Dictionary, findings: int, commands: int, matches: int
) -> Array[Dictionary]:
	var kinds: Array[Dictionary] = []
	for kind: String in counts:
		var count := int(counts[kind])
		(
			kinds
			. append(
				{
					"kind": kind,
					"count": count,
					"share": float(count) / float(findings) if findings > 0 else 0.0,
					"per_100_commands": 100.0 * count / commands if commands > 0 else 0.0,
					"per_match": float(count) / float(matches) if matches > 0 else 0.0,
					"subjects": _top_subjects(subjects.get(kind, {})),
				}
			)
		)
	kinds.sort_custom(_by_count)
	return kinds


static func _top_subjects(tally: Dictionary) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for subject: String in tally:
		ranked.append({"subject": subject, "count": int(tally[subject])})
	ranked.sort_custom(_by_subject_count)
	return ranked.slice(0, TOP_SUBJECTS)


static func _by_count(a: Dictionary, b: Dictionary) -> bool:
	if int(a["count"]) != int(b["count"]):
		return int(a["count"]) > int(b["count"])
	return String(a["kind"]) < String(b["kind"])


static func _by_subject_count(a: Dictionary, b: Dictionary) -> bool:
	if int(a["count"]) != int(b["count"]):
		return int(a["count"]) > int(b["count"])
	return String(a["subject"]) < String(b["subject"])


static func _kind_table(survey: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append("## Findings by kind")
	lines.append("")
	lines.append("| finding | count | share | per 100 commands | per match | most often |")
	lines.append("| --- | ---: | ---: | ---: | ---: | --- |")
	var kinds: Array = survey["kinds"]
	for entry: Dictionary in kinds:
		(
			lines
			. append(
				(
					"| `%s` | %d | %.1f%% | %.2f | %.1f | %s |"
					% [
						entry["kind"],
						int(entry["count"]),
						100.0 * float(entry["share"]),
						float(entry["per_100_commands"]),
						float(entry["per_match"]),
						_subject_line(entry["subjects"]),
					]
				)
			)
		)
	if kinds.is_empty():
		lines.append("| _nothing_ | 0 | — | — | — | — |")
	lines.append("")
	return lines


static func _subject_line(subjects: Array) -> String:
	var parts: Array[String] = []
	for entry: Dictionary in subjects:
		parts.append("%s ×%d" % [entry["subject"], int(entry["count"])])
	return ", ".join(parts) if not parts.is_empty() else "—"


static func _row_table(survey: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append("## The recordings")
	lines.append("")
	lines.append("| recording | board | commands | days | winner | findings | stopped |")
	lines.append("| --- | --- | ---: | ---: | ---: | ---: | --- |")
	for row: Dictionary in survey["rows"]:
		(
			lines
			. append(
				(
					"| %s | %s | %d | %d | %s | %d | %s |"
					% [
						row["label"] if String(row["label"]) != "" else "—",
						String(row["map_path"]).get_file(),
						int(row["commands"]),
						int(row["days"]),
						"team %d" % int(row["winner"]) if int(row["winner"]) != 0 else "undecided",
						int(row["findings"]),
						row["stopped"] if String(row["stopped"]) != "" else "—",
					]
				)
			)
		)
	lines.append("")
	return lines
