class_name TouchTarget
extends Control
## An invisible hit rectangle over a control drawn smaller than a finger: the
## chrome keeps the size it was designed at and the tap keeps its 44 px
## (mobile plan D8, "hit areas first, drawn chrome second").
##
## Drawn heights are not free here — every pixel of the two docked HUD bars feeds
## UiTheme.HUD_BARS_H, therefore BattleView's board viewport, therefore min_zoom
## and the floor rung of every board — so a control that grew to meet a thumb
## would move the opening frame of every match. A hit rectangle costs the board
## nothing.
##
## Built only on a touch build, through UiKit.touchable, which is the one caller.
##
## The one rule, and `inflation` is the whole of it: **a control claims the free
## space around it, up to the minimum, and never a neighbour's**. Two chips 4 px
## apart in a row cannot both answer the pixel between them — the topmost would
## simply win it, which is a stolen tap rather than a bigger one — so each takes
## half the gap and the growth that is left goes where nothing is standing. A row
## of buttons packed edge to edge therefore gains nothing in that axis, and that
## is the honest answer: there is no free space there to give. A neighbour lying
## diagonally is measured by neither axis' gap, so `_retreat` is a second pass that
## hands back whichever axis it reaches into by least.
##
## A tap on the area is the parent's press and only the parent's — the event is
## claimed here, so one finger still makes one receipt (mobile R1).

## Set once by `expand`; the caller's, because the metric belongs to UiTheme.
var _minimum := 0.0
## True between a press on this area and its release, so a tap that wandered off
## before letting go is cancelled rather than delivered.
var _armed := false


## Lays an area over `host` and hands it back. The area is a child, so it follows
## whatever the layout does with the host and dies with it.
static func expand(host: BaseButton, minimum: float) -> TouchTarget:
	var area := TouchTarget.new()
	area._minimum = minimum
	host.add_child(area)
	return area


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var host := get_parent() as Control
	if host != null:
		host.item_rect_changed.connect(_fit)
	# Deferred: a container places its children one after another, so the first
	# of them would measure a row whose later members are still at the origin.
	_fit.call_deferred()


## The hit rectangle `host` gets, in the coordinates its own rect is stated in.
## `screen` bounds it — an empty rect means unbounded — because half of a top
## bar's growth would otherwise go up off the canvas, where no finger can land.
##
## Pure, and the whole of the rule this class exists for, so it is checked without
## a scene (tests/unit/test_touch_target.gd) — PathArrow.segments' shape.
static func inflation(
	host: Rect2, neighbours: Array[Rect2], minimum: float, screen := Rect2()
) -> Rect2:
	var lead := Vector2(INF, INF)
	var trail := Vector2(INF, INF)
	for other: Rect2 in neighbours:
		if _shares_band(host.position.y, host.end.y, other.position.y, other.end.y):
			if other.end.x <= host.position.x:
				lead.x = minf(lead.x, (host.position.x - other.end.x) / 2.0)
			elif other.position.x >= host.end.x:
				trail.x = minf(trail.x, (other.position.x - host.end.x) / 2.0)
		if _shares_band(host.position.x, host.end.x, other.position.x, other.end.x):
			if other.end.y <= host.position.y:
				lead.y = minf(lead.y, (host.position.y - other.end.y) / 2.0)
			elif other.position.y >= host.end.y:
				trail.y = minf(trail.y, (other.position.y - host.end.y) / 2.0)
	if screen.has_area():
		lead = lead.min(host.position - screen.position)
		trail = trail.min(screen.end - host.end)
	var x := _spread(host.position.x, host.end.x, minimum, lead.x, trail.x)
	var y := _spread(host.position.y, host.end.y, minimum, lead.y, trail.y)
	var grown := Rect2(Vector2(x.x, y.x), Vector2(x.y - x.x, y.y - y.x))
	for other: Rect2 in neighbours:
		grown = _retreat(grown, host, other)
	return grown


## The second pass, and the one that makes "never a neighbour's" true rather than
## nearly true: growing both axes at once can reach a control that sits *diagonally*
## away, which neither axis' own gap ever measured. The rectangle gives that
## neighbour back the axis it overlaps by least — the smaller retreat of the two —
## and never gives back the host's own drawn rect.
static func _retreat(rect: Rect2, host: Rect2, other: Rect2) -> Rect2:
	if other.intersects(host) or not other.intersects(rect):
		return rect
	var axis := (
		0 if _retreat_cost(rect, host, other, 0) <= _retreat_cost(rect, host, other, 1) else 1
	)
	var trimmed := _trim(rect, host, other, axis)
	# The cheaper axis cannot always clear it: the retreat stops at the host's own
	# drawn rect, and where that binds the other axis is the one that has room. A
	# neighbour that does not touch the host is always disjoint on one of the two.
	if trimmed.intersects(other):
		trimmed = _trim(trimmed, host, other, 1 - axis)
	return trimmed


