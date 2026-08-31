extends SceneTree
## Scores every line of campaign dialogue for structural AI-slop and prints the
## worst of it. `make prose` is the entry point.
##
## **A measurement, not a gate.** It exits 0 whatever it finds, it is not in
## `make verify`, and it edits no content — the same standing as
## `make campaign-difficulty`. What it produces is a reading order for a human
## doing a dialogue pass; `docs/prose_slop.md` is the committed record of what
## each reading means, which false positives are known, and the numbers a rewrite
## is measured against.
##
## The corpus is `ProseCorpus`'s, the per-line readings are `ProseMetrics`'s and
## every table is `ProseReport`'s. What lives here is the flags, the printing and
## the CSV.
##
## Usage (headless; see `make prose`):
##   Godot --headless --path . -s res://tools/run_prose_check.gd -- [flags]
##     --campaign=the_quiet_war   one war rather than all of them
##     --speaker=vale             one voice; "(narration)" for the narrator
##     --worst=25                 how many lines to list (default 25)
##     --min=0.0                  list only lines at or above this score
##     --csv=reports/prose/slop.csv   where the full table goes (gitignored)
##     --reference                score the commanders' power quotes and doctrine
##                                blurbs *instead* of the campaigns, as a control

const TOOL := "prose"
const DEFAULT_CSV := "reports/prose/slop.csv"
const DEFAULT_WORST := 25
const EXCERPT_WIDTH := 40

const CSV_COLUMNS: Array[String] = [
	"campaign",
	"source",
	"slot",
	"index",
	"speaker",
	"score",
	"lockstep",
	"aphorism",
	"negation",
	"em_dash",
	"cadence",
	"triad",
	"stock",
	"vocative",
	"register",
	"sentences",
	"words",
	"text",
]

var _campaign := ""
var _speaker := ""
var _worst := DEFAULT_WORST
var _min := 0.0
var _csv := DEFAULT_CSV
var _reference := false


func _initialize() -> void:
	_parse_args(CmdArgs.user())
	# The control corpus replaces the campaigns rather than joining them: a power
	# quote is written to be one aphorism, so scored in the same table it would
	# both top the worst-N list and drag every campaign mean it is averaged into.
	var lines := (
		ProseCorpus.commander_lines(CommanderDB.load_default())
		if _reference
		else ProseCorpus.gather(CampaignDB.load_default())
	)
	lines = ProseCorpus.narrow(lines, _campaign, _speaker)
	if lines.is_empty():
		print("%s: no dialogue matched that filter" % TOOL)
		quit(0)
		return
	var scored := ProseReport.rows(lines)
	_print_summary(lines, scored)
	_print_tables(lines, scored)
	_print_worst(scored)
	_write_csv(scored)
	quit(0)


func _parse_args(args: PackedStringArray) -> void:
	_campaign = CmdArgs.value(args, "--campaign")
	_speaker = CmdArgs.value(args, "--speaker")
	_reference = CmdArgs.flag(args, "--reference")
	if CmdArgs.has(args, "--worst"):
		_worst = maxi(0, int(CmdArgs.value(args, "--worst")))
	if CmdArgs.has(args, "--min"):
		_min = float(CmdArgs.value(args, "--min"))
	# `has` rather than a non-empty value, so `--csv=` means "write nothing"
	# rather than "write to the default place".
	if CmdArgs.has(args, "--csv"):
		_csv = CmdArgs.value(args, "--csv")


