class_name CaptureBackdrop
extends RefCounted
## Everything behind the capture cut-in's squad: the graded evening sky, the low
## sun, the two drifting skylines and the ground plane the property stands on.
##
## Split out of CaptureStage for the reason CutsceneScenery is split out of both
## cut-ins — the stage draws the capture, this draws the place it happens in, and
## the stage is already the longest file in the family. Draws on the canvas it is
## handed and reads nothing else: every layer is a pure function of the arena, the
## two colours sampled off the board's own atlas and the cut-in's clock, so a
## posed still stays a pure function of that clock (plan CP3).
##
## The skyline's colour is the *property's* roof tint, which is the capturer's
## faction row once the flip lands. That is deliberate and is COM-10's rule kept:
## the town behind the building recolours with the building rather than off a team
## int of its own, so two palettes can never share one frame.

## The warm end of the capture sky. The combat cut-in's daylight blue is
## CutscenePalette's; a capture is fought at the end of a day.
const SKY_LOW := Color(0.980, 0.851, 0.620)
## The low sun: where it hangs as a share of the width, how far above the horizon,
## its radius, and the colour of the disc. Its two haloes are drawn off the same.
const SUN_X := 0.78
const SUN_LIFT := 26.0
const SUN_PX := 17.0
const SUN := Color(1.0, 0.949, 0.800, 0.35)

## The far town: one entry per silhouette, an x as a share of the drift span, a
## height as a share of PROP_PX and a width as a share of its own height. Eight
## reads as a skyline; fewer reads as a row of blocks.
const FAR_TOWERS: Array[Vector3] = [
	Vector3(0.03, 0.30, 0.52),
	Vector3(0.14, 0.19, 0.74),
	Vector3(0.26, 0.42, 0.44),
	Vector3(0.38, 0.24, 0.62),
	Vector3(0.52, 0.35, 0.50),
	Vector3(0.65, 0.21, 0.80),
	Vector3(0.79, 0.38, 0.46),
	Vector3(0.91, 0.26, 0.66),
]
## And the nearer band, which drifts faster and sits darker — the parallax is the
## whole point of there being two.
const MID_TOWERS: Array[Vector3] = [
	Vector3(0.10, 0.50, 0.42),
	Vector3(0.44, 0.62, 0.36),
	Vector3(0.72, 0.46, 0.48),
]
## How fast each band slides, in pixels a second.
const FAR_DRIFT := 3.0
const MID_DRIFT := 8.0
## How far each band is taken from the roof tint toward black, and how far the far
## one is then washed into the sky it stands against — distance drains contrast
## here the same way it does down the ground's own recession.
const FAR_DARKEN := 0.55
const MID_DARKEN := 0.35
const FAR_HAZE := 0.30
const MID_ALPHA := 0.55
## The dust hanging over the town, and how high above the horizon it lies.
const HAZE_ALPHA := 0.10
const HAZE_PX := 10.0

## The ground plane's own greens, and how far each row is pulled toward the colour
## of the cell the property actually stands on — a desert or a city capture does
## not happen on a lawn.
const GRASS := Color(0.471, 0.784, 0.314)
const GRASS_DARK := Color(0.353, 0.651, 0.235)
const GROUND_BLEND := 0.4

## The faction light the low sun throws across the field: two thin wedges from the
## disc down to the property's feet, at an alpha that tints rather than paints.
const SHAFT_ALPHA := 0.06
const SHAFT_SPREAD := 0.35


## The graded sky, the low sun and the two clouds above it.
static func draw_sky(
	canvas: CanvasItem, arena: Rect2, width: float, horizon: float, bands: int
) -> void:
	CutsceneScenery.draw_sky_gradient(
		canvas, arena, width, horizon, bands, CutscenePalette.SKY_TOP, SKY_LOW
	)
	var sun := sun_at(width, horizon)
	canvas.draw_circle(sun, SUN_PX * 2.6, Color(SUN, SUN.a * 0.25))
	canvas.draw_circle(sun, SUN_PX * 1.6, Color(SUN, SUN.a * 0.5))
	canvas.draw_circle(sun, SUN_PX, Color(SUN.r, SUN.g, SUN.b, 0.9))
	CutsceneScenery.draw_cloud(
		canvas, Vector2(width * 0.22, arena.position.y + arena.size.y * 0.16), 1.0
	)
	CutsceneScenery.draw_cloud(
		canvas, Vector2(width * 0.72, arena.position.y + arena.size.y * 0.08), 0.66
	)


