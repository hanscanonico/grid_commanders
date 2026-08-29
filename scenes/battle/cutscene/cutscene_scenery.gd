class_name CutsceneScenery
extends RefCounted
## The shapes a standing terrain puts on a cut-in's ground, and the colours they
## are drawn in: one declaration each, shared by both cut-ins.
##
## This is the one home of the battle-animations plan's D2 departure — an atlas
## cell is a square of ground with its object drawn *on* it, so stood up as-is a
## building brings that opaque plate with it and reads as a framed picture rather
## than a tower. So the shape is drawn, with its colour still sampled off the same
## cell (`object_tint`, over the middle of it). Which terrain stands and which
## paves is TerrainType's answer (`stands_in_cutin`, `cutin_scenery`); this is the
## vocabulary those keys name, the way BattleStyle's projectile kinds are the one
## CutsceneFx shares.
##
## Draws on the canvas it is handed and reads nothing else: every shape is a pure
## function of a base point, a height and a colour, so a posed still stays a pure
## function of its cut-in's clock.

## How tall each kind stands at full size. A ridge dwarfs a pine, and a tower
## splits the difference while going far higher than either above the horizon.
const TREE_PX := 40.0
const PEAK_PX := 64.0
const BUILDING_PX := 68.0
## How far the dark edge around a drawn silhouette reaches past it.
const SCENERY_EDGE := 1.6
## The part of an atlas cell that is the object rather than the ground around it:
## the middle, where every one of these tiles draws its peak, canopy or building.
## The scenery's colour is averaged over this and nothing else.
const OBJECT_WINDOW := Rect2i(20, 14, 24, 30)

## The snowline on a ridge, and a building's two window states.
const SNOW := Color(0.933, 0.953, 0.965)
const WINDOW_LIT := Color(CutscenePalette.GOLD, 0.85)
const WINDOW_DARK := Color(CutscenePalette.SKY_HORIZON, 0.45)

## Cached average colour per sampled atlas band — the horizon ridge's tint and the
## scenery's. Keyed by atlas (column, row, window) rather than terrain id so an
## owner-tinted city ridge follows the same team colour the board paints, and the
## two windows one cell is read at cannot overwrite each other.
static var _tint_cache: Dictionary = {}
## The atlas as a mutable RGBA8 Image, decompressed once for `cell_tint`'s reads
## (MapThumbnail._source_image documents the same trade).
static var _atlas_image: Image


## How tall a kind stands at full size, so a caller scales that rather than
## naming a pixel height of its own.
static func height_of(kind: StringName) -> float:
	match kind:
		TerrainType.TREES:
			return TREE_PX
		TerrainType.PEAKS:
			return PEAK_PX
		_:
			return BUILDING_PX


## One piece of scenery, standing on `base` at `height` in `shade`.
static func draw_shape(
	canvas: CanvasItem, kind: StringName, base: Vector2, height: float, shade: Color
) -> void:
	match kind:
		TerrainType.TREES:
			_draw_tree(canvas, base, height, shade)
		TerrainType.PEAKS:
			_draw_peak(canvas, base, height, shade)
		_:
			_draw_building(canvas, base, height, shade)


## The flattened contact shadow a piece of scenery casts, sized off its own
## height. Drawn under the shape, and the reason a drawn silhouette sits on the
## ground plane rather than floating over it.
static func draw_contact_shadow(
	canvas: CanvasItem, base: Vector2, radius: float, alpha: float
) -> void:
	canvas.draw_set_transform(base + Vector2(0.0, -2.0), 0.0, Vector2(1.0, 0.24))
	canvas.draw_circle(Vector2.ZERO, radius, Color(CutscenePalette.GROUND_SHADOW, alpha))
	canvas.draw_set_transform(Vector2.ZERO)


