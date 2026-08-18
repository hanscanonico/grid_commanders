extends Node
## The composite legibility sweep (sprite design spec item 15): every unit kind,
## in every faction's colours, ready and acted, over every ground, under every
## wash the board lays on it — and the same figures at the cut-in's resolution.
## Each cell is measured for unit-vs-ground separation in ramp steps and judged
## against LegibilitySweep.PASS_STEPS.
##
## An instrument, not a gate: it reads shipped art and shipped constants, plays
## no match, tunes nothing, and stays out of `make verify` for the same reason
## the Balance Lab does — a failing cell is a finding to record and answer in
## the art, never a number to move here. docs/sprite_legibility.md is the
## committed reading, dated and superseded wholesale rather than edited.
##
## Booted as a scene rather than with `-s`, unlike its sibling instruments: it
## reads the board's own constants off BattleView and BattleOverlays, and those
## scripts reach UI that names autoload singletons, which only exist once the
## project's main loop is up.
##
## Usage (headless; see `make legibility-check`):
##   Godot --headless --path . res://tools/run_legibility_check.tscn -- [flags]
##     --out=reports/legibility   output directory (default shown)
##     --worst=20                 how many failing cells to print
##     --dump=board:tank:verdant:ready:woods:none
##                                writes that one composite as a PNG beside the
##                                report, magnified by --dump-scale
##     --dump-scale=8             nearest magnification of a dumped crop
##
## Writes cells.csv and summary.md under --out (gitignored).

const DEFAULT_OUT := "reports/legibility"
const DEFAULT_WORST := 20
const DEFAULT_DUMP_SCALE := 8


func _ready() -> void:
	var args := _args()
	var sweep := LegibilitySweep.create(TerrainDB.load_default(), UnitDB.load_default())
	if sweep == null:
		push_error("legibility: the shipped art could not be read")
		get_tree().quit(1)
		return
	var started := Time.get_ticks_msec()
	var rows := sweep.run()
	var elapsed := Time.get_ticks_msec() - started
	var out := BalanceReportWriter.prepare_dir(str(args.get("out", DEFAULT_OUT)))
	if out == "":
		get_tree().quit(1)
		return
	var summary := _summary(sweep, rows, elapsed)
	BalanceReportWriter.write_csv(out.path_join("cells.csv"), rows, LegibilitySweep.COLUMNS)
	_write(out.path_join("summary.md"), summary)
	print(summary)
	print(_worst(rows, int(args.get("worst", DEFAULT_WORST))))
	if args.has("dump"):
		_dump(sweep, str(args["dump"]), int(args.get("dump-scale", DEFAULT_DUMP_SCALE)), out)
	get_tree().quit(0)


func _summary(sweep: LegibilitySweep, rows: Array[Dictionary], elapsed: int) -> String:
	var failed := LegibilitySweep.failures(rows).size()
	var lines: Array[String] = []
	lines.append("# Composite legibility sweep")
	lines.append("")
	lines.append("Ran %s, %d ms." % [Time.get_datetime_string_from_system(true), elapsed])
	lines.append(
		"One ramp step = %.4f luminance, measured off the shipped units atlas." % sweep.ramp_step
	)
	lines.append(
		"Bar: >= %.1f ramp steps of figure-vs-ground separation." % LegibilitySweep.PASS_STEPS
	)
	lines.append("")
	lines.append("%d cells, %d failing (%.1f%%)." % [rows.size(), failed, _percent(failed, rows)])
	for column in ["view", "overlay", "terrain", "faction", "state"]:
		lines.append("")
		lines.append_array(_table(column, LegibilitySweep.tally(rows, column)))
	lines.append("")
	lines.append_array(_table("unit", LegibilitySweep.tally(rows, "unit")))
	return "\n".join(lines)


func _table(column: String, counts: Dictionary[String, Array]) -> Array[String]:
	var lines: Array[String] = [
		"| %s | cells | failing | %% |" % column, "| --- | --- | --- | --- |"
	]
	var keys: Array = counts.keys()
	keys.sort()
	for key: String in keys:
		var pair: Array = counts[key]
		var share := 100.0 * float(pair[1]) / float(pair[0]) if pair[0] > 0 else 0.0
		lines.append("| %s | %d | %d | %.1f |" % [key, pair[0], pair[1], share])
	return lines


func _worst(rows: Array[Dictionary], count: int) -> String:
	var failed := LegibilitySweep.failures(rows)
	var lines: Array[String] = ["", "Worst %d of %d failing cells:" % [count, failed.size()]]
	for i in mini(count, failed.size()):
		var row := failed[i]
		var fields: Array = [
			row["steps"],
			row["view"],
			row["unit"],
			row["faction"],
			row["state"],
			row["terrain"],
			row["overlay"],
		]
		lines.append("  %5.2f steps  %-6s %-11s %-8s %-6s %-8s %s" % fields)
	return "\n".join(lines)


## `view:unit:faction:state:terrain:overlay` — the same six fields a report row
## is keyed by, so a cell in the table is copied straight onto the command line.
func _dump(sweep: LegibilitySweep, spec: String, scale: int, out: String) -> void:
	var parts := spec.split(":")
	if parts.size() != 6:
		push_error("legibility: --dump wants view:unit:faction:state:terrain:overlay")
		return
	var unit_type := sweep.unit_db.by_id(StringName(parts[1]))
	var row := LegibilitySweep.ROW_NAMES.find(parts[2])
	var overlay := LegibilityComposite.Overlay.keys().find(parts[5].to_upper())
	if unit_type == null or row < 0 or overlay < 0:
		push_error("legibility: --dump names art that does not exist: %s" % spec)
		return
	var cell := sweep.composite(unit_type, row, StringName(parts[4]), overlay, parts[0])
	cell.exhausted = parts[3] == "acted"
	var image := cell.to_image()
	image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var path := out.path_join("%s.png" % spec.replace(":", "_"))
	if image.save_png(path) != OK:
		push_error("legibility: cannot write %s" % path)
		return
	print("\nWrote %s" % path)


func _percent(failed: int, rows: Array[Dictionary]) -> float:
	return 100.0 * float(failed) / float(rows.size()) if not rows.is_empty() else 0.0


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("legibility: cannot write %s" % path)
		return
	file.store_string(text + "\n")


func _args() -> Dictionary:
	var parsed := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			continue
		var pair := argument.substr(2).split("=", true, 1)
		parsed[pair[0]] = pair[1] if pair.size() > 1 else "1"
	return parsed
