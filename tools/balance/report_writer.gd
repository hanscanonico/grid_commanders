class_name BalanceReportWriter
extends RefCounted
## Writes a balance run's artifacts: CSV tables, a JSON summary, and the
## per-command JSONL log.
##
## Shared by the commander matrix, the difficulty ladder and the Balance Lab so
## the three write the same shapes — and, for the two committed gates, the same
## bytes they always did. The CSV format is deliberately the plainest thing that
## a spreadsheet opens: comma-separated, one header line, LF endings, trailing
## newline.
##
## Node-free, like the rest of the harness.

## Where every instrument's artifacts live, and the whole of what `resolve_out`
## contains a run to.
const REPORTS_ROOT := "reports"


## The one answer to where a run may write, given whatever a caller typed: a
## project-relative directory under `reports/`, or "" when the request leaves it.
## The write and the "wrote X" line both read this, so no tool can name a path it
## did not write to.
##
## `ProjectSettings.globalize_path("res://").path_join(out_dir)` re-roots rather
## than resolves, and three spellings have now reached it: a leading `/`, a
## `res://` prefix, and a `..` that climbs out. Each lands the artifact inside
## the repo under a name nobody reads, while the tool reports the path it was
## given — and a pool resume keyed on finding a marker then replays every shard
## forever. `tools/balance_pool.py`'s `resolve_out` is the same policy said in
## Python, because that driver has to refuse a path before it launches a preset
## rather than after; the two share the case table their checks are pinned by.
static func resolve_out(out_dir: String) -> String:
	var relative := out_dir.trim_prefix("res://")
	if relative.begins_with("/"):
		return ""
	var path := relative.simplify_path()
	if not _under_reports(path):
		path = REPORTS_ROOT.path_join(path).simplify_path()
	return path if _under_reports(path) else ""


## Absolutizes a run's out-directory, creating it. Returns "" when `resolve_out`
## refuses the path or the directory could not be created, and nothing is
## written — a caller that goes on to write against "" is the bug this guards
## against, not a fallback this function offers.
static func prepare_dir(out_dir: String) -> String:
	var relative := resolve_out(out_dir)
	if relative == "":
		push_error("balance: a run writes under %s/ (got '%s')" % [REPORTS_ROOT, out_dir])
		return ""
	var dir := ProjectSettings.globalize_path("res://").path_join(relative)
	var error := DirAccess.make_dir_recursive_absolute(dir)
	if error != OK:
		push_error("balance: cannot create %s (error %d)" % [dir, error])
		return ""
	return dir


static func _under_reports(path: String) -> bool:
	return path == REPORTS_ROOT or path.begins_with(REPORTS_ROOT + "/")


## One header line then one line per row, in the requested column order — the
## row's own key order is never consulted, so a runner may build a row however is
## convenient and still write the committed shape.
##
## A column a row does not carry is written empty and reported: a batch is an
## hour of matches, and dropping the whole run over one missing key loses every
## match that was fine.
static func write_csv(path: String, rows: Array[Dictionary], columns: Array[String]) -> bool:
	var lines: Array[String] = [",".join(columns)]
	for row in rows:
		var cells: Array[String] = []
		for column in columns:
			if not row.has(column):
				push_error("balance: no '%s' in a row of %s" % [column, path.get_file()])
				cells.append("")
				continue
			cells.append(_cell(str(row[column])))
		lines.append(",".join(cells))
	return _store(path, "\n".join(lines) + "\n")


## A cell, quoted the way every spreadsheet reads back (RFC 4180): wrapped in
## double quotes when it holds a separator, a quote or a newline, with its own
## quotes doubled. Nothing the reports write today needs it — the tally fields
## that could hold a separator are semicolon-joined at the source — so this moves
## no committed byte; it is here so that the day one does, the file stays the
## table it claims to be instead of silently growing a column.
static func _cell(value: String) -> String:
	if not (
		value.contains(",") or value.contains('"') or value.contains("\n") or value.contains("\r")
	):
		return value
	return '"%s"' % value.replace('"', '""')


static func write_json(path: String, data: Variant) -> bool:
	return _store(path, JSON.stringify(data, "\t"))


## One compact JSON object per line. Written in one store rather than a line at a
## time because a big sweep's log is tens of thousands of lines and the file API
## charges per call, not per byte.
static func write_jsonl(path: String, entries: Array[Dictionary]) -> bool:
	var lines: Array[String] = []
	for entry in entries:
		lines.append(JSON.stringify(entry))
	return _store(path, "\n".join(lines) + "\n" if not lines.is_empty() else "")


static func write_text(path: String, text: String) -> bool:
	return _store(path, text)


## Writes a whole artifact, and says so when it could not — both halves are
## reported, and both are the caller's to act on: a run whose disk filled
## halfway through a sweep must not hand back a truncated report that reads
## like a finished one, or exit as if it had.
static func _store(path: String, text: String) -> bool:
	if not path.is_absolute_path():
		push_error("balance: no resolved output directory for '%s'" % path)
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("balance: cannot write %s" % path)
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		push_error("balance: %s was not written whole (error %d)" % [path, error])
		return false
	return true
