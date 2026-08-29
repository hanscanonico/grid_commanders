extends Node
## The composite legibility sweep (sprite design spec item 15): every unit kind,
## in every faction's colours, ready and acted, over every ground, under every
## wash the board lays on it, in every frame of the two clips it beats them
## through — and the same figures at the cut-in's resolution, in the two frames
## it poses them in.
## Each cell is measured for unit-vs-ground separation in ramp steps — along the
## figure's own contour, which is the headline, and over the whole figure, which
## is the secondary — and judged against LegibilitySweep.PASS_STEPS.
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
##     --gallery=docs/images/legibility_worst20.png
##                                where the worst-cell sheet is written; empty
##                                skips it
##     --dump=board:idle_a:tank:verdant:ready:woods:atlas:none
##                                writes that one composite as a PNG beside the
##                                report, magnified by --dump-scale
##     --dump-scale=8             nearest magnification of a dumped crop
##     --units=/tmp/round5/units_atlas.png
##                                score that units sheet instead of the shipped
##                                one, on today's grounds — how a past
##                                generation reads through today's ruler
##
## Writes cells.csv and summary.md under --out (gitignored), plus the gallery,
## which is the one thing a run publishes: it is committed review evidence that
## docs/sprite_legibility.md references, so it lands under docs/images/ rather
## than in the gitignored report directory, and it is deterministic — same art
## in, same sheet out.

const DEFAULT_OUT := "reports/legibility"
const DEFAULT_WORST := 20
const DEFAULT_DUMP_SCALE := 8
const DEFAULT_GALLERY := "docs/images/legibility_worst20.png"


func _ready() -> void:
	var args := _args()
	var sweep := LegibilitySweep.create(
		TerrainDB.load_default(), UnitDB.load_default(), str(args.get("units", ""))
	)
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
	_gallery(sweep, rows, str(args.get("gallery", DEFAULT_GALLERY)))
	if args.has("dump"):
		_dump(sweep, str(args["dump"]), int(args.get("dump-scale", DEFAULT_DUMP_SCALE)), out)
	get_tree().quit(0)


func _summary(sweep: LegibilitySweep, rows: Array[Dictionary], elapsed: int) -> String:
	var lines: Array[String] = []
	lines.append("# Composite legibility sweep")
	lines.append("")
	lines.append("Ran %s, %d ms." % [Time.get_datetime_string_from_system(true), elapsed])
	lines.append(
		(
			"One ramp step = %.4f luminance, measured off %s."
			% [sweep.ramp_step, sweep.art.units_source]
		)
	)
	lines.append(
		(
			"Bar: >= %.1f ramp steps of figure-vs-ground separation, >= %.1f under the fog shroud."
			% [LegibilitySweep.PASS_STEPS, LegibilitySweep.FOG_PASS_STEPS]
		)
	)
	lines.append(
		(
			"Read along the figure's contour, against the ground %d px outside it, at its p%d."
			% [LegibilityMetric.EDGE_BAND_PX, int(LegibilityMetric.EDGE_PERCENTILE * 100.0)]
		)
	)
	lines.append("")
	lines.append(
		(
			"Second reading: CIE76 chroma distance over the same pairs, cleared at %.0f."
			% LegibilitySweep.HUE_CLEAR
		)
	)
	lines.append("Secondary: the whole-figure medians, `steps` and `hue`, which decide nothing.")
	lines.append_array(_frame_lines())
	lines.append("")
	var clear := LegibilitySweep.unfogged(rows)
	lines.append_array(_class_lines("Clear", clear))
	lines.append("")
	lines.append_array(_class_lines("Fogged", LegibilitySweep.fogged(rows)))
	lines.append("")
	lines.append("Every table below is the clear class; the fog class is the line above it.")
	for column in ["view", "frame", "overlay", "terrain", "faction", "state"]:
		lines.append("")
		lines.append_array(_table(column, LegibilitySweep.tally(clear, column)))
	lines.append("")
	lines.append_array(_table("terrain/variant", LegibilitySweep.tally_variants(clear)))
	lines.append("")
	lines.append_array(_table("unit", LegibilitySweep.tally(clear, "unit")))
	return "\n".join(lines)


## Which shipped sheet each frame of each view was read off, so a per-frame
## table in the report names a file.
func _frame_lines() -> Array[String]:
	var lines: Array[String] = ["", "| view | frame | sheet |", "| --- | --- | --- |"]
	for view in [LegibilitySweep.BOARD_VIEW, LegibilitySweep.CUTIN_VIEW]:
		for frame in LegibilitySweep.frames_of(view):
			lines.append("| %s | %s | %s |" % [view, frame, LegibilitySweep.sheet_of(view, frame)])
	return lines


