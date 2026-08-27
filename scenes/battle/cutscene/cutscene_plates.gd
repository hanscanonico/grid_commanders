class_name CutscenePlates
extends RefCounted
## The chrome both cut-in stages hang their diorama in: the two plates and the
## arena between them, the defence stars on the lower one, and the cell a figure
## is blown up to. One declaration each, the way CutscenePalette owns the colours
## and CutsceneScenery the shapes.
##
## CutsceneSide and CaptureStage are structural siblings and drew this frame
## twice, down to both halves of every constant. What stays each stage's is what
## differs between them — the slide direction, the name row, the pips, the
## CAPTURE chip — and each still draws its own; what is here is only what they
## cannot disagree about without the two frames reading as different films.
##
## Draws on the canvas it is handed and reads nothing else, so a posed still
## stays a pure function of its cut-in's clock.

## The plates the arena is framed by, top and bottom.
const TOP_H := 26
const BOT_H := 20
## The figure cell, blown up at 1:1 — the board's own art, never rescaled, so it
## is the sprite's cell and not a size of this layer's own. Taller than it is
## wide and anchored by its footprint, so FIGURE_H is drawn above the feet.
const FIGURE_PX := UnitSprite.SPRITE_W
const FIGURE_H := UnitSprite.SPRITE_H
## The defence row: how many stars are printed and how far apart. The step is
## signed by the caller, so a mirrored half reads its row inward like the rest of
## its plate.
const MAX_STARS := 4
const STAR_STEP := 11.0


## The band left between the two plates — the diorama's own frame.
static func arena(size: Vector2) -> Rect2:
	return Rect2(0.0, TOP_H, size.x, size.y - TOP_H - BOT_H)


## Both plates and the rule under each. Called inside the caller's own slide
## transform, so a stage that slides its chrome in slides this with it.
static func draw_frames(canvas: CanvasItem, size: Vector2, alpha: float) -> void:
	canvas.draw_rect(Rect2(0.0, 0.0, size.x, TOP_H), Color(CutscenePalette.PLATE, alpha))
	canvas.draw_rect(Rect2(0.0, TOP_H - 2.0, size.x, 2.0), Color(CutscenePalette.STROKE, alpha))
	var bottom := size.y - BOT_H
	canvas.draw_rect(Rect2(0.0, bottom, size.x, BOT_H), Color(CutscenePalette.PLATE, alpha))
	canvas.draw_rect(Rect2(0.0, bottom, size.x, 2.0), Color(CutscenePalette.STROKE, alpha))


## The defence row, `lit` of MAX_STARS filled. `first` is the leading star's
## centre and `step` the signed stride from it.
static func draw_stars(
	canvas: CanvasItem, first: Vector2, step: float, lit: int, alpha: float
) -> void:
	for i in MAX_STARS:
		var center := first + Vector2(step * i, 0.0)
		var tint := CutscenePalette.GOLD if i < lit else CutscenePalette.STAR_OFF
		canvas.draw_colored_polygon(
			CutsceneFx.star_points(center, 4.5), Color(tint, tint.a * alpha)
		)


static func terrain_atlas() -> Texture2D:
	return load(BattleView.ATLAS_PATH)


## Which pose of an idle clip a stage is drawing, off its own cut-in's clock at
## the board's ambient cadence — never BoardBeat.frame's wall clock, which would
## make a posed still depend on when the shutter fired.
static func figure_now(figures: Array[AtlasTexture], clock: float) -> AtlasTexture:
	return figures[BoardBeat.frame_at(BoardBeat.AMBIENT_MS, int(clock * 1000.0))]
