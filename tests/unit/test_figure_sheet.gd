extends GutTest
## The cut-ins' figure sheet: the board's army with the tile's cast shadow gone,
## and nothing else about it moved.
##
## In scope for the same reason test_ambient_frames.gd is: `figure_texture_for`
## is static and pure and nothing here builds a sprite. What is under test is the
## art contract, which is the half that goes quiet when it breaks — a sheet
## regenerated on one side of the pair and not the other changes no code and no
## other test, and the cut-in would simply draw a stale army.

const SPRITE_W := UnitSprite.SPRITE_W
const SPRITE_H := UnitSprite.SPRITE_H

var units: UnitDB
var board: Image
var figures: Image


func before_each() -> void:
	units = Fixture.unit_db()
	board = _sheet(UnitSprite.UNITS_ATLAS_PATH)
	figures = _sheet(UnitSprite.UNITS_ATLAS_FIGURES_PATH)


func test_the_two_sheets_are_the_same_grid() -> void:
	assert_not_null(board, "the board sheet did not load")
	assert_not_null(figures, "the figure sheet did not load")
	assert_eq(figures.get_size(), board.get_size(), "the sheets are different sizes")


## The whole claim of the sheet: it subtracts, so a figure blown up in a cut-in
## is the figure on the board. A repainted pixel here would be the cut-in quietly
## drawing a second opinion on the art.
func test_the_figure_sheet_only_ever_removes_a_pixel() -> void:
	for y in figures.get_height():
		for x in figures.get_width():
			var kept := figures.get_pixel(x, y)
			if kept.a == 0.0:
				continue
			assert_eq(
				kept, board.get_pixel(x, y), "the figure sheet repaints the pixel at %d,%d" % [x, y]
			)


func test_every_unit_leaves_its_tile_shadow_behind() -> void:
	assert_gt(units.size(), 0, "no units loaded, so this would pass vacuously")
	for type in units.all():
		assert_true(
			_shadow_rows(type.atlas_col).y >= 0,
			"%s keeps its tile shadow in the figure sheet (column %d)" % [type.id, type.atlas_col]
		)


## The cut-ins draw their own contact ellipse on UnitSprite.CELL_GROUND_PX, so
## that constant has to be the row the generator centres the tile's shadow on —
## and the shadow is exactly what the two sheets differ by. Air is left out: its
## cast is displaced down the cell from height, and a cut-in lifts the aircraft
## off the ground plane itself.
func test_the_cell_ground_line_is_where_the_tile_shadow_is_centred() -> void:
	var ground_line := float(SPRITE_H - UnitSprite.CELL_GROUND_PX)
	for type in units.all():
		if type.domain == UnitType.AIR:
			continue
		var span := _shadow_rows(type.atlas_col)
		assert_almost_eq(
			(span.x + span.y + 1.0) / 2.0,
			ground_line,
			0.5,
			"%s centres its tile shadow off the cell's ground line" % type.id
		)


func test_the_cut_ins_ask_for_the_figure_sheet() -> void:
	var type: UnitType = units.all()[0]
	var art := UnitSprite.figure_texture_for(type, 1)
	assert_eq(
		art.atlas.resource_path,
		UnitSprite.UNITS_ATLAS_FIGURES_PATH,
		"figure_texture_for cut its region from the wrong sheet"
	)
	assert_eq(art.region, UnitSprite.texture_for(type, 1).region, "the two sheets cut differently")


## The rows of `column` the figure sheet dropped, as first and last, over every
## faction row at once — the shadow is the same shape in all of them. Empty
## (a negative last row) when the column lost nothing at all.
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


func _sheet(path: String) -> Image:
	var texture := load(path) as Texture2D
	return texture.get_image() if texture != null else null
