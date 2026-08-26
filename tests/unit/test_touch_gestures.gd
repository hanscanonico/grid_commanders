extends GutTest
## The hand on the board, with no board under it (mobile plan MB6). TouchGestures
## is a pure state machine over the two touch classes, so every rule it carries —
## a drag is not a tap, two fingers are not a pan, a pinch is counted in whole
## rungs — is checked here by feeding it real events, the way `PathArrow.segments`
## and `BattleZoom.floor_for` are checked without a scene.

## One rung of the ladder in play, in pixels: the scale a real board is drawn at
## when the default rung is up.
const CELL := 32.0

## Bulwark's ladder — the widest in the game, and the board MB6 exists for. A var
## rather than a const because a packed array is not a constant expression.
var _bulwark := PackedFloat64Array([0.568, 1.0, 2.0, 3.0, 4.0, 5.0])
var _hand: TouchGestures
var _gain := 0.0


func before_each() -> void:
	_hand = TouchGestures.new()
	_gain = TouchGestures.gain_for(_bulwark)


func _press(index: int, at: Vector2) -> TouchGestures.Kind:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.pressed = true
	touch.position = at
	return _feed(touch)


func _release(index: int, at: Vector2) -> TouchGestures.Kind:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.pressed = false
	touch.position = at
	return _feed(touch)


func _drag(index: int, to: Vector2, by: Vector2) -> TouchGestures.Kind:
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = to
	drag.relative = by
	return _feed(drag)


func _feed(event: InputEvent) -> TouchGestures.Kind:
	return _hand.feed(event, CELL, _gain)


func test_a_mouse_is_not_the_hands() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_eq(_feed(click), TouchGestures.Kind.NONE, "a mouse event is the caller's own answer")


func test_a_press_that_goes_nowhere_is_a_tap() -> void:
	assert_eq(_press(0, Vector2(100, 80)), TouchGestures.Kind.HELD, "a press alone asks nothing")
	assert_eq(_release(0, Vector2(100, 80)), TouchGestures.Kind.TAP)
	assert_eq(_hand.tap_at, Vector2(100, 80), "the tap lands where the finger let go")


func test_a_finger_inside_the_slop_is_still_a_tap() -> void:
	_press(0, Vector2(100, 80))
	var wobble := Vector2(TouchGestures.TAP_SLOP_PX - 2.0, 0.0)
	assert_eq(_drag(0, Vector2(100, 80) + wobble, wobble), TouchGestures.Kind.HELD)
	assert_eq(_release(0, Vector2(100, 80) + wobble), TouchGestures.Kind.TAP)


## The whole of R1's second form: a drag beginning on a unit must not become a
## move, and the recogniser is where that is settled — the release says HELD, so
## nothing ever reaches `confirm_at`.
func test_a_drag_is_never_a_tap() -> void:
	_press(0, Vector2(100, 80))
	assert_eq(_drag(0, Vector2(100 + CELL, 80), Vector2(CELL, 0)), TouchGestures.Kind.PAN)
	assert_eq(
		_release(0, Vector2(100 + CELL, 80)), TouchGestures.Kind.HELD, "a drag confirms nothing"
	)


func test_a_pan_walks_the_cursor_against_the_finger() -> void:
	_press(0, Vector2(200, 200))
	assert_eq(
		_drag(0, Vector2(200 - 2.0 * CELL, 200), Vector2(-2.0 * CELL, 0.0)), TouchGestures.Kind.PAN
	)
	assert_eq(
		_hand.pan_cells, Vector2i(2, 0), "dragging the board left brings the ground east into view"
	)


## A finger crossing a cell boundary in two goes has to arrive, or a slow drag
## moves nothing at all.
func test_a_slow_drag_arrives_a_cell_at_a_time() -> void:
	_press(0, Vector2(200, 200))
	assert_eq(
		_drag(0, Vector2(200, 180), Vector2(0, -20)), TouchGestures.Kind.HELD, "not a cell yet"
	)
	assert_eq(_drag(0, Vector2(200, 160), Vector2(0, -20)), TouchGestures.Kind.PAN)
	assert_eq(_hand.pan_cells, Vector2i(0, 1), "the remainder was kept rather than dropped")


