extends GutTest
## The edge-band reading: the contour of a figure against the ground just
## outside it, at the p25 of the perimeter. Round 8's headline, and the reason
## the whole-figure median was demoted — the last test here is that reason,
## stated as a figure with one side that vanishes.
##
## Pure and static like the rest of LegibilityMetric, so the reading the offline
## sweep is judged on is checked without reading an atlas or composing a cell.
## Its sibling suite, test_legibility_metric.gd, holds the medians and the ramp,
## and test_stats.gd holds the rank the p25 is taken at.


func _sample(values: Array) -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	for value: float in values:
		packed.append(value)
	return packed


## A `side`-wide square cell of `ground`, with a `figure`-coloured square of
## `figure_side` centred in it. Returned as the pair the edge reading takes: the
## composited pixels and the silhouette over them.
func _cell(side: int, figure_side: int, ground: Color, figure: Color) -> Array:
	var pixels := PackedColorArray()
	var covered := PackedByteArray()
	var margin := (side - figure_side) / 2
	for y in side:
		for x in side:
			var inside := (
				x >= margin
				and x < margin + figure_side
				and y >= margin
				and y < margin + figure_side
			)
			pixels.append(figure if inside else ground)
			covered.append(1 if inside else 0)
	return [pixels, covered]


func test_in_steps_is_unsigned_and_survives_a_sheet_with_no_ramp() -> void:
	assert_almost_eq(LegibilityMetric.in_steps(0.3, 0.15), 2.0, 0.0001)
	assert_almost_eq(LegibilityMetric.in_steps(-0.3, 0.15), 2.0, 0.0001)
	assert_eq(LegibilityMetric.in_steps(1.0, 0.0), 0.0, "no ramp to state it against")


## A filled square's contour is its rim: four sides of it, corners counted once,
## and nothing from inside.
func test_boundary_pixels_are_the_rim_of_the_silhouette() -> void:
	var built := _cell(12, 6, Color.BLACK, Color.WHITE)
	var boundary := LegibilityMetric.boundary_pixels(built[1], 12)
	assert_eq(boundary.size(), 6 * 6 - 4 * 4, "the rim of a 6x6 square")


## A figure drawn out to the cell's edge has a contour there: the tile beside it
## is ground the composite simply does not hold.
func test_boundary_pixels_count_the_cell_edge_as_ground() -> void:
	var covered := PackedByteArray()
	for index in 16:
		covered.append(1)
	assert_eq(LegibilityMetric.boundary_pixels(covered, 4).size(), 12, "the cell's own outer ring")


func test_edge_reading_measures_the_contour_against_the_band_outside_it() -> void:
	var ground := Color(0.2, 0.2, 0.2)
	var figure := Color(0.8, 0.8, 0.8)
	var built := _cell(16, 8, ground, figure)
	var reading := LegibilityMetric.edge_reading(built[0], built[1], 16)
	assert_almost_eq(reading.x, 0.6, 0.0001)
	assert_almost_eq(reading.y, 0.0, 0.001, "two greys differ in no colour")


func test_edge_reading_of_a_figure_on_its_own_colour_is_nothing() -> void:
	var flat := Color(0.42, 0.42, 0.42)
	var built := _cell(16, 8, flat, flat)
	assert_almost_eq(LegibilityMetric.edge_reading(built[0], built[1], 16).x, 0.0, 0.0001)


func test_edge_reading_is_blind_to_the_body_it_never_looks_at() -> void:
	var ground := Color(0.2, 0.2, 0.2)
	var built := _cell(16, 8, ground, Color(0.8, 0.8, 0.8))
	var pixels: PackedColorArray = built[0]
	var covered: PackedByteArray = built[1]
	var before := LegibilityMetric.edge_reading(pixels, covered, 16)
	for index in pixels.size():
		var x := index % 16
		var y := index / 16
		if x > 4 and x < 11 and y > 4 and y < 11:
			pixels[index] = Color.RED
	assert_eq(LegibilityMetric.edge_reading(pixels, covered, 16), before, "the middle says nothing")


## Why the round-7 median was superseded. A figure with three bright sides and
## one painted its ground's own colour reads as a clean 4.0 steps on the median
## and as nothing at all on the contour, which is what a shape with a side that
## vanishes looks like on screen.
func test_edge_reading_catches_a_side_the_median_cannot() -> void:
	var ground := Color(0.2, 0.2, 0.2)
	var built := _cell(16, 8, ground, Color(0.8, 0.8, 0.8))
	var pixels: PackedColorArray = built[0]
	var covered: PackedByteArray = built[1]
	for y in range(4, 12):
		pixels[y * 16 + 4] = ground
	var figure := PackedFloat32Array()
	var plate := PackedFloat32Array()
	for index in pixels.size():
		if covered[index] == 0:
			plate.append(LegibilityMetric.luminance(pixels[index]))
		else:
			figure.append(LegibilityMetric.luminance(pixels[index]))
	assert_gt(LegibilityMetric.separation(figure, plate, 0.15), 3.9, "the mass reads as separated")
	assert_almost_eq(LegibilityMetric.edge_reading(pixels, covered, 16).x, 0.0, 0.0001)


func test_edge_reading_of_a_cell_with_no_figure_is_nothing() -> void:
	var built := _cell(16, 0, Color.WHITE, Color.BLACK)
	assert_eq(LegibilityMetric.edge_reading(built[0], built[1], 16), Vector2.ZERO)
