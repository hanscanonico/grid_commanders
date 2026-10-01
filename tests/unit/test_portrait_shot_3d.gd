extends GutTest
## PortraitShot3D: how a general's 3D portrait still is framed on the pixel
## bust's grid — pure arithmetic, so the framing rules are checked without
## rendering a still.

const VARIANTS: Array[StringName] = [PortraitShot3D.BUST, PortraitShot3D.FACE]


func test_each_still_keeps_the_shape_of_the_drawing_it_stands_in_for() -> void:
	for variant in VARIANTS:
		var drawn := PortraitShot3D.drawn(variant)
		var px := PortraitShot3D.pixels(variant)
		assert_eq(px.x * drawn.y, px.y * drawn.x, "%s keeps the drawing's aspect" % variant)
		assert_gt(px.x, drawn.x * 2, "%s is rendered well above its drawn size" % variant)


func test_the_bust_is_the_drawing_and_the_chip_is_the_drawing_of_the_chip() -> void:
	assert_eq(PortraitShot3D.drawn(PortraitShot3D.BUST), CommanderVisuals.PORTRAIT_SIZE)
	assert_eq(PortraitShot3D.drawn(PortraitShot3D.FACE), CommanderVisuals.FACE_SIZE)


func test_the_chip_shows_a_centred_square_of_the_bust_holding_the_whole_head() -> void:
	var shot := PortraitShot3D.FACE_SHOT
	var grid := Rect2i(Vector2i.ZERO, CommanderVisuals.PORTRAIT_SIZE)
	assert_eq(shot.size.x, shot.size.y, "a square, like the chip")
	assert_true(grid.encloses(shot), "inside the bust's grid")
	assert_eq(shot.position.x * 2 + shot.size.x, grid.size.x, "centred across")
	assert_lte(shot.position.y, PortraitShot3D.HEAD_TOP_ROW, "the hair top is in it")
	var chin_row := PortraitShot3D.HEAD_TOP_ROW + PortraitShot3D.HEAD_ROWS
	assert_gte(shot.end.y, chin_row, "the chin is in it")


func test_the_head_lands_on_its_rows_of_the_bust() -> void:
	var bust := PortraitShot3D.BUST
	var height := PortraitShot3D.lens_height(bust)
	var top_of_frame := PortraitShot3D.aim(bust).y + height / 2.0
	var rows_per_unit := CommanderVisuals.PORTRAIT_SIZE.y / height
	var hair_row := (top_of_frame - PortraitShot3D.HEAD_TOP_Y) * rows_per_unit
	var chin_row := (top_of_frame - PortraitShot3D.CHIN_Y) * rows_per_unit
	assert_almost_eq(hair_row, float(PortraitShot3D.HEAD_TOP_ROW), 0.001)
	assert_almost_eq(chin_row, float(PortraitShot3D.HEAD_TOP_ROW + PortraitShot3D.HEAD_ROWS), 0.001)
	assert_almost_eq(PortraitShot3D.aim(bust).x, 0.0, 0.0001, "the figure stands in the middle")


func test_the_lens_stands_in_front_of_the_face_and_above_the_aim() -> void:
	for variant in VARIANTS:
		var to_lens := PortraitShot3D.eye(variant) - PortraitShot3D.aim(variant)
		assert_lt(to_lens.z, 0.0, "%s: the figure faces -Z, toward the lens" % variant)
		assert_gt(to_lens.y, 0.0, "%s: looking a little down" % variant)


func test_the_window_is_the_drawings_window_at_the_stills_scale() -> void:
	var scale := PortraitShot3D.BUST_SCALE
	var window := PortraitShot3D.window(PortraitShot3D.BUST)
	assert_eq(
		window, Rect2i(PortraitShot3D.WINDOW.position * scale, PortraitShot3D.WINDOW.size * scale)
	)
	assert_eq(PortraitShot3D.pen(PortraitShot3D.BUST), PortraitShot3D.WINDOW_PEN * scale)


func test_the_chips_window_runs_past_its_sides_so_only_the_top_rule_shows() -> void:
	var face := PortraitShot3D.FACE
	var window := PortraitShot3D.window(face)
	var px := PortraitShot3D.pixels(face)
	assert_lt(window.position.x, 0, "past the left edge")
	assert_gt(window.end.x, px.x, "past the right edge")
	assert_gte(window.end.y, px.y, "past the bottom edge")
	assert_between(window.position.y, 0, px.y, "its top rule is in the still")


func test_each_general_and_drawing_has_its_own_still() -> void:
	var keys := {}
	for id: StringName in [&"alina_ward", &"viktor_draeg", CommanderType.NEUTRAL_ID]:
		for variant in VARIANTS:
			keys[PortraitShot3D.key(id, variant)] = true
	assert_eq(keys.size(), 6)
