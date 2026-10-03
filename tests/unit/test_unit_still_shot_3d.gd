extends GutTest
## UnitStillShot3D: how a unit's 3D icon still is framed — pure arithmetic, so
## the framing is checked without rendering a still.

const TOLERANCE := 0.0001


## Off the origin on purpose: a model's box is not centred on its root, and a
## centred box would frame correctly even with the aim pinned to the origin.
func _box() -> AABB:
	return AABB(Vector3(-0.2, 0.05, -0.4), Vector3(0.8, 0.35, 0.5))


func test_the_lens_looks_down_at_the_flank_with_the_nose_toward_the_right() -> void:
	var frame := UnitStillShot3D.basis()
	assert_lt(UnitStillShot3D.forward().y, 0.0, "the lens looks down")
	assert_gt(frame.x.x, 0.0, "the model's nose, +X, points right on screen")
	assert_gt(frame.z.z, 0.0, "the lens stands off the model's +Z flank")
	assert_gt(frame.z.x, 0.0, "swung toward the nose: a three-quarter view")
	assert_almost_eq(frame.x.dot(frame.y), 0.0, TOLERANCE, "right and up are square")
	assert_gt(frame.y.y, 0.0, "the frame's up leans up")


func test_the_lens_aims_at_the_middle_of_the_model_as_it_is_seen() -> void:
	var box := _box()
	var frame := UnitStillShot3D.basis()
	var aim := UnitStillShot3D.aim(box)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i in 8:
		var corner := box.get_endpoint(i) - aim
		var at := Vector2(frame.x.dot(corner), frame.y.dot(corner))
		low = low.min(at)
		high = high.max(at)
	assert_almost_eq(low.x, -high.x, TOLERANCE, "centred across the frame")
	assert_almost_eq(low.y, -high.y, TOLERANCE, "centred up and down the frame")
	var eye := UnitStillShot3D.eye(box)
	assert_almost_eq(eye.distance_to(aim), UnitStillShot3D.LENS_DISTANCE, TOLERANCE)


func test_the_square_frame_holds_the_whole_model_with_air_round_it() -> void:
	var box := _box()
	var frame := UnitStillShot3D.basis()
	var aim := UnitStillShot3D.aim(box)
	var half := UnitStillShot3D.lens_height(box) / 2.0
	for i in 8:
		var corner := box.get_endpoint(i) - aim
		assert_lt(absf(frame.x.dot(corner)), half, "corner %d inside across" % i)
		assert_lt(absf(frame.y.dot(corner)), half, "corner %d inside up and down" % i)


func test_a_bigger_model_is_framed_wider() -> void:
	var box := _box()
	var bigger := AABB(box.position * 2.0, box.size * 2.0)
	assert_almost_eq(
		UnitStillShot3D.lens_height(bigger), UnitStillShot3D.lens_height(box) * 2.0, TOLERANCE
	)


func test_the_still_is_the_icon_slot_in_screen_pixels() -> void:
	assert_eq(UnitStillShot3D.pixels(1.0), UiTheme.MENU_ICON)
	assert_eq(UnitStillShot3D.pixels(2.0), UiTheme.MENU_ICON * 2)
	assert_eq(UnitStillShot3D.pixels(1.5), UiTheme.MENU_ICON * 3 / 2)
	assert_eq(UnitStillShot3D.pixels(0.5), UiTheme.MENU_ICON, "never under the slot's own size")


func test_each_army_and_size_has_its_own_still() -> void:
	var key := UnitStillShot3D.key(&"tank", 1, 32)
	assert_ne(key, UnitStillShot3D.key(&"tank", 2, 32))
	assert_ne(key, UnitStillShot3D.key(&"tank", 1, 48))
	assert_ne(key, UnitStillShot3D.key(&"md_tank", 1, 32))