## A conifer: a short dark trunk under three stacked skirts, each narrower and a
## shade lighter than the one below, which is what makes a flat triangle read as
## a tree rather than as a road sign.
static func _draw_tree(canvas: CanvasItem, base: Vector2, height: float, shade: Color) -> void:
	var half := height * 0.30
	canvas.draw_rect(
		Rect2(base.x - height * 0.05, base.y - height * 0.30, height * 0.10, height * 0.30),
		shade.darkened(0.45)
	)
	for tier in 3:
		var top := base.y - height * (0.42 + tier * 0.22)
		var bottom := top + height * 0.30
		var spread := half * (1.0 - tier * 0.24)
		_outlined_triangle(
			canvas,
			Vector2(base.x - spread, bottom),
			Vector2(base.x + spread, bottom),
			Vector2(base.x, top),
			shade.darkened(0.34 - tier * 0.11)
		)


## A triangle with a hard dark edge around it. Scenery is drawn in the terrain's
## own colour, and woods over plains is green on green — the outline is what keeps
## a pine legible against ground the same hue, the way every round in the volley
## carries one for the same reason.
static func _outlined_triangle(
	canvas: CanvasItem, a: Vector2, b: Vector2, c: Vector2, fill: Color
) -> void:
	var middle := (a + b + c) / 3.0
	var grown := PackedVector2Array()
	for corner in [a, b, c]:
		grown.append(corner + (corner - middle).normalized() * SCENERY_EDGE)
	canvas.draw_colored_polygon(grown, Color(CutscenePalette.STROKE, 0.55))
	canvas.draw_colored_polygon(PackedVector2Array([a, b, c]), fill)


## A ridge: one broad triangle with a snowline capping it.
static func _draw_peak(canvas: CanvasItem, base: Vector2, height: float, shade: Color) -> void:
	var half := height * 0.78
	var apex := Vector2(base.x, base.y - height)
	_outlined_triangle(
		canvas,
		Vector2(base.x - half, base.y),
		Vector2(base.x + half, base.y),
		apex,
		shade.darkened(0.28)
	)
	var cap := height * 0.34
	var cap_half := half * cap / height
	var snowline := PackedVector2Array(
		[
			Vector2(apex.x - cap_half, apex.y + cap),
			Vector2(apex.x + cap_half, apex.y + cap),
			apex,
		]
	)
	canvas.draw_colored_polygon(snowline, SNOW)


## A block with a darker parapet and lit windows. The windows are what sell it at
## this size — a plain rectangle reads as a wall, and two rows of squares read as
## somewhere people are.
static func _draw_building(canvas: CanvasItem, base: Vector2, height: float, shade: Color) -> void:
	var width := height * 0.52
	var left := base.x - width * 0.5
	canvas.draw_rect(Rect2(left, base.y - height, width, height), shade.darkened(0.18))
	canvas.draw_rect(Rect2(left, base.y - height, width, height * 0.07), shade.darkened(0.45))
	# The sunless face, so the block has a corner rather than being a flat card.
	canvas.draw_rect(
		Rect2(left + width * 0.82, base.y - height, width * 0.18, height), shade.darkened(0.38)
	)
	var columns := 2
	var rows := maxi(2, int(height / 14.0))
	var pane := Vector2(width * 0.17, height * 0.055)
	for row in rows:
		for column in columns:
			var at := Vector2(
				left + width * (0.22 + column * 0.34), base.y - height * 0.86 + row * height * 0.13
			)
			if at.y + pane.y > base.y - height * 0.06:
				continue
			var pane_tint := WINDOW_LIT if (row + column) % 3 == 0 else WINDOW_DARK
			canvas.draw_rect(Rect2(at, pane), pane_tint)


# --- the sky over it ----------------------------------------------------------


## Where a diorama's ground plane starts, measured down its arena. `ground_ratio`
## is the share the plane fills and stays each stage's own — the two frame their
## horizons a little differently on purpose.
static func horizon_of(arena: Rect2, ground_ratio: float) -> float:
	return arena.position.y + arena.size.y * (1.0 - ground_ratio)