## Where the sun hangs, asked rather than spelled twice: the light shaft leaves
## from the same point the disc is drawn at.
static func sun_at(width: float, horizon: float) -> Vector2:
	return Vector2(width * SUN_X, horizon - SUN_LIFT)


## The town behind the capture: two bands of silhouettes with their feet on the
## horizon, both cut from `roof` — the property's own colour — so the skyline
## flips faction with the building it belongs to.
static func draw_skyline(
	canvas: CanvasItem, width: float, horizon: float, prop_px: float, roof: Color, clock: float
) -> void:
	var far := roof.darkened(FAR_DARKEN).lerp(SKY_LOW, FAR_HAZE)
	_draw_towers(canvas, FAR_TOWERS, width, horizon, prop_px, clock * FAR_DRIFT, far)
	canvas.draw_rect(
		Rect2(0.0, horizon - HAZE_PX, width, HAZE_PX), Color(CutscenePalette.DUST, HAZE_ALPHA)
	)
	var mid := Color(roof.darkened(MID_DARKEN), MID_ALPHA)
	_draw_towers(canvas, MID_TOWERS, width, horizon, prop_px, clock * MID_DRIFT, mid)


## One band. Each tower is drawn twice, a span apart, so the one leaving the right
## edge is already entering on the left and the loop has no seam in it.
static func _draw_towers(
	canvas: CanvasItem,
	towers: Array[Vector3],
	width: float,
	horizon: float,
	prop_px: float,
	drift: float,
	shade: Color
) -> void:
	var span := width * 1.25
	for tower in towers:
		var h := prop_px * tower.y
		var w := h * tower.z
		var x := fposmod(tower.x * span + drift, span)
		for at in PackedFloat32Array([x, x - span]):
			canvas.draw_rect(Rect2(at - w * 0.5, horizon - h, w, h), shade)
			canvas.draw_rect(
				Rect2(at - w * 0.22, horizon - h - h * 0.10, w * 0.44, h * 0.10), shade
			)


## The ground plane: rows that widen and lighten toward the front, each pulled
## toward `tint` — the colour of the board cell this capture is standing on.
static func draw_ground(
	canvas: CanvasItem, arena: Rect2, width: float, horizon: float, tint: Color
) -> void:
	var floor_y := arena.position.y + arena.size.y
	var depth := floor_y - horizon
	var near := GRASS.lerp(tint, GROUND_BLEND)
	var far := GRASS_DARK.lerp(tint, GROUND_BLEND)
	var y := horizon
	var row_h := depth * 0.06
	var toggle := 0
	while y < floor_y:
		var lit := lerpf(0.82, 1.0, clampf((y - horizon) / depth, 0.0, 1.0))
		var base := near if toggle % 2 == 0 else far
		canvas.draw_rect(
			Rect2(0.0, y, width, row_h + 1.0), Color(base.r * lit, base.g * lit, base.b * lit)
		)
		y += row_h
		row_h *= 1.5
		toggle += 1
	canvas.draw_rect(Rect2(0.0, horizon, width, 2.0), Color(far.darkened(0.35), 0.9))
	canvas.draw_rect(Rect2(0.0, horizon - 1.0, width, 1.0), Color(1.0, 1.0, 1.0, 0.3))
	canvas.draw_rect(Rect2(0.0, floor_y - 16.0, width, 16.0), Color(0.0, 0.0, 0.0, 0.14))


## The capturer's colour thrown down the field: two wedges from the point the low
## sun meets the horizon out to the property's feet. It starts on the horizon
## rather than at the disc because it is light lying on the ground — a wedge drawn
## from the disc itself crosses the sky and reads as a pane of glass over it.
static func draw_light_shaft(
	canvas: CanvasItem, sun: Vector2, horizon: float, base: Vector2, accent: Color
) -> void:
	var from := Vector2(sun.x, horizon)
	var reach := (base - from).length() * SHAFT_SPREAD
	for side in PackedFloat32Array([-1.0, 1.0]):
		var foot := base.x + reach * side
		var wedge := PackedVector2Array(
			[
				Vector2(from.x - 4.0, from.y),
				Vector2(from.x + 4.0, from.y),
				Vector2(foot + 26.0 * side, base.y),
				Vector2(foot, base.y),
			]
		)
		canvas.draw_colored_polygon(wedge, Color(accent, SHAFT_ALPHA))