## How much of an edge one axis' retreat would cost, so the rectangle gives back
## the side it reaches into by least.
static func _retreat_cost(rect: Rect2, host: Rect2, other: Rect2, axis: int) -> float:
	if other.get_center()[axis] >= host.get_center()[axis]:
		return rect.end[axis] - other.position[axis]
	return other.end[axis] - rect.position[axis]


## Pulls one edge back clear of `other`, never past the host's own edge.
static func _trim(rect: Rect2, host: Rect2, other: Rect2, axis: int) -> Rect2:
	var position := rect.position
	var size := rect.size
	if other.get_center()[axis] >= host.get_center()[axis]:
		size[axis] = maxf(other.position[axis], host.end[axis]) - rect.position[axis]
	else:
		var edge := minf(other.end[axis], host.position[axis])
		size[axis] = rect.end[axis] - edge
		position[axis] = edge
	return Rect2(position, size)


## One axis, as the span it ends up covering: the control grows evenly toward
## `minimum`, and whatever one side cannot take — a neighbour, or the edge of the
## screen — the other side does.
static func _spread(
	from: float, to: float, minimum: float, room_before: float, room_after: float
) -> Vector2:
	var want := maxf(minimum - (to - from), 0.0)
	var room := Vector2(maxf(room_before, 0.0), maxf(room_after, 0.0))
	var before := minf(want / 2.0, room.x)
	var after := minf(want - before, room.y)
	return Vector2(from - minf(want - after, room.x), to + after)


## Whether two spans overlap on one axis — which is what makes a control a
## neighbour in the other one.
static func _shares_band(from: float, to: float, other_from: float, other_to: float) -> bool:
	return other_from < to and from < other_to


## A tap on the area is the host's tap, claimed here so it is delivered once
## (mobile R1), and delivered exactly as the engine delivers it: on **release**,
## which is `BaseButton`'s own default action mode, and as `toggled` **and**
## `pressed` together on a toggle. A flip alone is what a segmented control cannot
## hear — `UiKit.segment` reads `pressed`, so a segment answering only `toggled`
## is a dead control. `tests/unit/test_touch_press.gd` drives every wiring kind
## through a real viewport for that reason.
##
## Which event class arrives is the engine's: a finger reaches this as an emulated
## mouse press, the default `emulate_mouse_from_touch` no project setting turns
## off.
func _gui_input(event: InputEvent) -> void:
	var host := get_parent() as BaseButton
	if host == null or host.disabled:
		return
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if click.pressed:
		_armed = true
		return
	# Released off the area after pressing on it — a cancelled tap, as it is on any
	# other button.
	var inside := Rect2(Vector2.ZERO, size).has_point(click.position)
	if not _armed or not inside:
		_armed = false
		return
	_armed = false
	if host.toggle_mode:
		host.button_pressed = not host.button_pressed
	host.pressed.emit()


func _fit() -> void:
	var host := get_parent() as Control
	# The fit is deferred, and a menu row picked with a finger is freed inside the
	# frame that placed it — so by the time this runs the area can be off the tree
	# with its host still attached to it, and there is then nothing to measure
	# against (found by MB3's driven dock scenario, which picks several rows).
	if host == null or not is_inside_tree():
		return
	var seat := host.get_global_rect()
	var screen := get_viewport().get_visible_rect()
	var rect := TouchTarget.inflation(seat, _blockers(host), _minimum, screen)
	offset_left = rect.position.x - seat.position.x
	offset_top = rect.position.y - seat.position.y
	offset_right = rect.end.x - seat.end.x
	offset_bottom = rect.end.y - seat.end.y


## Everything laid out beside the host, in canvas coordinates: its siblings, and
## its ancestors' siblings, up to the first ancestor that is not a Control — a
## CanvasLayer or the window, which is where this control's own plane ends. The
## row a control sits in is only half the answer: the seat strip's rows are four
## sibling containers, so a segment that measured its own row alone would grow
## straight over the row above it and swallow that row's taps.
func _blockers(host: Control) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var node := host as Node
	while node != null:
		var parent := node.get_parent() as Control
		if parent == null:
			break
		for child in parent.get_children():
			var control := child as Control
			if control != null and control != node and control.visible:
				rects.append(control.get_global_rect())
		node = parent
	return rects
