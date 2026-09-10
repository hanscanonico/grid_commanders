class_name UiMarks
extends RefCounted
## The six marks the shell prints that neither pixel face draws: ✓ ✗ ★ ☆ → ∞.
##
## They are drawn here rather than loaded because the only fallback behind them
## was the machine's own system font, which a browser does not hand the engine —
## the web build printed every one of them as Godot's missing-glyph box. Six
## shapes on Silkscreen's own 8-pixel grid, baked into a bitmap face `UiTheme`
## hangs off every font it serves: no new font asset, no new licence, and the
## same mark on every platform.

## The grid the marks are drawn on — Silkscreen's, so a mark sits on the same
## pixels as the digits beside it, and the pen's step past one. The air on a
## mark's right is the mask's own blank last column rather than a wider advance.
const GRID := 8

## Mark -> its rows, one character per pixel, `#` set and anything else clear.
## Every row is GRID wide and every mark GRID tall; `test_ui_marks.gd` holds them
## to it, because a short row bakes a silently cropped glyph.
const MARKS := {
	"✓":
	[
		"........",
		"......#.",
		".....##.",
		"#...##..",
		"##.##...",
		".###....",
		"..#.....",
		"........",
	],
	"✗":
	[
		"........",
		".#....#.",
		".##..##.",
		"..####..",
		"...##...",
		"..####..",
		".##..##.",
		".#....#.",
	],
	"★":
	[
		"........",
		"...#....",
		"..###...",
		"#######.",
		".#####..",
		"..###...",
		".#...#..",
		"........",
	],
	## The filled star hollowed out, keeping its silhouette to the pixel — same
	## arms, same chin, same feet. The chin stays solid because it is what closes
	## the hollow: opened at the bottom, the hollow runs into the gap between the
	## feet and the mark reads as two blobs rather than as a star.
	"☆":
	[
		"........",
		"...#....",
		"..#.#...",
		"###.###.",
		".#...#..",
		"..###...",
		".#...#..",
		"........",
	],
	"→":
	[
		"........",
		"........",
		"....#...",
		".....#..",
		"#######.",
		".....#..",
		"....#...",
		"........",
	],
	"∞":
	[
		"........",
		"........",
		"........",
		".##.##..",
		".#.#.#..",
		".##.##..",
		"........",
		"........",
	],
}

static var _font: FontFile


## The fallback face, baked once. White pixels: a glyph texture is tinted by the
## label's own font colour, so one bake serves the cream marks and the ink ones.
static func font() -> FontFile:
	if _font == null:
		_font = _bake()
	return _font


static func _bake() -> FontFile:
	var face := FontFile.new()
	face.fixed_size = GRID
	face.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	face.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	face.set_cache_ascent(0, GRID, GRID)
	face.set_cache_descent(0, GRID, 0.0)

	var size := Vector2i(GRID, 0)
	var sheet := Image.create_empty(GRID * MARKS.size(), GRID, false, Image.FORMAT_RGBA8)
	var left := 0
	for mark: String in MARKS:
		_stamp(sheet, MARKS[mark], left)
		var glyph := mark.unicode_at(0)
		face.set_glyph_texture_idx(0, size, glyph, 0)
		face.set_glyph_uv_rect(0, size, glyph, Rect2(left, 0, GRID, GRID))
		face.set_glyph_size(0, size, glyph, Vector2(GRID, GRID))
		# Hung off the baseline, so a mark sits where a capital does.
		face.set_glyph_offset(0, size, glyph, Vector2(0, -GRID))
		face.set_glyph_advance(0, GRID, glyph, Vector2(GRID, 0))
		left += GRID
	face.set_texture_image(0, size, 0, sheet)
	return face


static func _stamp(sheet: Image, rows: Array, left: int) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				sheet.set_pixel(left + x, y, Color.WHITE)
