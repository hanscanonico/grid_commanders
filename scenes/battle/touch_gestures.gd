class_name TouchGestures
extends RefCounted
## What a hand on the board asked for: one finger drags, two fingers pinch, and a
## press that went nowhere is a tap (mobile plan MB6, D3).
##
## A pure state machine over the two touch classes — it holds where the fingers
## are and answers in whole cells and whole rungs, knowing nothing of a Battle, a
## camera or a map. The caller hands it the two scales the board is drawn at, so
## `tests/unit/test_touch_gestures.gd` feeds it real events with no scene at all,
## the way `PathArrow.segments` and `BattleZoom.floor_for` are checked.
##
## Whole cells and whole rungs are the answer rather than a rounding of it. The
## board is sampled with nearest filtering, so a pan resting between two world
## pixels and a zoom resting between two rungs are the same crawling-edge defect
## the integer ladder and `position_smoothing`'s removal already exist to forbid;
## a gesture reporting a float would be that defect arriving by another door.

## What the last `feed` made of the hand. NONE is "not a touch event at all", so
## the caller keeps its own answer for a mouse; HELD is a touch event that has not
## asked for anything yet.
enum Kind { NONE, HELD, TAP, PAN, PINCH }

## How far a finger may wander and still be placing the cursor rather than walking
## the board with it. A tap that has moved is what a drag is made of, so this is
## the whole difference between the two.
const TAP_SLOP_PX := 10.0

## The gain a ladder with no room to move falls back on. Never read on a shipped
## board — every one of them offers at least two rungs — and here so that a degenerate
## ladder answers something finite rather than dividing by a zero span.
const FALLBACK_GAIN := 2.0

## Where the finger let go, read for `Kind.TAP` and stale otherwise.
var tap_at := Vector2.ZERO
## How many whole cells the *cursor* walks, read for `Kind.PAN`. The board follows
## the finger, so this is the opposite of the way the finger went.
var pan_cells := Vector2i.ZERO
## How many rungs out from the one the pinch began on, read for `Kind.PINCH`.
## Positive is further in, the direction spreading two fingers asks for.
var pinch_rungs := 0

var _fingers: Dictionary[int, Vector2] = {}
## Sub-cell drag the board has not been paid for yet, so a slow finger arrives a
## cell at a time rather than never.
var _rest := Vector2.ZERO
var _travel := 0.0
var _tappable := false
## The span the pinch is measured against: re-taken whenever the hand changes.
var _span := 0.0


## Feeds one event and says what it made of it. `cell_px` is the board's scale (a
## cell's width on screen) and `gain` the ladder's (`gain_for`) — both facts about
## how the board is drawn right now, which is why they arrive with the event
## rather than being held here.
func feed(event: InputEvent, cell_px: float, gain: float) -> Kind:
	var touch := event as InputEventScreenTouch
	if touch != null:
		return _touched(touch)
	var drag := event as InputEventScreenDrag
	if drag != null:
		return _dragged(drag, cell_px, gain)
	return Kind.NONE


## The span ratio one rung costs, per ladder rather than one constant for the
## game: Bulwark's six rungs span 8.8x and a board small enough to open above the
## default spans 2.5x over four, so a single gain would make one of them a hair
## trigger and put the other out of reach inside a screen's width.
static func gain_for(rungs: PackedFloat64Array) -> float:
	if rungs.size() < 2 or rungs[0] <= 0.0:
		return FALLBACK_GAIN
	return pow(rungs[rungs.size() - 1] / rungs[0], 1.0 / float(rungs.size() - 1))


## How many rungs a span that has grown by `ratio` has asked for.
static func rung_step(ratio: float, gain: float) -> int:
	if ratio <= 0.0 or gain <= 1.0:
		return 0
	return roundi(log(ratio) / log(gain))


## The whole cells inside a pixel travel, truncated toward zero — the remainder is
## the caller's to keep.
static func cells_in(px: Vector2, cell_px: float) -> Vector2i:
	if cell_px <= 0.0:
		return Vector2i.ZERO
	return Vector2i(px / cell_px)


## A press for a finger already down is a release that never arrived: the board
## swallowed it in a state that refuses play. The hand is forgotten rather than
## read as the second finger of a pinch nobody made.
func _touched(touch: InputEventScreenTouch) -> Kind:
	if touch.pressed:
		if _fingers.has(touch.index):
			_fingers.clear()
		_fingers[touch.index] = touch.position
		_tappable = _fingers.size() == 1
		_travel = 0.0
		_anchor()
		return Kind.HELD
	var tapped := _tappable and _fingers.size() == 1
	_fingers.erase(touch.index)
	_tappable = false
	_anchor()
	if not tapped:
		return Kind.HELD
	tap_at = touch.position
	return Kind.TAP


func _dragged(drag: InputEventScreenDrag, cell_px: float, gain: float) -> Kind:
	if not _fingers.has(drag.index):
		return Kind.HELD  # a finger whose press the board never saw
	_fingers[drag.index] = drag.position
	if _fingers.size() > 1:
		pinch_rungs = 0 if _span <= 0.0 else rung_step(_span_now() / _span, gain)
		return Kind.PINCH
	_travel += drag.relative.length()
	_tappable = _tappable and _travel <= TAP_SLOP_PX
	_rest += drag.relative
	var walked := cells_in(_rest, cell_px)
	if walked == Vector2i.ZERO:
		return Kind.HELD
	_rest -= Vector2(walked) * cell_px
	pan_cells = -walked
	return Kind.PAN


## Re-anchors the gesture to the hand as it now stands. A finger arriving or
## leaving changes both measurements at once, and carrying either across that
## moment would jerk the board by the difference.
func _anchor() -> void:
	_rest = Vector2.ZERO
	_span = _span_now()


func _span_now() -> float:
	if _fingers.size() < 2:
		return 0.0
	var held: Array[Vector2] = _fingers.values()
	return held[0].distance_to(held[1])
