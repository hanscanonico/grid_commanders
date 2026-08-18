class_name LegibilityLabel
extends RefCounted
## Text straight into an Image, one glyph at a time.
##
## A headless run has no viewport, so a Label, a TextLine and a SubViewport all
## draw into nothing here — but the font cache is CPU-side, so the glyphs
## themselves are readable: `render_glyph` rasterises into a cache texture and
## `get_texture_image` hands that image back. The gallery's captions are drawn
## through this rather than composed anywhere else in the tree, because there is
## nowhere else in the tree that draws into an Image.
##
## Silkscreen at its own 8px size for the same reason the HUD wears it: a pixel
## font at its authored size beside pixel art, upscaled with everything else.
## The rasterisation is deterministic, which is what the gallery needs of it.

const FONT_PATH := "res://assets/fonts/Silkscreen-Regular.ttf"
const SIZE := 8
## Baseline-to-baseline of stacked lines, in the same pixels.
const LINE_HEIGHT := 11

var _font: FontFile
var _cache_size := Vector2i(SIZE, 0)


static func create() -> LegibilityLabel:
	var label := LegibilityLabel.new()
	label._font = load(FONT_PATH) as FontFile
	if label._font == null:
		push_error("legibility: cannot load %s" % FONT_PATH)
		return null
	return label


## Draws one line with its top-left corner at `at`, in `ink`, and returns the pen
## position it ended at. Anything the image cannot hold is clipped rather than
## wrapped: a caption that does not fit is a layout to fix, not a line to reflow.
func draw(image: Image, text: String, at: Vector2i, ink: Color) -> int:
	var pen := at.x
	var baseline := at.y + int(_font.get_ascent(SIZE))
	for character in text.to_utf32_buffer():
		var glyph := _font.get_glyph_index(SIZE, character, 0)
		_blit(image, glyph, Vector2i(pen, baseline), ink)
		pen += int(_font.get_glyph_advance(0, SIZE, glyph).x)
	return pen


## Width one line will take, so a caller can centre it or check it fits.
func width(text: String) -> int:
	var pen := 0
	for character in text.to_utf32_buffer():
		pen += int(_font.get_glyph_advance(0, SIZE, _font.get_glyph_index(SIZE, character, 0)).x)
	return pen


func _blit(image: Image, glyph: int, pen: Vector2i, ink: Color) -> void:
	_font.render_glyph(0, _cache_size, glyph)
	var texture := _font.get_glyph_texture_idx(0, _cache_size, glyph)
	if texture < 0:
		return
	var sheet := _font.get_texture_image(0, _cache_size, texture)
	var region := _font.get_glyph_uv_rect(0, _cache_size, glyph)
	var offset := _font.get_glyph_offset(0, _cache_size, glyph)
	for y in int(region.size.y):
		for x in int(region.size.x):
			var coverage := (
				sheet.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a
			)
			if coverage <= 0.0:
				continue
			var at := pen + Vector2i(int(offset.x) + x, int(offset.y) + y)
			if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
				continue
			var wash := Color(ink.r, ink.g, ink.b, ink.a * coverage)
			image.set_pixel(at.x, at.y, LegibilityMetric.over(wash, image.get_pixel(at.x, at.y)))
