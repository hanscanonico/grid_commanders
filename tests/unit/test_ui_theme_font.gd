extends GutTest
## What the display font must never do again: Pixelify Sans ships OpenType
## standard ligatures whose merged glyphs are unreadable at pixel size — the `fi`
## one rasterises as an `A`, so a campaign briefing read "at Arst frost" and a
## commander card read "Every unit reAlls fuel".
##
## Shaped rather than drawn: `UiTheme.display()` is a pure static answer, like
## `TransitionInput.is_press` and `PathArrow.segments`, so the promise is checked
## without a scene. Counting glyphs is what says the pair stayed two characters —
## the ligature is one glyph for the two codepoints, and nothing else about the
## shaping run distinguishes them.
##
## The run is spelled the way a `Label` spells it, features and all: a font's
## feature overrides ride beside its RIDs rather than inside them, so a shaping
## call that dropped them would report the ligature live on a face that draws it
## switched off.

## Five letters, and five glyphs only when `fi` did not merge.
const LIGATURE_WORD := "first"


func _glyphs(font: Font) -> int:
	var server := TextServerManager.get_primary_interface()
	var shaped := server.create_shaped_text()
	server.shaped_text_add_string(
		shaped, LIGATURE_WORD, font.get_rids(), UiTheme.SIZE_BODY, font.get_opentype_features()
	)
	server.shaped_text_shape(shaped)
	var count := server.shaped_text_get_glyph_count(shaped)
	server.free_rid(shaped)
	return count


func test_the_display_face_shapes_fi_as_two_letters() -> void:
	assert_eq(_glyphs(UiTheme.display()), LIGATURE_WORD.length())


func test_the_bold_display_face_shapes_fi_as_two_letters() -> void:
	assert_eq(_glyphs(UiTheme.display(true)), LIGATURE_WORD.length())


## The font file itself still carries the ligature — the fix is the wrapping, so
## a check that only measured `UiTheme` would pass just as happily against a face
## that never had one, and stop meaning anything.
func test_the_raw_font_file_is_the_one_that_merges_them() -> void:
	var raw: FontFile = load(UiTheme.DISPLAY_FONT_PATH)
	assert_lt(_glyphs(raw), LIGATURE_WORD.length())


## What the stat face must never do again: Silkscreen is drawn on an 8-pixel grid,
## and the shell served it at 6 and 7, where the rasteriser drops a row out of
## every glyph and prints a different letter — "FUNDS 4200" as "FUHDG 42DD"
## (COM-254). A size is a number anybody can type, so the grid is a constant and
## this is the lint that keeps the one size the shell sets on it.
func test_the_stat_face_is_set_on_its_own_pixel_grid() -> void:
	assert_gt(UiTheme.SIZE_STAT, 0)
	assert_eq(UiTheme.SIZE_STAT % UiTheme.STAT_DESIGN_PX, 0)
