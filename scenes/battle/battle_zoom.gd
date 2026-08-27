class_name BattleZoom
extends RefCounted
## Owns the battle camera's zoom: the ladder itself, the current rung, and the
## clamp against the board's floor. Battle decides when to zoom and BoardCamera
## owns the camera itself — this sits between them, split out of battle.gd so the
## interaction flow could shed a responsibility (the gdlintrc line ratchet).
##
## **The rungs are whole numbers, and the floor is the one that frames the board.**
## The board art is sampled with nearest filtering, so a rung that is not a whole
## number of screen pixels per world pixel drops and doubles rows — and which rows
## it drops moves as the camera pans, which reads as crawling edges once anything
## on the board is animated. That is what the whole rungs buy, and every rung a
## match is played at is one.
##
## The furthest-out rung is the deliberate exception: it is the survey view, the
## one that frames the whole map, and a board bigger than 1x has no whole rung
## that can. Snapping it away left Bulwark's 49x32 showing half of itself at
## maximum zoom-out, which is a worse frame than a crawling edge on a view nobody
## fights from (playtest, 2026-08-19).
##
## `tests/unit/test_texel_stability.gd` is what holds this to it.

const MAX_ZOOM := 5.0

## The rung a match opens on, wherever the board can hold it.
const DEFAULT_ZOOM := 2.0

var _board: BoardCamera
var _rungs := rungs_for(DEFAULT_ZOOM)
var _zoom := DEFAULT_ZOOM


func _init(board: BoardCamera) -> void:
	_board = board


## The furthest-out rung a board is offered: exactly far enough to frame the
## whole map, with the backdrop filling whatever the map's aspect leaves over.
static func floor_for(view: Vector2, map_px: Vector2) -> float:
	return minf(minf(view.x / map_px.x, view.y / map_px.y), MAX_ZOOM)


## The ladder a board offers, furthest out first: its floor, then every whole
## rung above it. The one statement of what rungs exist.
static func rungs_for(floor_zoom: float) -> PackedFloat64Array:
	var rungs := PackedFloat64Array([floor_zoom])
	for whole in range(1, int(MAX_ZOOM) + 1):
		if whole > floor_zoom:
			rungs.append(float(whole))
	return rungs


## How far the player may zoom out depends on the viewport, so the ladder is
## worked out here; BoardCamera owns the camera itself.
func setup() -> void:
	_rungs = rungs_for(_board.min_zoom())
	set_zoom(_zoom)


func set_zoom(zoom: float) -> void:
	settle_at(_nearest_rung(zoom))


## The ladder this board offers, so a caller that has to reason about the whole of
## it — the pinch's gain is the one — reads it here rather than rebuilding it.
func rungs() -> PackedFloat64Array:
	return _rungs


## Which rung the board is standing on: where a gesture measures its own steps
## from.
func rung_index() -> int:
	return _nearest_rung(_zoom)


## The zoom-step actions — keys, wheel and the pad's shoulders alike. Returns true
## when it consumed the event, so the input handler stops there — the two branches
## this replaced sat first in that chain and swallowed the event the same way.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed(&"zoom_in"):
		settle_at(rung_index() + 1)
		return true
	if event.is_action_pressed(&"zoom_out"):
		settle_at(rung_index() - 1)
		return true
	return false


## **The one way onto a rung**, whichever end of the ladder the index falls off:
## a key, a dock chip and a pinch all arrive here, so nothing anywhere can leave
## the board resting between two rungs.
func settle_at(index: int) -> void:
	_zoom = _rungs[clampi(index, 0, _rungs.size() - 1)]
	_board.set_zoom(_zoom)


## Which rung a level asks for: the closest one, so the opening DEFAULT_ZOOM lands
## on the floor of a board too small to hold it and on DEFAULT_ZOOM everywhere
## else.
func _nearest_rung(zoom: float) -> int:
	var best := 0
	for i in _rungs.size():
		if absf(_rungs[i] - zoom) < absf(_rungs[best] - zoom):
			best = i
	return best
