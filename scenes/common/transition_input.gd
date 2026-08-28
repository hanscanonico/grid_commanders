class_name TransitionInput
extends RefCounted
## One presentation-only answer for "did the player press something?" at a
## transition boundary. Banners use it to skip their beat; the outcome lockup
## uses the same answer to swallow buffered input before it arms an action.
##
## A finger has two doors here and **exactly one of them is ever open**, because
## one finger must be one press. Godot's `emulate_mouse_from_touch` is on — the
## engine's default, which this game keeps — so a tap arrives as *both* an
## `InputEventScreenTouch` and a synthesised left click, and both reach
## `_unhandled_input`: marking one handled does not suppress the other (measured
## on 4.7.1). Answering true to both would skip two banners, advance two
## interlude lines and refuse a computer turn twice, for one tap. So the touch
## class is named — which is what makes the convention a statement rather than a
## silent engine default — and it speaks only when the emulation that would
## otherwise speak for it is switched off.


## True for a press of the one finger door, which is shut while the engine is
## emulating a click for the same finger. The engine is asked whether it is
## emulating, rather than the project setting it starts from, because
## `Input.set_emulate_mouse_from_touch` can move it at runtime and a second
## opinion here would answer for a click nobody is sending.
static func is_touch_press(event: InputEvent) -> bool:
	var touch := event as InputEventScreenTouch
	return touch != null and touch.pressed and not Input.is_emulating_mouse_from_touch()


## The narrower question the two states that swallow play still ask: the confirm
## action, a left click, or a finger. Here rather than in `Battle` so the
## handoff's "I'm ready" and the computer turn's refusal can never answer
## different presses.
static func is_confirm(event: InputEvent) -> bool:
	if event.is_action_pressed(&"confirm") or is_touch_press(event):
		return true
	var button := event as InputEventMouseButton
	return button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed


static func is_press(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null:
		return key.pressed and not key.echo
	var mouse := event as InputEventMouseButton
	if mouse != null:
		return mouse.pressed
	var button := event as InputEventJoypadButton
	if button != null:
		return button.pressed
	if is_touch_press(event):
		return true
	var action := event as InputEventAction
	return action != null and action.pressed


## Whether a cancel press dismisses this page: the visible guard, the test, and
## the receipt, in the one place the convention is stated. A page's
## `_unhandled_input` is then the two lines that say what dismissing it does —
## re-asserting the shape per page is how one of them ends up without the
## receipt and double-fires on a touch build.
static func dismissed_by_cancel(page: Control, event: InputEvent) -> bool:
	return _dismissed(page, event.is_action_pressed(&"cancel"))


## The same, for a page any press retires rather than cancel alone.
static func dismissed_by_press(page: Control, event: InputEvent) -> bool:
	return _dismissed(page, is_press(event))


static func _dismissed(page: Control, pressed: bool) -> bool:
	if not page.visible or not pressed:
		return false
	page.get_viewport().set_input_as_handled()
	return true