func _print_summary(lines: Array[ProseLine], scored: Array[Dictionary]) -> void:
	var totals := ProseReport.aggregate(lines, scored)
	print("")
	print("%s: %d lines, %d voices" % [TOOL, totals["lines"], totals["speakers"]])
	print(
		(
			"%s: mean score %.3f | mean sentence %.1f words | sentence-count entropy %.2f bits"
			% [
				TOOL,
				totals["mean_score"],
				totals["corpus_mean_sentence_words"],
				totals["sentence_count_entropy"],
			]
		)
	)
	var rates: Dictionary = totals["rates"]
	var parts: Array[String] = []
	for key: String in ProseMetrics.HEURISTICS:
		parts.append("%s %.0f%%" % [key, float(rates[key]) * 100.0])
	print("%s: fired on — %s" % [TOOL, ", ".join(parts)])
	print(
		(
			"%s: speaker sentence-length σ spans %.2f to %.2f words"
			% [TOOL, totals["narrowest_speaker_sigma"], totals["widest_speaker_sigma"]]
		)
	)


func _print_tables(lines: Array[ProseLine], scored: Array[Dictionary]) -> void:
	_print_section("worst missions (mean score)")
	for row: Dictionary in ProseReport.worst_sources(scored, 10):
		print("  %.3f  %-34s %d lines" % [row["mean_score"], row["source"], row["lines"]])
	_print_section("openings shared across voices")
	for row: Dictionary in ProseReport.shared_openings(lines):
		print("  %-24s %d uses across %d voices" % [row["opening"], row["uses"], row["speakers"]])
	_print_section("voices that overlap most (trigram Jaccard)")
	for row: Dictionary in ProseReport.voice_overlap(lines):
		print("  %.3f  %s / %s" % [row["jaccard"], row["a"], row["b"]])
	_print_section("narrowest cadence (sentence-length σ)")
	for row: Dictionary in ProseReport.speaker_spread(lines).slice(0, 10):
		print(
			(
				"  σ %.2f  mean %.1f  %-20s %d lines"
				% [row["sigma"], row["mean"], row["speaker"], row["lines"]]
			)
		)
	var vocatives := ProseReport.vocative_sources(scored)
	if vocatives.is_empty():
		return
	_print_section("vocative-heavy missions (over %d%%)" % int(ProseReport.VOCATIVE_RATE * 100.0))
	for row: Dictionary in vocatives:
		print("  %.0f%%  %-34s %d lines" % [row["rate"] * 100.0, row["source"], row["lines"]])


func _print_worst(scored: Array[Dictionary]) -> void:
	_print_section("worst %d lines" % _worst)
	for row: Dictionary in ProseReport.worst(scored, _worst):
		if float(row["score"]) < _min:
			break
		var line: ProseLine = row["line"]
		print(
			(
				"  %.3f  %-30s %-14s %s"
				% [
					row["score"],
					line.where(),
					String(line.voice()),
					line.excerpt(EXCERPT_WIDTH),
				]
			)
		)
		var fired := ProseMetrics.fired(row["measures"])
		if not fired.is_empty():
			print("         %s" % ", ".join(fired))


func _print_section(title: String) -> void:
	print("")
	print("%s: %s" % [TOOL, title])


func _write_csv(scored: Array[Dictionary]) -> void:
	if _csv == "":
		return
	var dir := BalanceReportWriter.prepare_dir(_csv.get_base_dir())
	if dir == "":
		return
	var rows: Array[Dictionary] = []
	for row: Dictionary in scored:
		rows.append(_csv_row(row))
	var path := dir.path_join(_csv.get_file())
	if BalanceReportWriter.write_csv(path, rows, CSV_COLUMNS):
		print("")
		print("%s: wrote %d rows to %s" % [TOOL, rows.size(), path])


func _csv_row(row: Dictionary) -> Dictionary:
	var line: ProseLine = row["line"]
	var cells := {
		"campaign": String(line.campaign_id),
		"source": line.source(),
		"slot": line.slot,
		"index": line.index,
		"speaker": String(line.voice()),
		"score": "%.4f" % row["score"],
		"sentences": ProseMetrics.sentences(line.text).size(),
		"words": ProseMetrics.word_count(line.text),
		"text": line.text.replace("\n", " "),
	}
	for key: String in ProseMetrics.HEURISTICS:
		cells[key] = "%.3f" % float(row["measures"][key])
	return cells
