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
## ## The edge reading — the headline since round 8
##
## Figure-ground separation is a **boundary** phenomenon: what tells a shape
## from what it stands on is its contour, not the average of its middle. So the
## reading the sweep is judged on compares each pixel of the silhouette's
## perimeter against the ground within `EDGE_BAND_PX` **outside** that
## silhouette, and reports the **p25** of that comparison along the whole
## perimeter — in luminance, which `in_steps` states in ramp steps, and in the
## same chroma-plane CIE76 distance `hue_distance` states.
##
## p25 rather than a median or a mean, and this is the whole reason the round-7
## ruler had to be superseded: a figure can carry a bright back and a side that
## vanishes into the ground, and both a median and a mean of the perimeter score
## it on the back. A quarter of an outline may go soft; more than a quarter is a
## shape with a missing edge.
##
## ## The median reading — the cheap secondary
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
##
## ## The hue measure
##
## Separation in ramp steps is value only, so a figure that differs from its
## ground in colour alone scores zero on it. `hue_distance` is the second
## reading: **CIE76 in the chroma plane** — `sqrt(da^2 + db^2)` between the two
## colours in CIE Lab over D65, taken between exactly the two colours the value
## bar compared, which is what `median_colour` exists to name. Lab is reached the
## standard way (sRGB -> linear through `Color.srgb_to_linear`, the linear ->
## XYZ matrix, then the Lab cube root), so it is the one place in this instrument
## that leaves the stored space.
##
## CIE76 rather than CIE94 or CIEDE2000 deliberately: the later formulas correct
## for perceptual non-uniformities at small distances, and nothing here is a
## small distance — the question is whether two things on screen are obviously
## different colours, not how close a near-match is.
##
## **The lightness term is dropped, and that is the whole point**: full CIE76
## carries `dL` too, which is the difference the ramp-step bar already measures,
## so a column holding it would score the same pair twice and read as a second
## opinion on value. Two greys are 0 apart here however far apart they are on
## the bar, and that is the reading the bar cannot give.

## Slots in one faction ramp. sprite_generator's contract, recorded in
## assets/LICENSES.md ("indexed six-slot faction ramps"); the step below is the
## gap between two neighbouring slots.
const RAMP_SLOTS := 6
## CIE D65, the white point the sRGB primaries are stated against.
const WHITE_POINT := Vector3(0.95047, 1.0, 1.08883)
## The Lab cube root's linear segment: CIE's own epsilon and kappa, as the
## integer ratios they are defined by.
const LAB_EPSILON := 216.0 / 24389.0
const LAB_KAPPA := 24389.0 / 27.0
## How far outside the silhouette a boundary pixel's ground is read, in
## composite pixels — three, the round-8 review's own band. Wide enough that the
## ground it names is the ground the eye reads that contour against, narrow
## enough that it is still *that* contour's ground rather than the tile average
## the median reading already reports.
const EDGE_BAND_PX := 3
## Which point of the perimeter the edge reading reports, as a share of it.
const EDGE_PERCENTILE := 0.25


## The p25 of the perimeter's luminance gap and of its chroma gap: for every
## pixel of the figure's contour, how far it stands from the ground within
## EDGE_BAND_PX outside the silhouette. `x` is luminance, which `in_steps`
## states in ramp steps; `y` is the chroma-plane CIE76 distance.
##
## `pixels` is the composited cell row-major and `covered` is one byte per pixel
## of it, non-zero where the figure covers the cell.
static func edge_reading(pixels: PackedColorArray, covered: PackedByteArray, size: int) -> Vector2:
	var lightness := PackedFloat32Array()
	var chroma := PackedFloat32Array()
	for index in boundary_pixels(covered, size):
		var band := _band_colours(pixels, covered, size, index)
		if band.is_empty():
			continue
		var ground := median_colour(band)
		lightness.append(absf(luminance(pixels[index]) - luminance(ground)))
		chroma.append(hue_distance(pixels[index], ground))
	return Vector2(percentile(lightness, EDGE_PERCENTILE), percentile(chroma, EDGE_PERCENTILE))