## The graded sky above that horizon, in `bands` steps. The band count and both
## ends are the caller's — how coarse a stage wants its gradient, and what hour it
## is fought at, are that stage's, while grading one into the other is not. The
## defaults are the band's daylight.
static func draw_sky_gradient(
	canvas: CanvasItem,
	arena: Rect2,
	width: float,
	horizon: float,
	bands: int,
	top_shade: Color = CutscenePalette.SKY_TOP,
	low_shade: Color = CutscenePalette.SKY_HORIZON
) -> void:
	for i in bands:
		var top := arena.position.y + (horizon - arena.position.y) * float(i) / bands
		var bottom := arena.position.y + (horizon - arena.position.y) * float(i + 1) / bands
		var shade := top_shade.lerp(low_shade, float(i) / float(bands - 1))
		canvas.draw_rect(Rect2(0.0, top, width, bottom - top + 1.0), shade)


## One blocky cloud. Where the clouds hang is each stage's own; what a cloud
## looks like is not.
static func draw_cloud(canvas: CanvasItem, at: Vector2, scale: float) -> void:
	var white := Color(1.0, 1.0, 1.0, 0.85)
	canvas.draw_rect(Rect2(at.x - 30.0 * scale, at.y, 60.0 * scale, 9.0 * scale), white)
	canvas.draw_circle(at + Vector2(-14.0, 1.0) * scale, 9.0 * scale, white)
	canvas.draw_circle(at + Vector2(2.0, -3.0) * scale, 13.0 * scale, white)
	canvas.draw_circle(at + Vector2(18.0, 0.0) * scale, 8.0 * scale, white)


# --- colours sampled off the board's own art ----------------------------------


## The terrain tile's average colour, for the horizon ridge behind it. Sampled
## off the art rather than tabled here, so a new terrain — or a repainted one —
## needs no entry in the presentation layer at all.
static func ground_tint(column: int, row: int) -> Color:
	return cell_tint(column, row, Rect2i(0, 0, BattleView.TERRAIN_PX, BattleView.TERRAIN_PX))


## And the colour of the *object* on that cell, for the scenery standing here.
##
## Only the middle of the cell is sampled, and that window is the whole idea: a
## mountain tile is a grey peak drawn on a green square, so averaging the square
## returns grass and paints the ridge the colour of the field it rises out of.
## Every one of these tiles is its object drawn centred with its ground around the
## outside — true of the peak, the canopy and the tower alike, which is why one
## window serves all three and no shape needs a colour of its own.
static func object_tint(column: int, row: int) -> Color:
	return cell_tint(column, row, OBJECT_WINDOW)


## Average colour over one window of one atlas cell, counting only the pixels
## that are there. The five property columns ship as transparent overlays, so a
## window over a roof lands on alpha as often as on tile, and a transparent pixel
## read as black drags a city's roof a third of the way to it.
static func cell_tint(column: int, row: int, window: Rect2i) -> Color:
	var key := [column, row, window]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var tint := CutscenePalette.PLATE
	var image := _atlas_source_image()
	if image != null:
		var total := Color(0.0, 0.0, 0.0)
		var samples := 0
		for y in range(window.position.y, window.end.y, 2):
			for x in range(window.position.x, window.end.x, 2):
				var pixel := image.get_pixel(
					column * BattleView.TERRAIN_PX + x, row * BattleView.TERRAIN_PX + y
				)
				if pixel.a <= 0.0:
					continue
				total += Color(pixel.r, pixel.g, pixel.b)
				samples += 1
		if samples > 0:
			tint = Color(total.r / samples, total.g / samples, total.b / samples)
	_tint_cache[key] = tint
	return tint


## The atlas image `cell_tint` samples, decompressed once and kept — `get_image`
## on every cache miss was ~140 decompressions a run.
static func _atlas_source_image() -> Image:
	if _atlas_image == null:
		_atlas_image = (load(BattleView.ATLAS_PATH) as Texture2D).get_image()
		if _atlas_image.get_format() != Image.FORMAT_RGBA8:
			_atlas_image.convert(Image.FORMAT_RGBA8)
	return _atlas_image
