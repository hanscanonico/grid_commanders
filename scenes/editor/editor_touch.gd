class_name EditorTouch
extends RefCounted
## A hand on the draft: one finger paints where it lands, one finger that travels
## walks the board under it, and two fingers change the zoom (mobile plan MB6).
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

var _board: EditorBoard
## What a tap does, which is the editor's business and not this class's — the same
## call a press of Enter makes.
var _paint: Callable
## Where a pan leaves the cursor. The editor's, not this class's, because moving
## the cursor is also what the status line under the board reports.
var _look: Callable
var _touch := TouchGestures.new()
## The rung the pinch in progress began on, and -1 between pinches, so a spread
## and its exact undo land back where the hand opened.
var _pinch_from := -1


func _init(board: EditorBoard, paint: Callable, look: Callable) -> void:
	_board = board
	_paint = paint
	_look = look


## True when the event was the hand's and the board's input stops there.
func handle(event: InputEvent) -> bool:
	var kind := _touch.feed(event, _board.tile_px(), TouchGestures.gain_for(_board.rungs()))
	if kind == TouchGestures.Kind.NONE:
		return event is InputEventMouse  # a finger's echo, and the finger already spoke
	if kind == TouchGestures.Kind.PINCH:
		if _pinch_from < 0:
			_pinch_from = _board.rung_index()
		_board.settle_at(_pinch_from + _touch.pinch_rungs)
		return true
	_pinch_from = -1
	if kind == TouchGestures.Kind.TAP:
		_paint.call(_board.cell_at(_touch.tap_at))
	elif kind == TouchGestures.Kind.PAN:
		_walk(_touch.pan_cells)
	return true


## A pan walks the cursor, because the cursor is what the board scrolls to keep in
## frame — a pan that wrote the scroll itself would be a second opinion about
## where the board is (`EditorBoard.scroll_axis`).
func _walk(cells: Vector2i) -> void:
	var edge := _board.board_size() - Vector2i.ONE
	_look.call((_board.cursor_cell + cells).clamp(Vector2i.ZERO, edge))
