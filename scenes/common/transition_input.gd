class_name TransitionInput
extends RefCounted
## One presentation-only answer for "did the player press something?" at a
## transition boundary. Banners use it to skip their beat; the outcome lockup
## uses the same answer to swallow buffered input before it arms an action.


## The narrower question the two states that swallow play still ask: the confirm
## action, or a left click. Here rather than in `Battle` so the handoff's "I'm
## ready" and the computer turn's refusal can never answer different presses.
static func is_confirm(event: InputEvent) -> bool:
	if event.is_action_pressed(&"confirm"):
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
	var action := event as InputEventAction
	return action != null and action.pressed
