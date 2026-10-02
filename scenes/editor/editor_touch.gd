class_name EditorTouch
extends RefCounted
## A hand on the draft: one finger paints where it lands, one finger that travels
## walks the board under it, and two fingers change the zoom (mobile plan MB6).
## With `drag_paints` on, the travelling finger lays the brush along its way
## instead, so a run of cells is one stroke rather than a tap per cell.
##
## `BoardPointer`'s shape, for the board the editor paints rather than the board a
## match is played on, and for the same reason: `emulate_mouse_from_touch` is on,
## so a tap arrives as a touch *and* as a synthesised click, and a click acts the
## instant the finger lands — before anyone can know whether that finger is going
## to stay still. On a touch build the mouse door is therefore shut and the
## finger's is open, which is what makes "a drag across the board pans it rather
## than painting a stripe" true by construction rather than by a threshold race.
##
## The gestures themselves are `TouchGestures`', asked rather than restated: whole
## cells and whole rungs, so a pan and a pinch here rest exactly where they rest in
## a match.

## Whether a one-finger drag paints rather than walks the board. A pinch still
## zooms either way, so the board stays reachable while it is on.
var drag_paints := false

var _board: EditorBoard
## Lays the brush on one cell, and files the stroke in hand: the editor's
## business and not this class's. A tap is one of each, as a press of Enter is.
var _lay: Callable
var _end_stroke: Callable
## Where a pan leaves the cursor. The editor's, not this class's, because moving
## the cursor is also what the status line under the board reports.
var _look: Callable
var _touch := TouchGestures.new()
## The rung the pinch in progress began on, and -1 between pinches, so a spread
## and its exact undo land back where the hand opened.
var _pinch_from := -1
## Fingers on the glass, so a stroke starts only under a hand of one.
var _down := 0
## Where the lone finger landed, and the last cell its stroke laid.
var _stroke_from := Vector2i.ZERO
var _stroking := false
## True while the lone finger may still turn into a stroke: a second finger makes
## the hand a pinch, and the pinch's leftover finger is not a stroke either.
var _stroke_armed := false


func _init(board: EditorBoard, lay: Callable, end_stroke: Callable, look: Callable) -> void:
	_board = board
	_lay = lay
	_end_stroke = end_stroke
	_look = look


## True when the event was the hand's and the board's input stops there.
func handle(event: InputEvent) -> bool:
	var kind := _touch.feed(event, _board.tile_px(), TouchGestures.gain_for(_board.rungs()))
	if kind == TouchGestures.Kind.NONE:
		return event is InputEventMouse  # a finger's echo, and the finger already spoke
	_count_fingers(event)
	if kind == TouchGestures.Kind.PINCH:
		_finish_stroke()
		if _pinch_from < 0:
			_pinch_from = _board.rung_index()
		_board.settle_at(_pinch_from + _touch.pinch_rungs)
		return true
	_pinch_from = -1
	if kind == TouchGestures.Kind.TAP:
		_lay.call(_board.cell_at(_touch.tap_at))
		_end_stroke.call()
	elif drag_paints and event is InputEventScreenDrag:
		_stroke(kind, _board.cell_at((event as InputEventScreenDrag).position))
	elif kind == TouchGestures.Kind.PAN:
		_walk(_touch.pan_cells)
	if _down == 0:
		_finish_stroke()
	return true


func _count_fingers(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	_down = _down + 1 if touch.pressed else maxi(_down - 1, 0)
	_stroke_armed = touch.pressed and _down == 1
	if _stroke_armed:
		_stroke_from = _board.cell_at(touch.position)


## A stroke begins where the finger landed once the drag has left the tap's slop
## (the first PAN), so a tap and the first finger of a pinch paint nothing extra.
func _stroke(kind: TouchGestures.Kind, cell: Vector2i) -> void:
	if not _stroking:
		if not _stroke_armed or kind != TouchGestures.Kind.PAN:
			return
		_stroking = true
		_lay.call(_stroke_from)
	_lay_to(cell)


## Every cell from the last one laid to `cell`, so a quick finger that skips a
## cell between two events still leaves an unbroken run.
func _lay_to(cell: Vector2i) -> void:
	var steps := maxi(absi(cell.x - _stroke_from.x), absi(cell.y - _stroke_from.y))
	for i in range(1, steps + 1):
		_lay.call(Vector2i(Vector2(_stroke_from).lerp(Vector2(cell), float(i) / steps).round()))
	_stroke_from = cell


func _finish_stroke() -> void:
	_stroke_armed = false
	if not _stroking:
		return
	_stroking = false
	_end_stroke.call()


## A pan walks the cursor, because the cursor is what the board scrolls to keep in
## frame — a pan that wrote the scroll itself would be a second opinion about
## where the board is (`EditorBoard.scroll_axis`).
func _walk(cells: Vector2i) -> void:
	var edge := _board.board_size() - Vector2i.ONE
	_look.call((_board.cursor_cell + cells).clamp(Vector2i.ZERO, edge))
