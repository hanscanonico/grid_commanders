extends GutTest
## The board's ambient beat: which figures the two units sheets differ in, and
## when the beat is not run at all.
##
## In scope despite living beside a Sprite2D: the sheet paths and `BoardBeat.frame`
## are static and pure, and nothing here builds a sprite — the same shape
## test_path_arrow.gd reads PathArrow.segments() in. What is under test is the
## art contract, which is the half that goes quiet when it breaks: a sheet
## regenerated with a still copter, or a land unit that started moving, changes
## no code and no test unless one reads the pixels.

const SPRITE_W := UnitSprite.SPRITE_W
const SPRITE_H := UnitSprite.SPRITE_H

var units: UnitDB
var frame_a: Image
var frame_b: Image
var opened_at: GameSpeed


func before_each() -> void:
	units = Fixture.unit_db()
	frame_a = _sheet(UnitSprite.UNITS_ATLAS_PATH)
	frame_b = _sheet(UnitSprite.UNITS_ATLAS_B_PATH)
	opened_at = Settings.speed


func after_each() -> void:
	Settings.speed = opened_at
	BoardBeat.frozen = false


func test_the_two_sheets_are_the_same_grid() -> void:
	assert_not_null(frame_a, "frame A did not load")
	assert_not_null(frame_b, "frame B did not load")
	assert_eq(frame_b.get_size(), frame_a.get_size(), "the sheets are different sizes")


## Every column carries a beat now — air and sea ride a pixel higher with rotors
## swept, land cells hold an idle key pose — which is what retired `animates()`.
## Regenerate a sheet with one column still and this is what says so.
func test_every_column_differs_between_the_sheets() -> void:
	assert_gt(units.size(), 0, "no units loaded, so this would pass vacuously")
	for type in units.all():
		assert_true(
			_column_differs(type.atlas_col),
			"%s: the sheets agree in column %d, so it does not animate" % [type.id, type.atlas_col]
		)


## The tier is named rather than inherited: this machine's stored preference may
## be Instant, which is a still board and would pass every one of these vacuously.
func test_the_beat_alternates_every_cadence() -> void:
	Settings.speed = GameSpeed.by_id(GameSpeed.DEFAULT_ID)
	assert_eq(BoardBeat.frame(BoardBeat.AMBIENT_MS, 0), 0, "the beat did not open on frame A")
	assert_eq(
		BoardBeat.frame(BoardBeat.AMBIENT_MS, BoardBeat.AMBIENT_MS), 1, "the beat did not turn over"
	)
	assert_eq(
		BoardBeat.frame(BoardBeat.AMBIENT_MS, 2 * BoardBeat.AMBIENT_MS),
		0,
		"the beat did not come back"
	)


func test_a_frozen_clock_holds_frame_a() -> void:
	Settings.speed = GameSpeed.by_id(GameSpeed.DEFAULT_ID)
	BoardBeat.frozen = true
	assert_eq(
		BoardBeat.frame(BoardBeat.AMBIENT_MS, BoardBeat.AMBIENT_MS),
		0,
		"a pinned capture read a beat"
	)


func test_instant_holds_frame_a() -> void:
	Settings.speed = GameSpeed.by_id(&"instant")
	assert_eq(
		BoardBeat.frame(BoardBeat.AMBIENT_MS, BoardBeat.AMBIENT_MS), 0, "Instant played the beat"
	)


## True when any faction row of `column` is *drawn* differently in frame B. The
## bytes alone are not the reading: the atlases import with `fix_alpha_border`,
## which bleeds each figure's colours into the transparent pixels around it, so a
## copter that moved leaves its neighbour's empty margin holding different — and
## equally invisible — RGB.
func _column_differs(column: int) -> bool:
	var rows := int(frame_a.get_height() / SPRITE_H)
	for row in rows:
		var region := Rect2i(column * SPRITE_W, row * SPRITE_H, SPRITE_W, SPRITE_H)
		var cell_a := frame_a.get_region(region)
		var cell_b := frame_b.get_region(region)
		if cell_a.get_data() != cell_b.get_data() and _visibly_differs(cell_a, cell_b):
			return true
	return false


func _visibly_differs(cell_a: Image, cell_b: Image) -> bool:
	for y in cell_a.get_height():
		for x in cell_a.get_width():
			var pixel_a := cell_a.get_pixel(x, y)
			var pixel_b := cell_b.get_pixel(x, y)
			if pixel_a.a == 0.0 and pixel_b.a == 0.0:
				continue
			if pixel_a != pixel_b:
				return true
	return false


func _sheet(path: String) -> Image:
	var texture := load(path) as Texture2D
	return texture.get_image() if texture != null else null
