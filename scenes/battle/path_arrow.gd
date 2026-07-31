class_name PathArrow
extends Node2D
## The route a selected unit would walk, drawn the way a tactics game draws it:
## square bars laid from each cell's centre out to the edges it connects, a joint
## block where they meet, and an arrowhead on the destination.
##
## It replaced a Line2D, which carried the same information and read worse. A
## polyline mitres its corners, so a route that turns showed a diagonal across
## ground the unit walks squarely; and it ended in a blunt cap, so the cell the
## unit stops on and a cell the route merely passes through looked the same.
##
## The geometry is `segments`, a pure function of the path, so it is checked
## without a scene the way SeatStrip.normalised_sides and TransitionInput are.
## `_draw` only paints what that returns.

const TILE := 16

## Bar thickness, how far the arrowhead reaches past the cell centre, and half
## its base — the design reference's 10/12/18 against a 44px tile, brought down
## to this board's 16.
const BAR := 4.0
const HEAD_LEN := 5.0
const HEAD_HALF := 3.5

## The spec's `drop-shadow(0 1px 0 var(--ink))`: the whole shape painted once in
## ink a pixel low before the red goes over it. A hard offset rather than a blur,
## like every other shadow in the design system (UiTheme.hard_shadow).
const SHADOW_OFFSET := Vector2(0, 1)


## One cell of the route: where it sits, which neighbours it is joined to, and —
## on the destination alone — which way the arrowhead points.
class Segment:
	var cell: Vector2i
	## Unit steps toward each connected neighbour: one at either end of the
	## route, two in the middle.
	var arms: Array[Vector2i] = []
	## Direction of travel, on the last cell only; Vector2i.ZERO elsewhere.
	var head := Vector2i.ZERO

	func _init(p_cell: Vector2i) -> void:
		cell = p_cell


var _segments: Array[Segment] = []


## The route broken into per-cell geometry. A path of fewer than two cells draws
## nothing: the unit has not been asked to go anywhere yet, and a lone joint
## block under it would read as a marker rather than a route.
static func segments(path: Array[Vector2i]) -> Array[Segment]:
	var out: Array[Segment] = []
	if path.size() < 2:
		return out
	for i in path.size():
		var segment := Segment.new(path[i])
		if i > 0:
			segment.arms.append(path[i - 1] - path[i])
		if i < path.size() - 1:
			segment.arms.append(path[i + 1] - path[i])
		else:
			# The head points the way the unit travels, which is the reverse of
			# the arm reaching back to where it came from.
			segment.head = path[i] - path[i - 1]
		out.append(segment)
	return out


## The bar from a cell's centre out to the edge it shares with `arm`'s neighbour.
## Built from its two corners because half the arms run in the negative direction
## and a position-and-size rect would come out with a negative extent.
static func bar_rect(centre: Vector2, arm: Vector2i) -> Rect2:
	var reach := Vector2(arm) * (TILE / 2.0)
	var across := Vector2(absi(arm.y), absi(arm.x)) * (BAR / 2.0)
	var near := centre - across
	var far := centre + reach + across
	return Rect2(near.min(far), (far - near).abs())


static func head_points(centre: Vector2, direction: Vector2i) -> PackedVector2Array:
	var forward := Vector2(direction)
	var across := Vector2(-forward.y, forward.x)
	return PackedVector2Array(
		[
			centre + forward * HEAD_LEN,
			centre + across * HEAD_HALF,
			centre - across * HEAD_HALF,
		]
	)


## Draws `path`, or clears when it is too short to be a route. The same contract
## the Line2D had, so none of its callers changed.
func set_path(path: Array[Vector2i]) -> void:
	_segments = segments(path)
	queue_redraw()


func _draw() -> void:
	if _segments.is_empty():
		return
	_paint(SHADOW_OFFSET, UiTheme.HARD_BORDER)
	_paint(Vector2.ZERO, UiTheme.DANGER)


func _paint(offset: Vector2, color: Color) -> void:
	for segment in _segments:
		var centre := Vector2(segment.cell * TILE) + Vector2(TILE, TILE) / 2.0 + offset
		for arm in segment.arms:
			draw_rect(bar_rect(centre, arm), color)
		draw_rect(Rect2(centre - Vector2(BAR, BAR) / 2.0, Vector2(BAR, BAR)), color)
		if segment.head != Vector2i.ZERO:
			draw_colored_polygon(head_points(centre, segment.head), color)
