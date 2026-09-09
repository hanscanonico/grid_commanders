class_name UiMarks
extends RefCounted
## The six marks the shell prints that neither pixel face draws: the tick and the
## cross a mission's conditions carry, the two stars a defence rating counts in,
## the arrow a debrief steps with and the infinity a full magazine reads as.
##
## The desktop hid the hole: a glyph no font in the chain has falls through to
## the machine's own system font there, and macOS drew all six. A browser hands
## the engine no system font at all, so the web build printed each of them as the
## hex box Godot draws for a glyph it cannot find — a white block reading "2713"
## where a toggle's tick belongs, which is the whole of "the buttons don't show
## correctly".
##
## So the marks are drawn here rather than loaded: six shapes on Silkscreen's own
## 8-pixel grid, baked into a bitmap face `UiTheme` hangs off every font as a
## fallback. No new font asset and no new licence, and the shell now says the same
## thing on every platform instead of whatever the machine happened to own.

## The grid the marks are drawn on — Silkscreen's, so a mark sits on the same
## pixels as the digits beside it.
const GRID := 8
## How far the pen moves past a mark. One column of air on the right, the way a
## stat glyph carries its own.
const ADVANCE := 8

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
	"☆":
	[
		"........",
		"...#....",
		"..#.#...",
		"###.###.",
		".#...#..",
		"..#.#...",
		".##.##..",
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

	var sheet := Image.create_empty(GRID * MARKS.size(), GRID, false, Image.FORMAT_RGBA8)
	var column := 0
	for mark: String in MARKS:
		_stamp(sheet, MARKS[mark], column * GRID)
		column += 1
	var size := Vector2i(GRID, 0)
	face.set_texture_image(0, size, 0, sheet)

	column = 0
	for mark: String in MARKS:
		var glyph := mark.unicode_at(0)
		face.set_glyph_texture_idx(0, size, glyph, 0)
		face.set_glyph_uv_rect(0, size, glyph, Rect2(column * GRID, 0, GRID, GRID))
		face.set_glyph_size(0, size, glyph, Vector2(GRID, GRID))
		# Hung off the baseline, so a mark sits where a capital does.
		face.set_glyph_offset(0, size, glyph, Vector2(0, -GRID))
		face.set_glyph_advance(0, GRID, glyph, Vector2(ADVANCE, 0))
		column += 1
	return face


static func _stamp(sheet: Image, rows: Array, left: int) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				sheet.set_pixel(left + x, y, Color.WHITE)
