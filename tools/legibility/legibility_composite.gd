class_name LegibilityComposite
extends RefCounted
## One cell of the board, or one crop of a cut-in, stacked out of the shipped
## art in the order the scene stacks it.
##
## battle.tscn's node order is the stacking order and this follows it exactly:
## the terrain layer, then the reach / fire / threat washes over it, then the
## unit, then the fog shroud over all of them. Fog sitting *above* the units is
## why a fogged cell loses separation on both sides at once, and the washes
## sitting *below* them is why a wash only ever moves the ground.
##
## Two patterns are spelled here rather than read, because both live somewhere
## that cannot be evaluated without a viewport, and both are one line:
## the acted scrim's screen-space checkerboard (UnitSprite._ACTED_SCRIM's
## `mod(floor(x) + floor(y), 2.0) < 0.5`, darkening by LegibilityArt's parsed
## factor) and the threat lens's diagonal stripe
## (BattleOverlays._build_threat_tile_set's `(x + y) % THREAT_STRIPE`). Every
## other number is read from its owner.

## The washes a board cell may be read under. NONE is the bare board; MOVE,
## ATTACK and THREAT are the three overlay layers; FOG is the shroud, which is
## a different layer rather than a fourth wash and is why this is one list
## rather than two flags.
enum Overlay { NONE, MOVE, ATTACK, THREAT, FOG }

## The board draws a cell at BattleView.TILE; the cut-in draws the same art at
## its own resolution. Nearest filtering means a board pixel is one texel of the
## 64px cell, so any integer zoom of the board shows these same values.
const BOARD_PX := BattleView.TILE
const CUTIN_PX := BattleView.TERRAIN_PX

var art: LegibilityArt
## The art the figure is cut from, and the art of the ground under it: each a
## {"image": Image, "origin": Vector2i, "px": int} as LegibilityArt hands them
## over.
var figure_cell: Dictionary
var ground_cell: Dictionary
var overlay: Overlay = Overlay.NONE
## True for a unit on the side in hand that has already acted — the one state
## that changes the figure's own pixels.
var exhausted := false
## Side of the composite in pixels: BOARD_PX or CUTIN_PX.
var size := BOARD_PX


## Every pixel the figure covers, composited.
func figure_colours() -> PackedColorArray:
	return _sample(true)


## The ground plate across the whole cell, composited — the tile as it reads,
## independent of which figure is standing on it.
func ground_colours() -> PackedColorArray:
	return _sample(false)


func figure_luminances() -> PackedFloat32Array:
	return LegibilityMetric.luminances(figure_colours())


func ground_luminances() -> PackedFloat32Array:
	return LegibilityMetric.luminances(ground_colours())


## The composite as an image, for eyeballing one cell the sweep has judged.
func to_image() -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			image.set_pixel(x, y, _pixel(x, y))
	return image


func _sample(figure: bool) -> PackedColorArray:
	var values := PackedColorArray()
	for y in size:
		for x in size:
			if figure and not _figure_covers(x, y):
				continue
			values.append(_pixel(x, y) if figure else _fogged(_ground(x, y)))
	return values


func _pixel(x: int, y: int) -> Color:
	var colour := _ground(x, y)
	if _figure_covers(x, y):
		colour = _figure(x, y)
	return _fogged(colour)


func _ground(x: int, y: int) -> Color:
	var colour := _texel(ground_cell, x, y)
	var wash := _wash(x, y)
	return LegibilityMetric.over(wash, colour) if wash.a > 0.0 else colour


func _figure(x: int, y: int) -> Color:
	var colour := _texel(figure_cell, x, y)
	if exhausted and (x + y) % 2 == 0:
		colour = Color(
			colour.r * art.acted_scrim, colour.g * art.acted_scrim, colour.b * art.acted_scrim
		)
	return colour


func _figure_covers(x: int, y: int) -> bool:
	return _texel(figure_cell, x, y).a > 0.0


func _fogged(colour: Color) -> Color:
	if overlay != Overlay.FOG:
		return colour
	return LegibilityMetric.over(art.fog_modulate, colour)


## The wash landing on this pixel: the overlay tile's own art times the layer's
## modulate. The threat lens has no art file — its tile is generated — so its
## stripe is evaluated here and the wash is white where the stripe is lit.
func _wash(x: int, y: int) -> Color:
	var tint := _modulate()
	if tint.a <= 0.0:
		return Color(0, 0, 0, 0)
	var tile := Vector2i(_tile_pixel(x), _tile_pixel(y))
	var mark := Color.WHITE
	if overlay == Overlay.THREAT:
		var stripe := BattleOverlays.THREAT_STRIPE
		if (tile.x + tile.y) % stripe >= stripe / 2:
			return Color(0, 0, 0, 0)
	else:
		mark = art.overlay.get_pixel(tile.x, tile.y)
	return Color(mark.r * tint.r, mark.g * tint.g, mark.b * tint.b, mark.a * tint.a)


func _modulate() -> Color:
	match overlay:
		Overlay.MOVE:
			return OverlayPalette.MOVE
		Overlay.ATTACK:
			return OverlayPalette.ATTACK
		Overlay.THREAT:
			return OverlayPalette.THREAT
	return Color(0, 0, 0, 0)


## Nearest sampling of an art cell at this composite's resolution, which is what
## the project's nearest texture filter does when the layer is scaled down. The
## cell states its own source size, so the figure is sampled at UnitSprite's and
## the ground at the board's.
##
## A cell that names an `under` origin is an overlay over that second cell of the
## same image — a property building on its ground — and the two are composited
## here, which is what the board's two layers do.
func _texel(cell: Dictionary, x: int, y: int) -> Color:
	var image: Image = cell["image"]
	var origin: Vector2i = cell["origin"]
	var step := float(cell["px"]) / float(size)
	var texel := Vector2i(int((x + 0.5) * step), int((y + 0.5) * step))
	var colour := image.get_pixel(origin.x + texel.x, origin.y + texel.y)
	if not cell.has("under"):
		return colour
	var under: Vector2i = cell["under"]
	return LegibilityMetric.over(colour, image.get_pixel(under.x + texel.x, under.y + texel.y))


## The overlay tile is authored at BattleView.TILE; this is the pixel of it a
## composite pixel lands on.
func _tile_pixel(at: int) -> int:
	return int((at + 0.5) * float(BOARD_PX) / float(size))
