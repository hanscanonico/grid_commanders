class_name PortraitShot3D
extends RefCounted
## How a general's 3D portrait is shot: an orthographic lens laid over the pixel
## bust's own grid, so the 3D still frames the head where the drawing does and
## every surface lays it out by the drawing's rules. Pure arithmetic over the
## figure's measurements and `CommanderVisuals`' bust geometry, checked without
## a scene.
##
## Two variants, the two drawings a field chooses between: `BUST`, the whole
## 110x134 drawing, and `FACE`, the chip — `FACE_SHOT` of the bust's grid, the
## head and nothing else.

const BUST := &"bust"
const FACE := &"face"
## Screen pixels the still is rendered at per texel of the drawing it stands in
## for: a bust slot is the drawing at 1:1 on the 640x360 canvas, so five covers a
## window five times the canvas before the still is magnified.
const BUST_SCALE := 5
## The chip is drawn up to `CommanderVisuals.CHIP_ZOOM` texels a texel, so it
## gets more pixels per texel than the bust.
const FACE_SCALE := 8
## The inked window the bust stands in, in bust texels — the generator's
## `backdrop.WINDOW` on the 110x134 grid; the head breaks out over its top.
const WINDOW := Rect2i(6, 38, 98, 96)
const WINDOW_PEN := 2
## Where the 3D head sits on the bust's grid: its hair top on `HEAD_TOP_ROW`,
## its chin `HEAD_ROWS` below. Smaller than the drawing's head, because the
## figure's is wider than tall and needs room inside the window's sides.
const HEAD_TOP_ROW := 26
const HEAD_ROWS := 64
## The chip's square of the grid: the head, centred, a little air round it.
const FACE_SHOT := Rect2i(17, 20, 76, 76)
## The figure turned a little off the lens and the lens a little above the
## eyes, so the still reads as a solid head rather than a flat face.
const YAW_DEG := -24.0
const PITCH_DEG := 8.0
## How far from the aim the lens stands; orthographic, so only clearance.
const LENS_DISTANCE := 2.0
## The figure's hair top and chin, at rest, in the actor's own space.
const HEAD_PIVOT_Y := (
	CommanderFigure3D.HIP_Y
	+ CommanderFigure3D.PIVOTS[&"torso"].y
	+ CommanderFigure3D.PIVOTS[&"head"].y
)
const HEAD_TOP_Y := HEAD_PIVOT_Y + CommanderFigure3D.HEAD_TOP
const CHIN_Y := HEAD_PIVOT_Y + CommanderFigure3D.HEAD_Y - CommanderFigure3D.HEAD_SIZE.y / 2.0


## World units per texel of the pixel bust.
static func texel() -> float:
	return (HEAD_TOP_Y - CHIN_Y) / float(HEAD_ROWS)


## The part of the bust's grid a variant shows.
static func region(variant: StringName) -> Rect2i:
	if variant == FACE:
		return FACE_SHOT
	return Rect2i(Vector2i.ZERO, CommanderVisuals.PORTRAIT_SIZE)


## The size a field lays the still out at — the drawing it stands in for.
static func drawn(variant: StringName) -> Vector2i:
	return CommanderVisuals.FACE_SIZE if variant == FACE else CommanderVisuals.PORTRAIT_SIZE


## The still's own pixels.
static func pixels(variant: StringName) -> Vector2i:
	return drawn(variant) * (FACE_SCALE if variant == FACE else BUST_SCALE)


## The lens's orthographic height, in world units.
static func lens_height(variant: StringName) -> float:
	return region(variant).size.y * texel()


## Where the lens aims, in the actor's own space: the region's middle, the
## figure facing -Z toward it. Seen from the front the figure's +X is on the
## lens's left, so a region right of the bust's middle is at -X.
static func aim(variant: StringName) -> Vector3:
	var middle := Rect2(region(variant)).get_center()
	var top := HEAD_TOP_Y + HEAD_TOP_ROW * texel()
	var across := (middle.x - CommanderVisuals.PORTRAIT_SIZE.x / 2.0) * texel()
	return Vector3(-across, top - middle.y * texel(), 0.0)


## Where the lens stands, in front of the face and a little above, looking
## down at `aim`.
static func eye(variant: StringName) -> Vector3:
	var pitch := deg_to_rad(PITCH_DEG)
	return aim(variant) + Vector3(0.0, sin(pitch), -cos(pitch)) * LENS_DISTANCE


## The inked window in the still's pixels. The chip shows only the middle of
## it, so its window runs past the still's edges and only the top rule shows.
static func window(variant: StringName) -> Rect2i:
	var shown := region(variant)
	var scale := Vector2(pixels(variant)) / Vector2(shown.size)
	var from := (Vector2(WINDOW.position - shown.position) * scale).round()
	var to := (Vector2(WINDOW.end - shown.position) * scale).round()
	return Rect2i(Vector2i(from), Vector2i(to - from))


## The window's ink pen, in the still's pixels.
static func pen(variant: StringName) -> int:
	var scale := float(pixels(variant).y) / region(variant).size.y
	return maxi(1, roundi(WINDOW_PEN * scale))


## The cache's name for one still: a general, one of the two drawings.
static func key(id: StringName, variant: StringName) -> String:
	return "%s/%s" % [id, variant]
