class_name BattleOverlays
extends RefCounted
## The transient marks laid over the board: where a unit may go, what it may
## shoot, where the hostile sides can reach, the route it would walk, and how much
## a capture still owes.
##
## They came out of BattleView together, when a fourth layer and a fifth mark put
## it past the size a renderer should be. They belong together anyway: they are
## the paint that answers a question the player is asking *right now* and is gone
## when the question is, as against terrain, sprites and fog, which are the board
## itself. Everything here is written and cleared by Battle as its flow moves;
## nothing survives a state it was raised in unless Battle says so.
##
## Assigned-not-constructed, like BattleView and BattleAnimator: Battle sets the
## node fields and calls `setup`, so this never holds a reference to Battle and
## the dependency stays one-way.

const TILE := BattleView.TILE
const OVERLAY_PATH := "res://assets/tiles/overlay.png"
const ATLAS_SOURCE_ID := 0
## Period of the threat lens's diagonal stripes, half on and half off. Must divide
## TILE — see `_build_threat_tile_set`.
const THREAT_STRIPE := 4

## Reachable cells, in mint.
var move_layer: TileMapLayer
## Cells that can be fired into: the R fire ring, the pickable targets while an
## attack is being aimed, and the square under an aimed Command Power. Solid, with
## the atlas's bright one-pixel border. The three never share the board — a power
## is aimed with no unit selected — which is what lets one layer say all three.
var attack_layer: TileMapLayer
## The threat lens. Its own layer rather than a second use of `attack_layer`,
## because that one is already two things at once and a lens sharing it would
## either erase a target list or be mistaken for one. Diagonal stripes, so the
## two never read as the same paint.
var threat_layer: TileMapLayer
var path_arrow: PathArrow
var capture_pips: CapturePips
## The mission's targets. Transient like the rest of this class only in that a
## campaign raises it and a skirmish never does; within a mission it stands until
## the objective it marks is met.
var objective_marks: ObjectiveMarks


## Builds the tile sets and paints the layers from OverlayPalette. Call once,
## after the node fields are set.
func setup() -> void:
	move_layer.tile_set = _build_overlay_tile_set()
	attack_layer.tile_set = move_layer.tile_set
	threat_layer.tile_set = _build_threat_tile_set()
	move_layer.modulate = OverlayPalette.MOVE
	attack_layer.modulate = OverlayPalette.ATTACK
	threat_layer.modulate = OverlayPalette.THREAT


## Highlights reachable cells — a unit's movement range, or where a transport
## could unload. An empty list clears the layer, so callers never need a separate
## "and now hide it" call. Every painter here has that contract.
func paint_move(cells: Array[Vector2i]) -> void:
	_paint(move_layer, cells)


## Highlights the cells a unit — or an aimed Command Power — may fire at.
func paint_attack(cells: Array[Vector2i]) -> void:
	_paint(attack_layer, cells)


## Shades every cell a side hostile to the viewer could bring under fire.
func paint_threat(cells: Array[Vector2i]) -> void:
	_paint(threat_layer, cells)


## Traces the planned route. A path too short to be a route clears the arrow.
func trace_path(path: Array[Vector2i]) -> void:
	path_arrow.set_path(path)


## Pins the capture chips: the sim's own progress table, keyed by cell to the
## points each property still owes, put through the same fog gate the board is —
## a capture the viewer has not scouted stays as unannounced as the ownership flip
## that will follow it. A presentation split of a number the sim already holds,
## and `CapturePips` stays dumb: never a call back into capture_strength.
func show_capture_pips(progress: Dictionary[Vector2i, int], perspective: BattlePerspective) -> void:
	var pips: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in progress:
		if perspective.can_see_cell(cell):
			pips[cell] = progress[cell]
	capture_pips.set_pips(pips)


## Rings the squares this mission's live objectives name. Empty for a skirmish
## and for every objective that is about a count rather than a place.
func show_objective_marks(cells: Array[Vector2i]) -> void:
	objective_marks.set_cells(cells)


func _paint(layer: TileMapLayer, cells: Array[Vector2i]) -> void:
	layer.clear()
	for cell in cells:
		layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i.ZERO)


func _build_overlay_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(OVERLAY_PATH)
	atlas.texture_region_size = Vector2i(TILE, TILE)
	atlas.create_tile(Vector2i.ZERO)
	tile_set.add_source(atlas, ATLAS_SOURCE_ID)
	return tile_set


## Diagonal stripes, generated rather than authored: the pattern is arithmetic,
## and an asset would only add a file that has to stay in step with TILE.
##
## The period divides the tile (TILE % THREAT_STRIPE == 0), which is what makes
## the stripes run unbroken across cell boundaries — a shading that restarted at
## every edge would draw the very grid the lens is meant to read past. Colour and
## depth stay OverlayPalette's modulate, set here in setup() — unlike the fog's,
## which stays battle.tscn's own.
func _build_threat_tile_set() -> TileSet:
	var image := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var lit := (x + y) % THREAT_STRIPE < THREAT_STRIPE / 2
			image.set_pixel(x, y, Color.WHITE if lit else Color(1, 1, 1, 0))
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(TILE, TILE)
	atlas.create_tile(Vector2i.ZERO)
	tile_set.add_source(atlas, ATLAS_SOURCE_ID)
	return tile_set
