class_name BoardPointer
extends RefCounted
## Where a pointing device lands on the board: a mouse on a desktop build, a hand
## on a touch one (mobile plan MB6). Split out of `Battle._unhandled_input`, which
## owned the mouse half and had no room left for the other.
##
## **One finger, one receipt.** `emulate_mouse_from_touch` is on, so a tap arrives
## as an `InputEventScreenTouch` *and* a synthesised click, and marking one handled
## does not suppress the other (measured on 4.7.1; `TransitionInput` says the same
## for its own boundary). A click acts the instant the finger lands, which is
## before anyone can know whether that finger is going to stay still — so on a
## touch build the mouse door is shut and the finger's is open: a press confirms
## nothing, and the *release* confirms only where the finger never went anywhere.
## That is what makes "a drag beginning on a unit never issues a move" true by
## construction rather than by a threshold race. The pinch reaches `BattleZoom`
## directly for the same reason it is not a dispatched `zoom_in`: a gesture that
## posted actions would be a second sender beside the dock's chips.
##
## The cost is deliberate and small: `--mobile` on a desktop machine poses the
## touch chrome, and the board there answers pushed touch events rather than the
## mouse.

var _battle: Battle
var _zoom: BattleZoom
## Null on a desktop build, where D5 says the touch side is never constructed at
## all rather than built and skipped.
var _touch: TouchGestures
## The rung the pinch in progress began on, and -1 between pinches. A pinch is
## measured from where it started so that a spread and its exact undo land back on
## the rung the hand opened on.
var _pinch_from := -1


func _init(battle: Battle, zoom: BattleZoom) -> void:
	_battle = battle
	_zoom = zoom
	_touch = TouchGestures.new() if MobileProfile.active() else null


## True when the event was the pointer's and the interaction flow stops there.
func handle(event: InputEvent) -> bool:
	if _touch == null:
		return _moused(event)
	var kind := _touch.feed(event, _cell_px(), TouchGestures.gain_for(_zoom.rungs()))
	if kind == TouchGestures.Kind.NONE:
		return event is InputEventMouse  # a finger's echo, and the finger already spoke
	if kind == TouchGestures.Kind.PINCH:
		_settle_pinch(_touch.pinch_rungs)
		return true
	_pinch_from = -1
	if kind == TouchGestures.Kind.TAP:
		_confirm(_cell_at(_world(_touch.tap_at)))
	elif kind == TouchGestures.Kind.PAN:
		_walk(_touch.pan_cells)
	return true


## Where a cell sits on the screen: the inverse of the reading every press is
## turned into a cell through, so the driven touch proof aims a finger at a cell
## the way a player does rather than spelling the transform a second time.
func screen_of(cell: Vector2i) -> Vector2:
	return _battle.get_canvas_transform() * BattleView.cell_center(cell)


func _moused(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var cell := _cell_at(_battle.get_global_mouse_position())
		if _battle.map.in_bounds(cell) and cell != _battle.cursor_cell:
			_battle.set_cursor_cell(cell)
		return true
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
		return false
	_confirm(_cell_at(_battle.get_global_mouse_position()))
	return true


func _confirm(cell: Vector2i) -> void:
	if not _battle.map.in_bounds(cell):
		return
	if cell != _battle.cursor_cell:
		_battle.set_cursor_cell(cell)
	_battle.confirm_at(_battle.cursor_cell)


## A pan walks the cursor, because the cursor is what the camera rides:
## `BattleView.move_cursor_to` parks the camera on the cell the cursor stands on,
## so a pan that wrote `camera.position` itself would be a second opinion about
## where the board is — and whole cells rest on whole world pixels for free.
func _walk(cells: Vector2i) -> void:
	var edge := _battle.map.size() - Vector2i.ONE
	var next := (_battle.cursor_cell + cells).clamp(Vector2i.ZERO, edge)
	if next != _battle.cursor_cell:
		_battle.set_cursor_cell(next)


## The ladder settles the pinch, never the gesture: `settle_at` is the one way
## onto a rung, so the board can no more rest between two of them under a finger
## than under a key.
func _settle_pinch(rungs: int) -> void:
	if _pinch_from < 0:
		_pinch_from = _zoom.rung_index()
	_zoom.settle_at(_pinch_from + rungs)


## A cell's width on screen, which is what a finger's travel is measured in.
func _cell_px() -> float:
	return float(BattleView.TILE) * _battle.view.camera.zoom.x


## A screen point in board coordinates, in the transform
## `CanvasItem.get_global_mouse_position` is the mouse's own reading of — the same
## conversion with a finger's position put in, so a tap and a click can never land
## on different cells.
func _world(screen: Vector2) -> Vector2:
	return _battle.get_canvas_transform().affine_inverse() * screen


func _cell_at(world: Vector2) -> Vector2i:
	return Vector2i((world / BattleView.TILE).floor())
