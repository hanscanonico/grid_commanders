extends GutTest
## The board cards' one stylebox. `UiTheme.dark_panel_box` grew the pad the
## mission strip and the objective card each used to spell for themselves, so
## what has to stay true is both readings of it: a padded call carries the pad on
## all four sides, and an unpadded one is the box the six other callers already
## draw — untouched margins, so adopting the parameter moved no pixel of theirs.
##
## Pure static answers over a `StyleBoxFlat`, so they are checked without a scene
## the way `UiTheme.display()` is.

## The board cards' own values: `_PAD` and `_PAD - 1` in both screens.
const CARD_PAD_X := 5
const CARD_PAD_Y := 4


func test_an_unpadded_box_leaves_its_content_margins_alone() -> void:
	var box := UiTheme.dark_panel_box()
	assert_eq(box.content_margin_left, -1.0)
	assert_eq(box.content_margin_right, -1.0)
	assert_eq(box.content_margin_top, -1.0)
	assert_eq(box.content_margin_bottom, -1.0)


func test_a_padded_box_carries_the_pad_on_all_four_sides() -> void:
	var box := UiTheme.dark_panel_box(UiTheme.SLATE_800, CARD_PAD_X, CARD_PAD_Y)
	assert_eq(box.content_margin_left, float(CARD_PAD_X))
	assert_eq(box.content_margin_right, float(CARD_PAD_X))
	assert_eq(box.content_margin_top, float(CARD_PAD_Y))
	assert_eq(box.content_margin_bottom, float(CARD_PAD_Y))


## The pad is the only thing the parameters may change: fill, outline and the
## hard shadow are what make a card read as one, and they are the same box.
func test_padding_changes_nothing_else_about_the_box() -> void:
	var plain := UiTheme.dark_panel_box()
	var padded := UiTheme.dark_panel_box(UiTheme.SLATE_800, CARD_PAD_X, CARD_PAD_Y)
	assert_eq(padded.bg_color, plain.bg_color)
	assert_eq(padded.border_color, plain.border_color)
	assert_eq(padded.border_width_left, plain.border_width_left)
	assert_eq(padded.corner_radius_top_left, plain.corner_radius_top_left)
	assert_eq(padded.shadow_size, plain.shadow_size)
	assert_eq(padded.shadow_offset, plain.shadow_offset)
