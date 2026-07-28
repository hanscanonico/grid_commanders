class_name TransitionInput
extends RefCounted
## One presentation-only answer for "did the player press something?" at a
## transition boundary. Banners use it to skip their beat; the outcome lockup
## uses the same answer to swallow buffered input before it arms an action.


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
