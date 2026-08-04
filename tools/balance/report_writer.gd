class_name BalanceReportWriter
extends RefCounted
## Writes a balance run's artifacts: CSV tables, a JSON summary, and the
## per-command JSONL log.
##
## Shared by the commander matrix, the difficulty ladder and the Balance Lab so
## the three write the same shapes — and, for the two committed gates, the same
## bytes they always did. The CSV format is deliberately the plainest thing that
## a spreadsheet opens: comma-separated, one header line, LF endings, trailing
## newline. Nothing here quotes, because nothing written through it contains a
## comma; the tally fields that could are semicolon-separated at the source.
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
## refuses the path, and nothing is written.
static func prepare_dir(out_dir: String) -> String:
	var relative := resolve_out(out_dir)
	if relative == "":
		push_error("balance: a run writes under %s/ (got '%s')" % [REPORTS_ROOT, out_dir])
		return ""
	var dir := ProjectSettings.globalize_path("res://").path_join(relative)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func _under_reports(path: String) -> bool:
	return path == REPORTS_ROOT or path.begins_with(REPORTS_ROOT + "/")


static func write_csv(path: String, rows: Array[Dictionary], columns: Array[String]) -> void:
	var lines: Array[String] = [",".join(columns)]
	for row in rows:
		var cells: Array[String] = []
		for column in columns:
			cells.append(str(row[column]))
		lines.append(",".join(cells))
	_store(path, "\n".join(lines) + "\n")


static func write_json(path: String, data: Variant) -> void:
	_store(path, JSON.stringify(data, "\t"))


## One compact JSON object per line. Written in one store rather than a line at a
## time because a big sweep's log is tens of thousands of lines and the file API
## charges per call, not per byte.
static func write_jsonl(path: String, entries: Array[Dictionary]) -> void:
	var lines: Array[String] = []
	for entry in entries:
		lines.append(JSON.stringify(entry))
	_store(path, "\n".join(lines) + "\n" if not lines.is_empty() else "")


static func write_text(path: String, text: String) -> void:
	_store(path, text)


static func _store(path: String, text: String) -> void:
	if not path.is_absolute_path():
		push_error("balance: no resolved output directory for '%s'" % path)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("balance: cannot write %s" % path)
		return
	file.store_string(text)
