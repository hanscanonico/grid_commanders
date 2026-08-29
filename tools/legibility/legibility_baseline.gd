class_name LegibilityBaseline
extends RefCounted
## The committed verdict digest the sweep is diffed against, and the diff itself.
##
## The sweep is an instrument and stays one: a failing cell is a finding for the
## art to answer, never a colour to move. What was missing between two manual
## re-reads was a way to notice a cell *falling out* of passing, so this holds
## that line and nothing more — a run fails only where the baseline says PASS and
## today says FAIL. A cell that newly passes is printed and forgiven, because
## demanding improvement is what would turn the instrument into a gate.
##
## Only the verdicts are committed, never the readings behind them. A ramp-step
## number moves with any legitimate re-render of the art; PASS/FAIL is what the
## bar actually says, so the file stays quiet through an art change that did not
## cost anything.
##
## Node-free, like the rest of tools/legibility.

## Where `make legibility-baseline` writes and `make legibility-ratchet` reads.
const PATH := "tests/fixtures/legibility_baseline.csv"
## The fields that name a cell here — the sweep's eight minus `variant`, which is
## the worst-scoring tile of the terrain's family rather than a coordinate of the
## matrix. A re-render can move which phase wins without moving the verdict, and
## keying on it would read that as one cell vanishing and another appearing
## instead of as the nothing it is.
const KEYS: Array[String] = ["view", "frame", "unit", "faction", "state", "terrain", "overlay"]
const COLUMNS: Array[String] = [
	"view", "frame", "unit", "faction", "state", "terrain", "overlay", "verdict"
]


## `view:frame:unit:faction:state:terrain:overlay` — how a cell is named in the
## file and in a regression line.
static func key_of(row: Dictionary) -> String:
	var fields: Array[String] = []
	for key in KEYS:
		fields.append(str(row.get(key, "")))
	return ":".join(fields)


## The sweep's rows, cut down to what the file holds, in the sweep's own walk
## order so two runs of one tree write the same bytes.
static func digest(rows: Array[Dictionary]) -> Array[Dictionary]:
	var digested: Array[Dictionary] = []
	for row in rows:
		var entry: Dictionary = {}
		for column in COLUMNS:
			entry[column] = str(row.get(column, ""))
		digested.append(entry)
	return digested


static func to_csv(rows: Array[Dictionary]) -> String:
	var lines: Array[String] = [",".join(COLUMNS)]
	for row in digest(rows):
		var cells: Array[String] = []
		for column in COLUMNS:
			cells.append(str(row[column]))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


## Cell name -> verdict. A duplicate key or a short line is a corrupt baseline
## rather than a finding, so parsing says so and hands back nothing.
static func parse(text: String) -> Dictionary[String, String]:
	var verdicts: Dictionary[String, String] = {}
	var lines := text.split("\n", false)
	if lines.is_empty() or lines[0].strip_edges() != ",".join(COLUMNS):
		push_error("legibility: a baseline starts with the header %s" % ",".join(COLUMNS))
		return {}
	for i in range(1, lines.size()):
		var cells := lines[i].strip_edges().split(",")
		if cells.size() != COLUMNS.size():
			push_error("legibility: baseline line %d has %d fields" % [i + 1, cells.size()])
			return {}
		var row: Dictionary = {}
		for c in COLUMNS.size():
			row[COLUMNS[c]] = cells[c]
		var key := key_of(row)
		if verdicts.has(key):
			push_error("legibility: baseline names %s twice" % key)
			return {}
		verdicts[key] = str(row["verdict"])
	return verdicts


## The four ways a run can differ from its baseline. Only `regressed` is a
## failure; the other three are things to read.
static func compare(
	verdicts: Dictionary[String, String], rows: Array[Dictionary]
) -> Dictionary[String, Array]:
	var diff: Dictionary[String, Array] = {
		"regressed": [], "recovered": [], "added": [], "missing": []
	}
	var seen: Dictionary[String, bool] = {}
	for row in rows:
		var key := key_of(row)
		seen[key] = true
		if not verdicts.has(key):
			diff["added"].append(key)
			continue
		var was: String = verdicts[key]
		var now := str(row.get("verdict", ""))
		if was == "PASS" and now == "FAIL":
			diff["regressed"].append(key)
		elif was == "FAIL" and now == "PASS":
			diff["recovered"].append(key)
	for key: String in verdicts:
		if not seen.has(key):
			diff["missing"].append(key)
	return diff


static func regressed(diff: Dictionary[String, Array]) -> bool:
	return not diff["regressed"].is_empty()


## What a ratchet run prints: the one class that fails, then the three that only
## report. A cell the baseline does not know about is listed rather than judged —
## the matrix grows whenever a unit, a frame or a ground is added, and that is a
## re-baseline, not a regression.
static func report(diff: Dictionary[String, Array]) -> String:
	var lines: Array[String] = ["", "# Legibility ratchet"]
	lines.append_array(_lines("regressed (PASS -> FAIL)", diff["regressed"]))
	lines.append_array(_lines("recovered (FAIL -> PASS)", diff["recovered"]))
	lines.append_array(_lines("not in the baseline", diff["added"]))
	lines.append_array(_lines("in the baseline, not in this run", diff["missing"]))
	if regressed(diff):
		lines.append("")
		lines.append("A cell that passed no longer does. Read it, answer it in the art, or")
		lines.append("re-baseline with `make legibility-baseline` if the loss is intended.")
	return "\n".join(lines)


static func _lines(label: String, keys: Array) -> Array[String]:
	var lines: Array[String] = ["", "%s: %d" % [label, keys.size()]]
	for key: String in keys:
		lines.append("  %s" % key)
	return lines
