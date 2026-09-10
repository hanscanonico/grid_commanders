extends GutTest
## The cut-ins' figure sheets: the board's army with the cast shadow gone — an
## aircraft's, the only one left since COM-270 — and nothing else about it
## moved. Both frames of the idle clip, because the
## cut-ins beat between them — a pair regenerated on one side only would leave a
## cut-in flickering between two different armies.
##
## In scope for the same reason test_ambient_frames.gd is: `figure_texture_for`
## is static and pure and nothing here builds a sprite. What is under test is the
## art contract, which is the half that goes quiet when it breaks — a sheet
## regenerated on one side of the pair and not the other changes no code and no
## other test, and the cut-in would simply draw a stale army.

const SPRITE_W := UnitSprite.SPRITE_W
const SPRITE_H := UnitSprite.SPRITE_H

## The idle clip, frame by frame: the sheet the board draws and the one the
## cut-ins cut the same pose out of.
const FRAMES := [
	[UnitSprite.UNITS_ATLAS_PATH, UnitSprite.UNITS_ATLAS_FIGURES_PATH],
	[UnitSprite.UNITS_ATLAS_B_PATH, UnitSprite.UNITS_ATLAS_FIGURES_B_PATH],
]

var units: UnitDB
var board: Image
var figures: Image


func before_each() -> void:
	units = Fixture.unit_db()
	_read_frame(0)


func test_the_paired_sheets_are_the_same_grid() -> void:
	for frame in FRAMES.size():
		_read_frame(frame)
		assert_not_null(board, "the board sheet of frame %d did not load" % frame)
		assert_not_null(figures, "the figure sheet of frame %d did not load" % frame)
		assert_eq(
			figures.get_size(), board.get_size(), "frame %d's sheets are different sizes" % frame
		)


## The whole claim of the sheet: it subtracts, so a figure blown up in a cut-in
## is the figure on the board. A repainted pixel here would be the cut-in quietly
## drawing a second opinion on the art.
func test_the_figure_sheets_only_ever_remove_a_pixel() -> void:
	for frame in FRAMES.size():
		_read_frame(frame)
		for y in figures.get_height():
			for x in figures.get_width():
				var kept := figures.get_pixel(x, y)
				if kept.a == 0.0:
					continue
				assert_eq(
					kept,
					board.get_pixel(x, y),
					"frame %d's figure sheet repaints the pixel at %d,%d" % [frame, x, y]
				)


## Only an aircraft casts on the board (COM-270), so only an aircraft's column
## has anything for the figure sheet to take: a unit that stands on the tile or
## sits in the water is already drawn flat, and its figure cell is its board
## cell. The cut-ins draw their own contact ellipse on UnitSprite.CELL_GROUND_PX
## either way — `tests/unit/test_anim_manifest.gd` is that constant's pin,
## against the generator's own `ground_px`.
func test_only_the_aircraft_leave_a_shadow_behind_in_both_frames() -> void:
	assert_gt(units.size(), 0, "no units loaded, so this would pass vacuously")
	var flyers := 0
	for frame in FRAMES.size():
		_read_frame(frame)
		for type in units.all():
			var dropped := _shadow_rows(type.atlas_col).y >= 0
			if type.domain == UnitType.AIR:
				flyers += 1
				assert_true(
					dropped,
					(
						"%s lost its cast shadow in frame %d's figure sheet (column %d)"
						% [type.id, frame, type.atlas_col]
					)
				)
			else:
				assert_false(
					dropped,
					(
						"%s casts a shadow on the board in frame %d (column %d)"
						% [type.id, frame, type.atlas_col]
					)
				)
	assert_gt(flyers, 0, "no aircraft read, so the shadow half would pass vacuously")


func test_the_cut_ins_ask_for_the_figure_sheet() -> void:
	var type: UnitType = units.all()[0]
	for frame in FRAMES.size():
		var art := UnitSprite.figure_texture_for(type, 1, frame)
		assert_eq(
			art.atlas.resource_path,
			FRAMES[frame][1],
			"figure_texture_for cut frame %d from the wrong sheet" % frame
		)
		assert_eq(
			art.region, UnitSprite.texture_for(type, 1).region, "frame %d cuts differently" % frame
		)


## The frame is the clip's, so an unasked-for frame is the resting one — every
## caller that wants a still keeps the signature it had.
func test_the_resting_frame_is_the_default() -> void:
	var type: UnitType = units.all()[0]
	assert_eq(
		UnitSprite.figure_texture_for(type, 1).atlas.resource_path,
		UnitSprite.UNITS_ATLAS_FIGURES_PATH,
		"the default frame is not the resting one"
	)


## The clip only exists if the two frames differ. Read off drawn pixels for the
## reason `_shadow_rows` is.
func test_the_two_figure_frames_are_a_beat_apart() -> void:
	var a := _sheet(UnitSprite.UNITS_ATLAS_FIGURES_PATH)
	var b := _sheet(UnitSprite.UNITS_ATLAS_FIGURES_B_PATH)
	var beats := false
	for y in a.get_height():
		for x in a.get_width():
			var was := a.get_pixel(x, y)
			var now := b.get_pixel(x, y)
			if was.a == 0.0 and now.a == 0.0:
				continue
			beats = beats or was != now
	assert_true(beats, "the two figure sheets are identical, so the cut-ins have no idle beat")


## A cut-in reads its frame off its director's clock, never off the wall — that
## is what keeps a posed still and a skip landing on a fixed pose.
func test_the_cut_in_beat_is_the_directors_clock() -> void:
	assert_eq(BoardBeat.frame_at(BoardBeat.AMBIENT_MS, 0), 0, "the clock opens on frame A")
	assert_eq(BoardBeat.frame_at(BoardBeat.AMBIENT_MS, 499), 0, "frame A holds its half beat")
	assert_eq(BoardBeat.frame_at(BoardBeat.AMBIENT_MS, 500), 1, "the beat did not turn over")
	assert_eq(BoardBeat.frame_at(BoardBeat.AMBIENT_MS, 1000), 0, "the clip did not loop")
	BoardBeat.frozen = true
	assert_eq(
		BoardBeat.frame_at(BoardBeat.AMBIENT_MS, 500),
		1,
		"the board's freeze reached a cut-in, whose stills are its own clock's"
	)
	BoardBeat.frozen = false


## The rows of `column` the figure sheet dropped, as first and last, over every
## faction row at once — the shadow is the same shape in all of them. Empty
## (a negative last row) when the column lost nothing at all, which is what
## every land and sea column now reads.
##
## Read off drawn pixels rather than bytes: the atlases import with
## `fix_alpha_border`, which bleeds colour into transparent pixels, so a removed
## shadow leaves RGB behind at alpha zero.
func _shadow_rows(column: int) -> Vector2i:
	var span := Vector2i(SPRITE_H, -1)
	for row in int(board.get_height() / SPRITE_H):
		var region := Rect2i(column * SPRITE_W, row * SPRITE_H, SPRITE_W, SPRITE_H)
		var on_tile := board.get_region(region)
		var posed := figures.get_region(region)
		for y in SPRITE_H:
			for x in SPRITE_W:
				if on_tile.get_pixel(x, y).a > 0.0 and posed.get_pixel(x, y).a == 0.0:
					span = Vector2i(mini(span.x, y), maxi(span.y, y))
					break
	return span


func _read_frame(frame: int) -> void:
	board = _sheet(FRAMES[frame][0])
	figures = _sheet(FRAMES[frame][1])


func _sheet(path: String) -> Image:
	var texture := load(path) as Texture2D
	return texture.get_image() if texture != null else null
