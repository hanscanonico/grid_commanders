extends GutTest
## The capture cut-in's light shaft: a static, pure quad builder, checked the way
## PathArrow.segments is — without standing up the cut-in.
##
## Worth pinning because a polygon's failure is in its *winding*, not in where it
## sits: the left shaft was wound so its bottom edge crossed back under the quad,
## and Godot's triangulator refuses a self-crossing polygon outright. The shaft
## simply did not draw, and the frame logged "Invalid polygon data, triangulation
## failed." for it.

const HORIZON := 150.0
const BASE := Vector2(320.0, 300.0)


func _from() -> Vector2:
	return Vector2(CaptureBackdrop.sun_at(640.0, HORIZON).x, HORIZON)


func test_both_shafts_are_polygons_the_triangulator_accepts() -> void:
	for side in [-1.0, 1.0]:
		var wedge := CaptureBackdrop.light_shaft_wedge(_from(), BASE, side)
		assert_gt(Geometry2D.triangulate_polygon(wedge).size(), 0, "side %s triangulates" % side)


func test_a_shaft_widens_from_the_horizon_to_the_feet() -> void:
	for side in [-1.0, 1.0]:
		var wedge := CaptureBackdrop.light_shaft_wedge(_from(), BASE, side)
		var mouth := absf(wedge[1].x - wedge[0].x)
		var feet := absf(wedge[2].x - wedge[3].x)
		assert_gt(feet, mouth, "side %s flares" % side)


func test_the_two_shafts_lean_opposite_ways() -> void:
	var from := _from()
	var left := CaptureBackdrop.light_shaft_wedge(from, BASE, -1.0)
	var right := CaptureBackdrop.light_shaft_wedge(from, BASE, 1.0)
	assert_lt(left[3].x, BASE.x)
	assert_gt(right[3].x, BASE.x)