## The headline for one class of cells. Two of them, because the fog shroud is
## judged against its own bar and a rate mixing the two answers nothing.
func _class_lines(label: String, rows: Array[Dictionary]) -> Array[String]:
	var failed := LegibilitySweep.failures(rows).size()
	var carried := LegibilitySweep.hue_carried(rows)
	return [
		"%s: %d cells, %d failing (%.1f%%)." % [label, rows.size(), failed, _percent(failed, rows)],
		(
			"  %d of those clear the hue bound (%.1f%%): value-blind, not illegible."
			% [carried, 100.0 * float(carried) / float(failed) if failed > 0 else 0.0]
		),
	]


func _table(column: String, counts: Dictionary[String, Array]) -> Array[String]:
	var lines: Array[String] = [
		"| %s | cells | failing | %% | hue-carried |" % column,
		"| --- | --- | --- | --- | --- |",
	]
	var keys: Array = counts.keys()
	keys.sort()
	for key: String in keys:
		var triple: Array = counts[key]
		var share := 100.0 * float(triple[1]) / float(triple[0]) if triple[0] > 0 else 0.0
		lines.append("| %s | %d | %d | %.1f | %d |" % [key, triple[0], triple[1], share, triple[2]])
	return lines


func _worst(rows: Array[Dictionary], count: int) -> String:
	var failed := LegibilitySweep.failures(rows)
	var lines: Array[String] = [
		"",
		(
			"Worst %d of %d failing cells, least of the *further* reading first:"
			% [count, failed.size()]
		)
	]
	for i in mini(count, failed.size()):
		var row := failed[i]
		var fields: Array = [
			row["edge_steps"],
			row["edge_hue"],
			row["view"],
			row["frame"],
			row["unit"],
			row["faction"],
			row["state"],
			"%s/%s" % [row["terrain"], row["variant"]],
			row["overlay"],
		]
		lines.append("  edge %5.2f  hue %5.1f  %-6s %-6s %-11s %-8s %-6s %-14s %s" % fields)
	return "\n".join(lines)


## The worst-cell sheet, the run's one committed artifact.
func _gallery(sweep: LegibilitySweep, rows: Array[Dictionary], path: String) -> void:
	if path == "":
		return
	var image := LegibilityGallery.compose(sweep, rows, LegibilityGallery.CELLS)
	if image == null:
		push_error("legibility: the gallery could not be drawn")
		return
	var absolute := ProjectSettings.globalize_path("res://").path_join(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		push_error("legibility: cannot create %s" % absolute.get_base_dir())
		return
	if image.save_png(absolute) != OK:
		push_error("legibility: cannot write %s" % absolute)
		return
	print("\nWrote %s (%d x %d)" % [path, image.get_width(), image.get_height()])


## `view:frame:unit:faction:state:terrain:variant:overlay` — the same eight fields a
## report row is keyed by, so a cell in the table is copied straight onto the
## command line.
func _dump(sweep: LegibilitySweep, spec: String, scale: int, out: String) -> void:
	var parts := spec.split(":")
	if parts.size() != LegibilitySweep.KEYS.size():
		push_error("legibility: --dump wants %s" % ":".join(LegibilitySweep.KEYS))
		return
	var keyed := {}
	for i in LegibilitySweep.KEYS.size():
		keyed[LegibilitySweep.KEYS[i]] = parts[i]
	var cell := sweep.composite_for(keyed)
	if cell == null:
		push_error("legibility: --dump names art that does not exist: %s" % spec)
		return
	var image := cell.to_image()
	image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var path := out.path_join("%s.png" % spec.replace(":", "_"))
	if image.save_png(path) != OK:
		push_error("legibility: cannot write %s" % path)
		return
	var figure := LegibilityMetric.median_colour(cell.figure_colours())
	var ground := LegibilityMetric.median_colour(cell.ground_colours())
	var edge := LegibilityMetric.edge_reading(cell.pixels(), cell.coverage(), cell.size)
	print("\nWrote %s" % path)
	print(
		(
			"  edge %.2f steps, hue %.2f — the verdict, taken along the contour"
			% [LegibilityMetric.in_steps(edge.x, sweep.ramp_step), edge.y]
		)
	)
	print(
		(
			"  figure #%s, ground #%s, median %.2f steps, hue %.2f — the secondary's two colours"
			% [
				figure.to_html(false),
				ground.to_html(false),
				LegibilityMetric.separation(
					cell.figure_luminances(), cell.ground_luminances(), sweep.ramp_step
				),
				LegibilityMetric.hue_distance(figure, ground)
			]
		)
	)


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