func test_two_fingers_pinch_rather_than_pan() -> void:
	_press(0, Vector2(100, 100))
	_press(1, Vector2(200, 100))
	assert_eq(
		_drag(1, Vector2(100.0 + 100.0 * _gain, 100), Vector2(1, 0)), TouchGestures.Kind.PINCH
	)
	assert_eq(_hand.pinch_rungs, 1, "one ladder gain is one rung in")
	assert_eq(
		_drag(1, Vector2(100.0 + 100.0 / _gain, 100), Vector2(-1, 0)), TouchGestures.Kind.PINCH
	)
	assert_eq(_hand.pinch_rungs, -1, "and pinching back past the start is one rung out")


func test_a_pinch_is_measured_from_where_it_opened() -> void:
	_press(0, Vector2(100, 100))
	_press(1, Vector2(200, 100))
	_drag(1, Vector2(300, 100), Vector2(100, 0))
	var spread := _hand.pinch_rungs
	_drag(1, Vector2(200, 100), Vector2(-100, 0))
	assert_gt(spread, 0, "spreading asks for a rung in")
	assert_eq(_hand.pinch_rungs, 0, "and undoing it asks for the rung it opened on")


func test_a_second_finger_ends_the_tap() -> void:
	_press(0, Vector2(100, 100))
	_press(1, Vector2(200, 100))
	_release(1, Vector2(200, 100))
	assert_eq(_release(0, Vector2(100, 100)), TouchGestures.Kind.HELD, "a pinch never confirms")


## A press for a finger already down means the board swallowed the release in a
## state that refuses play. The hand starts again rather than reading the next tap
## as half of a pinch.
func test_a_swallowed_release_does_not_strand_a_finger() -> void:
	_press(0, Vector2(100, 100))
	assert_eq(_press(0, Vector2(140, 140)), TouchGestures.Kind.HELD)
	assert_eq(
		_release(0, Vector2(140, 140)), TouchGestures.Kind.TAP, "the fresh press is a fresh hand"
	)


func test_a_drag_with_no_press_behind_it_asks_nothing() -> void:
	assert_eq(_drag(0, Vector2(200, 200), Vector2(CELL, 0)), TouchGestures.Kind.HELD)


## Sensitivity is per ladder because the ladders differ by a factor of three in
## what they span; one gain would make one board a hair trigger and the other
## unreachable.
func test_the_gain_is_the_ladders_own_step() -> void:
	var small := PackedFloat64Array([2.03, 3.0, 4.0, 5.0])
	assert_gt(_gain, TouchGestures.gain_for(small), "a wider ladder costs more span per rung")
	assert_almost_eq(pow(_gain, _bulwark.size() - 1), _bulwark[5] / _bulwark[0], 0.001)
	assert_eq(TouchGestures.gain_for(PackedFloat64Array([1.0])), TouchGestures.FALLBACK_GAIN)


func test_a_rung_step_is_whole() -> void:
	assert_eq(TouchGestures.rung_step(1.0, _gain), 0, "a hand that has not moved asks for nothing")
	assert_eq(TouchGestures.rung_step(_gain * _gain, _gain), 2)
	assert_eq(TouchGestures.rung_step(0.0, _gain), 0, "a degenerate span asks for nothing")
	assert_eq(TouchGestures.rung_step(4.0, 1.0), 0)


func test_cells_are_counted_toward_zero() -> void:
	assert_eq(TouchGestures.cells_in(Vector2(CELL * 1.9, -CELL * 1.9), CELL), Vector2i(1, -1))
	assert_eq(TouchGestures.cells_in(Vector2(CELL, CELL), 0.0), Vector2i.ZERO)
