class_name BattleZoom
extends RefCounted
## Owns the battle camera's zoom: the ladder itself, the current rung, and the
## clamp against the view's floor. Battle decides when to zoom and the view owns
## the camera itself — this sits between them, split out of battle.gd so the
## interaction flow could shed a responsibility (the gdlintrc line ratchet).
##
## **The ladder is integers, and this is the one place that says so.** The board
## art is sampled with nearest filtering, so a rung that is not a whole number of
## screen pixels per world pixel drops and doubles rows — and which rows it drops
## moves as the camera pans, which reads as crawling edges the moment anything on
## the board is animated. The ladder used to be anchored on the per-map fit ratio
## (rungs like 1.37 / 2.37 / … / 5.0), which put every map but a lucky one on
## fractional sampling at every rung. It is now anchored on `floor_for` and
## stepped by whole rungs, and the remainder a whole rung leaves over is
## letterboxed by the board's own out-of-bounds backdrop — the camera limits
## already centre a map its rung overshoots (`BattleView._apply_camera_limits`).
##
## `tests/unit/test_texel_stability.gd` is what holds this to it.

const MAX_ZOOM := 5.0
const MIN_ZOOM := 1.0
const STEP := 1.0

var _view: BattleView
var _zoom := 2.0
var _min_zoom := MIN_ZOOM


func _init(view: BattleView) -> void:
	_view = view


## The furthest-out rung a board is offered: the largest whole rung that still
## shows the map entire, and MIN_ZOOM for a map too big for even that — a board
## wider than the window scrolls, which is the honest floor now that "fit it
## whole" is no longer allowed to buy itself a fractional rung.
static func floor_for(view: Vector2, map_px: Vector2) -> float:
	var fit := minf(view.x / map_px.x, view.y / map_px.y)
	return clampf(floorf(fit), MIN_ZOOM, MAX_ZOOM)


## How far the player may zoom out depends on the viewport, so the clamp is
## worked out here; the view owns the camera itself.
func setup() -> void:
	_min_zoom = _view.min_zoom()
	set_zoom(_zoom)


func set_zoom(zoom: float) -> void:
	_zoom = clampf(roundf(zoom), _min_zoom, MAX_ZOOM)
	_view.set_zoom(_zoom)


## The zoom-step actions — keys, wheel and the pad's shoulders alike. Returns true
## when it consumed the event, so the input handler stops there — the two branches
## this replaced sat first in that chain and swallowed the event the same way.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed(&"zoom_in"):
		set_zoom(_zoom + STEP)
		return true
	if event.is_action_pressed(&"zoom_out"):
		set_zoom(_zoom - STEP)
		return true
	return false
