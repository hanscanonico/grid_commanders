extends GutTest
## The legibility sweep's arithmetic: luminance, the wash blend, the median and
## the ramp step. Pure and static like PathArrow.segments, so the metric the
## offline sweep reports in is checked without reading an atlas or composing a
## cell.
##
## The sweep itself stays offline (`make legibility-check`) for the Balance Lab's
## reason — it measures shipped art and gates nothing — but the number it reports
## in has to mean the same thing every run, which is what this pins.

const SLOTS := LegibilityMetric.RAMP_SLOTS
## The step of the grey row below, which the assertions read against.
const GREY_STEP := 0.15
## Where that row starts, chosen so no slot of it is black — a slot both rows
## painted the same colour would read as shared ink rather than as ramp.
const GREY_FLOOR := 0.1


func _sample(values: Array) -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	for value: float in values:
		packed.append(value)
	return packed


func test_luminance_weights_green_most() -> void:
	assert_almost_eq(LegibilityMetric.luminance(Color.BLACK), 0.0, 0.0001)
	assert_almost_eq(LegibilityMetric.luminance(Color.WHITE), 1.0, 0.0001)
	assert_gt(
		LegibilityMetric.luminance(Color.GREEN),
		LegibilityMetric.luminance(Color.RED),
		"green reads"
	)


func test_over_is_straight_alpha_and_opaque() -> void:
	var blended := LegibilityMetric.over(Color(1, 1, 1, 0.25), Color(0, 0, 0, 1))
	assert_almost_eq(blended.r, 0.25, 0.0001)
	assert_almost_eq(blended.a, 1.0, 0.0001)


func test_over_with_a_clear_wash_leaves_the_ground() -> void:
	var ground := Color(0.2, 0.4, 0.6, 1)
	assert_eq(LegibilityMetric.over(Color(1, 0, 0, 0.0), ground), ground)


func test_median_ignores_collection_order() -> void:
	assert_almost_eq(LegibilityMetric.median(_sample([0.9, 0.1, 0.5])), 0.5, 0.0001)
	assert_almost_eq(LegibilityMetric.median(_sample([0.1, 0.5, 0.9])), 0.5, 0.0001)
	assert_almost_eq(LegibilityMetric.median(_sample([0.2, 0.4])), 0.3, 0.0001)
	assert_eq(LegibilityMetric.median(PackedFloat32Array()), 0.0, "an empty sample has no median")


func test_separation_counts_ramp_steps_either_way() -> void:
	var light := _sample([0.8, 0.8, 0.8])
	var dark := _sample([0.5, 0.5, 0.5])
	assert_almost_eq(LegibilityMetric.separation(light, dark, 0.15), 2.0, 0.0001)
	assert_almost_eq(LegibilityMetric.separation(dark, light, 0.15), 2.0, 0.0001)


func test_separation_of_a_figure_on_its_own_colour_is_zero() -> void:
	var same := _sample([0.42, 0.42])
	assert_almost_eq(LegibilityMetric.separation(same, same, 0.15), 0.0, 0.0001)


func test_separation_without_a_ramp_is_zero_rather_than_infinite() -> void:
	assert_eq(LegibilityMetric.separation(_sample([1.0]), _sample([0.0]), 0.0), 0.0)


## A sheet of two rows that disagree everywhere: evenly spaced greys against the
## same levels in red. The ramp is what the rows disagree about, and its step is
## the gap between two of its slots.
func _ramp_atlas() -> Image:
	var image := Image.create(SLOTS, 2, false, Image.FORMAT_RGBA8)
	for slot in SLOTS:
		var level := GREY_FLOOR + GREY_STEP * float(slot)
		image.set_pixel(slot, 0, Color(level, level, level))
		image.set_pixel(slot, 1, Color(level, 0.0, 0.0))
	return image


## The grey row steps by GREY_STEP in luminance and the red row by that much of
## red alone; the sheet's step is the mean over the rows. The tolerance is the
## 8-bit sheet's rounding, not slack in the metric.
func test_ramp_step_is_the_mean_gap_between_two_slots() -> void:
	var red_step := LegibilityMetric.luminance(Color(GREY_STEP, 0, 0))
	assert_almost_eq(
		LegibilityMetric.ramp_step(_ramp_atlas(), 1, 2), (GREY_STEP + red_step) / 2.0, 1.0 / 255.0
	)


func test_ramp_step_ignores_pixels_every_row_paints_the_same() -> void:
	var image := _ramp_atlas()
	var shared := Image.create(SLOTS + 4, 2, false, Image.FORMAT_RGBA8)
	shared.fill(Color(0.02, 0.02, 0.02))
	for slot in SLOTS:
		shared.set_pixel(slot, 0, image.get_pixel(slot, 0))
		shared.set_pixel(slot, 1, image.get_pixel(slot, 1))
	assert_almost_eq(
		LegibilityMetric.ramp_step(shared, 1, 2), LegibilityMetric.ramp_step(image, 1, 2), 0.0001
	)


func test_ramp_step_of_a_sheet_with_no_ramp_is_zero() -> void:
	var flat := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	flat.fill(Color(0.5, 0.5, 0.5))
	assert_eq(LegibilityMetric.ramp_step(flat, 1, 2), 0.0, "nothing to read a step off")
