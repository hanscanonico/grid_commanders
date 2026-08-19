extends GutTest
## The width an illustrated menu row caps its artwork at. Pure and static, like
## PathArrow.segments, so it is checked without standing up the menu.
##
## Worth its own suite because the smoke sweep cannot answer for it: every unit
## sprite that ships is square, so a capture is byte-identical whether the fit
## holds or not, and the shape this arithmetic exists for is the one no committed
## frame contains.

const SLOT := UiTheme.MENU_ICON


func _stub(w: int, h: int) -> Texture2D:
	return ImageTexture.create_from_image(Image.create(w, h, false, Image.FORMAT_RGBA8))


## `icon_max_width` scales by width and lets the height follow the ratio, so this
## is the box the row actually draws.
func _drawn(w: int, h: int) -> Vector2:
	var cap := ActionMenu.icon_cap(_stub(w, h))
	return Vector2(cap, float(h) * cap / float(w))


func test_square_art_fills_the_slot() -> void:
	assert_eq(ActionMenu.icon_cap(_stub(64, 64)), SLOT)
	assert_eq(_drawn(64, 64), Vector2(SLOT, SLOT))


func test_wide_art_is_capped_by_its_width() -> void:
	assert_eq(ActionMenu.icon_cap(_stub(96, 64)), SLOT)
	assert_lt(_drawn(96, 64).y, float(SLOT))


func test_tall_art_stays_inside_the_slot() -> void:
	var drawn := _drawn(64, 96)
	assert_lt(drawn.x, float(SLOT), "a taller-than-wide sprite gives width up to fit")
	assert_lte(drawn.y, float(SLOT), "and never stands out of the row")


func test_a_sliver_still_asks_for_a_pixel() -> void:
	assert_eq(ActionMenu.icon_cap(_stub(1, 256)), 1)


func test_a_widthless_texture_falls_back_to_the_slot() -> void:
	var empty := PlaceholderTexture2D.new()
	empty.size = Vector2.ZERO
	assert_eq(ActionMenu.icon_cap(empty), SLOT)
