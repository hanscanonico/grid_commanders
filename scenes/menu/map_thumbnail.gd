class_name MapThumbnail
extends Control
## Draws a MapData as a miniature board by blitting one sheet region per cell —
## which sheet and which region from TerrainAutotiles and SideIdentity.atlas_row,
## the exact authorities BattleView paints the live board with (menu-revamp D5).
##
## No symbol table, no per-terrain colour list, no second opinion (plan R2): there
## is only one of it, so a new terrain lands here for free and the miniature can
## never drift from the board it launches — the range-overlay-vs-command bug,
## closed by construction. That is why an autotiled cell asks the same authority
## the board does rather than reading atlas_col: a one-tile lake was a hard blue
## square in the picker and a coasted pond in the match. Owned properties draw in
## the resolved faction's row, so a thumbnail is a truthful miniature of day one,
## and they draw over the same ground the board paints under them — a property
## column is a transparent overlay, so it is composed here rather than copied.
##
## The same per-cell region logic serves two masters: `_draw` paints a live cell
## for the picker, and the static `bake()` renders the panning backdrop to an
## ImageTexture — one renderer, so the field behind the menu and the thumbnails in
## front of it agree by definition.

## Atlas cell size, mirroring BattleView.TERRAIN_PX and the art pipeline. The
## atlas is 14 columns x 5 rows of these; the row order is SideIdentity's.
const CELL := 64
const ATLAS_PATH := "res://assets/tiles/terrain_atlas.png"

static var _textures: Dictionary[String, Texture2D] = {}
static var _images: Dictionary[String, Image] = {}
static var _ground_col := -1

var _map: MapData
var _identity: SideIdentity
var _tile := 4
var _origin := Vector2.ZERO


## A picture, never a target: a Control defaults to swallowing the mouse, and a
## thumbnail filling its picker cell swallowed the cell's. That cost the cell both
## its hover styling and, once the menu stopped using the engine's own tooltips —
## which walk up the tree to find one — its explanation as well.
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Points the thumbnail at a board and fits it, centred, into `box` (canvas px).
## The tile size is the largest whole-pixel size that keeps the whole board inside
## the box, so different-shaped boards all sit in an identical cell.
func setup(map: MapData, identity: SideIdentity, box: Vector2) -> void:
	_map = map
	_identity = identity
	custom_minimum_size = box
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if map == null:
		queue_redraw()
		return
	_tile = maxi(1, floori(minf(box.x / map.width, box.y / map.height)))
	var drawn := Vector2(map.width * _tile, map.height * _tile)
	_origin = ((box - drawn) / 2.0).floor()
	queue_redraw()


func _draw() -> void:
	if _map == null:
		return
	for y in _map.height:
		for x in _map.width:
			var cell := Vector2i(x, y)
			var dst := Rect2(_origin + Vector2(x * _tile, y * _tile), Vector2(_tile, _tile))
			var under := ground_region(_map, cell)
			if under.has_area():
				draw_texture_rect_region(_texture(ATLAS_PATH), dst, under)
			draw_texture_rect_region(
				_texture(sheet_path(_map, cell)), dst, sheet_region(_map, _identity, cell)
			)


# --- the one renderer, shared by the live draw and the baked backdrop ---------


## Bakes a board to an ImageTexture at `tile` px per cell: paints it at full atlas
## resolution, then resizes down with nearest-neighbour so it stays crisp. This is
## the panning field behind the menu (plan MN2), and it is the same per-cell
## region logic `_draw` uses, so the backdrop cannot disagree with a thumbnail.
static func bake(map: MapData, identity: SideIdentity, tile: int) -> ImageTexture:
	var full := Image.create(map.width * CELL, map.height * CELL, false, Image.FORMAT_RGBA8)
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var region := sheet_region(map, identity, cell)
			var at := Vector2i(x * CELL, y * CELL)
			var under := ground_region(map, cell)
			# blit copies alpha and blend composites it, so a property overlay has to
			# arrive the second way or it punches its ground back out again.
			if under.has_area():
				full.blit_rect(_source_image(ATLAS_PATH), Rect2i(under.position, under.size), at)
				full.blend_rect(
					_source_image(sheet_path(map, cell)), Rect2i(region.position, region.size), at
				)
				continue
			full.blit_rect(
				_source_image(sheet_path(map, cell)), Rect2i(region.position, region.size), at
			)
	full.resize(map.width * tile, map.height * tile, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(full)


## Which sheet `cell` draws from: the base terrain atlas, or the autotile family
## sheet TerrainAutotiles picks for it. The thumbnail names the file and never
## decides the variant.
static func sheet_path(map: MapData, cell: Vector2i) -> String:
	var family := TerrainAutotiles.family(map, cell)
	if family == TerrainAutotiles.Family.NONE:
		return ATLAS_PATH
	return TerrainAutotiles.SHEET_PATHS[family]


## Where on that sheet `cell`'s art sits. The base atlas is a plain grid of
## cells; an autotile sheet is cut on TerrainAutotiles' contact-sheet contract,
## which is what BattleView hands its TileSet sources instead of indexing by
## hand.
static func sheet_region(map: MapData, identity: SideIdentity, cell: Vector2i) -> Rect2:
	var family := TerrainAutotiles.family(map, cell)
	if family == TerrainAutotiles.Family.NONE:
		var terrain := map.terrain_at(cell)
		return _region(terrain.atlas_col, _row_for(map, identity, terrain, cell))
	var coords := TerrainAutotiles.atlas_coords(family, TerrainAutotiles.mask(map, cell))
	var step := CELL + TerrainAutotiles.SHEET_SEPARATION
	var margin := TerrainAutotiles.SHEET_MARGIN
	return Rect2(margin + coords.x * step, margin + coords.y * step, CELL, CELL)


## What `cell` is painted over, when its own art does not cover the tile: the
## default ground's atlas cell under a property, whose column ships as a
## transparent overlay (TerrainDB.GROUND_ID), and an empty rect everywhere else.
## The board paints the same cell on its own layer under the same terrain.
static func ground_region(map: MapData, cell: Vector2i) -> Rect2:
	if not map.terrain_at(cell).is_property:
		return Rect2()
	if _ground_col < 0:
		_ground_col = TerrainDB.load_default().ground().atlas_col
	return _region(_ground_col, 0)


## The atlas row a cell draws in: a team-tinted property takes its owner's
## resolved faction row, everything else the neutral row 0 — SideIdentity's call,
## never the owner int (BattleView's exact rule).
static func _row_for(
	map: MapData, identity: SideIdentity, terrain: TerrainType, cell: Vector2i
) -> int:
	if terrain.team_tinted and identity != null:
		return identity.atlas_row(map.owner_at(cell))
	return 0


static func _region(col: int, row: int) -> Rect2:
	return Rect2(col * CELL, row * CELL, CELL, CELL)


static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


## A sheet as a mutable RGBA8 Image, decompressed once for `bake`'s blits.
static func _source_image(path: String) -> Image:
	if not _images.has(path):
		var image := _texture(path).get_image()
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		_images[path] = image
	return _images[path]
