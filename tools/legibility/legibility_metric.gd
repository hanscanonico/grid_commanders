class_name LegibilityMetric
extends RefCounted
## The pure arithmetic behind the composite legibility sweep: what a pixel is
## worth, what one ramp step is worth, and how far a figure stands off its
## ground once every wash has composited.
##
## Node-free and free of any art path, so the suite checks the metric without
## reading a sheet (tests/unit/test_legibility_metric.gd). The pixels themselves
## are LegibilityArt's and the stacking order is LegibilityComposite's.
##
## ## The metric
##
## Separation is stated in **ramp steps**: the median luminance of the figure's
## own pixels, minus the median luminance of the ground plate under it, divided
## by one step of the shipped faction ramp. Two composites a step apart differ
## by exactly the shading gap the art uses to tell one face of a hull from the
## next; a figure less than a step off its ground is painted in a value the
## ground already holds.
##
## Median rather than mean on both sides: a unit is an outline, a body and a
## highlight, and a mean is dragged around by the outline's black; a median
## reads the value the shape mostly is. The ground is measured over the whole
## cell rather than only the pixels the figure leaves showing, so the number
## belongs to the tile and stays comparable across units of different footprints.
##
## Luminance is Rec.709 over the stored (sRGB) components, which is the space
## the washes composite in — 2D blending in this project is over stored values,
## not linearised ones — so the ramp and the composites are read on one scale.

## Slots in one faction ramp. sprite_generator's contract, recorded in
## assets/LICENSES.md ("indexed six-slot faction ramps"); the step below is the
## gap between two neighbouring slots.
const RAMP_SLOTS := 6


## Rec.709 luminance of a stored colour, alpha ignored.
static func luminance(colour: Color) -> float:
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b


## Straight "source over" alpha compositing, the blend a translucent wash lands
## with. The result is opaque, because every stack here starts on opaque ground.
static func over(fg: Color, bg: Color) -> Color:
	var a := fg.a
	return Color(
		fg.r * a + bg.r * (1.0 - a), fg.g * a + bg.g * (1.0 - a), fg.b * a + bg.b * (1.0 - a), 1.0
	)


## Median of a sample, 0.0 for an empty one. Sorts a copy: a caller's sample is
## the order it collected the pixels in and nothing may depend on that.
static func median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return (sorted[middle - 1] + sorted[middle]) * 0.5


## Separation between a figure sample and a ground sample, in ramp steps.
## Unsigned: a figure that is darker than its ground reads as well as one that
## is lighter, and the sweep records the two medians beside it either way.
static func separation(
	figure: PackedFloat32Array, ground: PackedFloat32Array, step: float
) -> float:
	if step <= 0.0:
		return 0.0
	return absf(median(figure) - median(ground)) / step


## One ramp step of the shipped units atlas, in luminance.
##
## Derived from the sheet rather than restated from the generator: the same
## model is drawn in every faction row, so a pixel where the rows disagree is
## one the ramp painted and a pixel where they all agree is shared ink — an
## outline, a track, a canopy. Tallying each row's colours over the disagreeing
## pixels leaves that row's ramp on top, and its RAMP_SLOTS most-used colours
## are the ramp. A row's step is its span over RAMP_SLOTS - 1 gaps; the sheet's
## is the mean over the rows, since one number is what a bar can be stated in.
static func ramp_step(atlas: Image, cell_px: int, rows: int) -> float:
	var total := 0.0
	var counted := 0
	var tallies: Array[Dictionary] = []
	for row in rows:
		tallies.append({})
	for y in cell_px:
		for x in atlas.get_width():
			_tally_row_colours(atlas, tallies, cell_px, x, y)
	for row in rows:
		var step := _row_step(tallies[row])
		if step > 0.0:
			total += step
			counted += 1
	return total / counted if counted > 0 else 0.0


## Adds one column of pixels — the same (x, y) in every row — to the tallies,
## unless every row painted it the same colour, in which case it is shared ink.
static func _tally_row_colours(
	atlas: Image, tallies: Array[Dictionary], cell_px: int, x: int, y: int
) -> void:
	var colours: Array[Color] = []
	for row in tallies.size():
		colours.append(atlas.get_pixel(x, row * cell_px + y))
	var shared := true
	for colour in colours:
		if colour != colours[0]:
			shared = false
			break
	if shared:
		return
	for row in tallies.size():
		if colours[row].a <= 0.0:
			continue
		var key := colours[row]
		tallies[row][key] = int(tallies[row].get(key, 0)) + 1


## The luminance span of one row's ramp over its gaps, or 0.0 for a row that
## carries fewer painted colours than the ramp has slots.
static func _row_step(tally: Dictionary) -> float:
	var colours: Array[Color] = []
	colours.assign(tally.keys())
	if colours.size() < RAMP_SLOTS:
		return 0.0
	# Count first, luminance second: a tie settled by dictionary order would make
	# the step depend on the order the sheet happened to be walked in.
	colours.sort_custom(
		func(a: Color, b: Color) -> bool:
			if tally[a] != tally[b]:
				return tally[a] > tally[b]
			return luminance(a) < luminance(b)
	)
	var levels: Array[float] = []
	for i in RAMP_SLOTS:
		levels.append(luminance(colours[i]))
	levels.sort()
	return (levels[RAMP_SLOTS - 1] - levels[0]) / float(RAMP_SLOTS - 1)