## Every figure pixel with ground directly beside it — the silhouette's contour,
## four-connected like every other distance in this project.
static func boundary_pixels(covered: PackedByteArray, size: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	for index in covered.size():
		if covered[index] == 0:
			continue
		var x := index % size
		var y := index / size
		if (
			_is_ground(covered, size, x - 1, y)
			or _is_ground(covered, size, x + 1, y)
			or _is_ground(covered, size, x, y - 1)
			or _is_ground(covered, size, x, y + 1)
		):
			found.append(index)
	return found


## The value `fraction` of the way through a sample, by nearest rank — never an
## interpolation between two, so the number reported is a gap some pixel of the
## contour really has. 0.0 for an empty sample, as `median` answers.
static func percentile(values: PackedFloat32Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var rank := clampi(ceili(fraction * float(sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[rank]


## A luminance gap in ramp steps, unsigned. 0.0 without a ramp to state it
## against, which is the one place this instrument divides by the step.
static func in_steps(gap: float, step: float) -> float:
	return absf(gap) / step if step > 0.0 else 0.0


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


## The luminance of every colour in a sample, in the order it was collected.
static func luminances(colours: PackedColorArray) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for colour in colours:
		values.append(luminance(colour))
	return values


## The colour at the middle of a sample ordered by luminance — the one the value
## bar's median is the luminance of, so the two measures compare the same pair.
## Black for an empty sample. Ties are settled by the components rather than by
## the order the pixels were collected, and an even sample averages its two
## middles exactly as `median` does, which is what keeps the two in step.
static func median_colour(colours: PackedColorArray) -> Color:
	if colours.is_empty():
		return Color.BLACK
	var levels := PackedFloat64Array()
	for colour in colours:
		levels.append(luminance(colour))
	levels.sort()
	var middle := levels.size() / 2
	if levels.size() % 2 == 1:
		return _colour_at(colours, levels[middle])
	return (_colour_at(colours, levels[middle - 1]) + _colour_at(colours, levels[middle])) * 0.5


## CIE Lab of a stored (sRGB) colour, alpha ignored.
static func lab(colour: Color) -> Vector3:
	var linear := colour.srgb_to_linear()
	var x := 0.4124564 * linear.r + 0.3575761 * linear.g + 0.1804375 * linear.b
	var y := 0.2126729 * linear.r + 0.7151522 * linear.g + 0.0721750 * linear.b
	var z := 0.0193339 * linear.r + 0.1191920 * linear.g + 0.9503041 * linear.b
	var fx := _lab_f(x / WHITE_POINT.x)
	var fy := _lab_f(y / WHITE_POINT.y)
	var fz := _lab_f(z / WHITE_POINT.z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


## How far apart two colours are in colour, ignoring how far apart they are in
## lightness: the CIE76 distance taken in Lab's chroma plane.
static func hue_distance(a: Color, b: Color) -> float:
	var first := lab(a)
	var second := lab(b)
	return Vector2(first.y - second.y, first.z - second.z).length()


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
	return in_steps(median(figure) - median(ground), step)


## The ground inside the band around one boundary pixel, in scan order.
static func _band_colours(
	pixels: PackedColorArray, covered: PackedByteArray, size: int, index: int
) -> PackedColorArray:
	var band := PackedColorArray()
	var centre := Vector2i(index % size, index / size)
	for y in range(maxi(centre.y - EDGE_BAND_PX, 0), mini(centre.y + EDGE_BAND_PX, size - 1) + 1):
		for x in range(
			maxi(centre.x - EDGE_BAND_PX, 0), mini(centre.x + EDGE_BAND_PX, size - 1) + 1
		):
			var at := y * size + x
			if covered[at] == 0:
				band.append(pixels[at])
	return band


## Off the cell counts as ground: a figure drawn out to the tile's edge has a
## contour there, and the band that contour is read against is whatever of the
## cell is left beside it.
static func _is_ground(covered: PackedByteArray, size: int, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= size or y >= size:
		return true
	return covered[y * size + x] == 0


## The least colour of a sample painted at exactly `level`, "least" being by
## components — a scan rather than a sort, and one that settles the case two
## different colours share a luminance without ever asking what order the pixels
## arrived in.
static func _colour_at(colours: PackedColorArray, level: float) -> Color:
	var found := Color.BLACK
	var seen := false
	for colour in colours:
		if luminance(colour) != level:
			continue
		if not seen or _lower_components(colour, found):
			found = colour
			seen = true
	return found


static func _lower_components(a: Color, b: Color) -> bool:
	if a.r != b.r:
		return a.r < b.r
	if a.g != b.g:
		return a.g < b.g
	return a.b < b.b


static func _lab_f(ratio: float) -> float:
	if ratio > LAB_EPSILON:
		return pow(ratio, 1.0 / 3.0)
	return (LAB_KAPPA * ratio + 16.0) / 116.0


## One ramp step of the shipped units atlas, in luminance.
##
## Derived from the sheet rather than restated from the generator: the same
## model is drawn in every faction row, so a pixel where the rows disagree is
## one the ramp painted and a pixel where they all agree is shared ink — an
## outline, a track, a canopy. Tallying each row's colours over the disagreeing
## pixels leaves that row's ramp on top, and its RAMP_SLOTS most-used colours
## are the ramp. A row's step is its span over RAMP_SLOTS - 1 gaps; the sheet's
## is the mean over the rows, since one number is what a bar can be stated in.
static func ramp_step(atlas: Image, cell_h: int, rows: int) -> float:
	var total := 0.0
	var counted := 0
	var tallies: Array[Dictionary] = []
	for row in rows:
		tallies.append({})
	for y in cell_h:
		for x in atlas.get_width():
			_tally_row_colours(atlas, tallies, cell_h, x, y)
	for row in rows:
		var step := _row_step(tallies[row])
		if step > 0.0:
			total += step
			counted += 1
	return total / counted if counted > 0 else 0.0


## Adds one column of pixels — the same (x, y) in every row — to the tallies,
## unless every row painted it the same colour, in which case it is shared ink.
static func _tally_row_colours(
	atlas: Image, tallies: Array[Dictionary], cell_h: int, x: int, y: int
) -> void:
	var colours: Array[Color] = []
	for row in tallies.size():
		colours.append(atlas.get_pixel(x, row * cell_h + y))
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
