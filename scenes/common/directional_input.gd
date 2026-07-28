class_name DirectionalInput
extends RefCounted
## One presentation-only answer for "did that event ask for one step this way?"
## (COM-39). TransitionInput's sibling: a boundary convention held in one place
## rather than re-decided by every consumer of a direction action.
##
## A key and a d-pad button already are one press per gesture, so both pass
## straight through — echo included, which is what keeps the keyboard's held
## arrow repeating. An analog stick is not: Godot emits a fresh
## InputEventJoypadMotion for every axis sample, and each one reports pressed
## the moment the value clears the action's deadzone, so one push of the stick
## would walk a cursor as many cells as its ramp had samples. This latches that
## crossing per device and per action; the stick has to fall back under the
## deadzone — or swing to the other side of the same axis — before it may ask
## again.
##
## Every threshold and every direction comes from the InputMap: nothing here
## reads an axis value, so the action's own deadzone stays the only authority.
## State is per instance, so each modal owner latches its own gestures.

var _latched: Dictionary = {}


## Resolves a whole direction set at once and names the one that fired, or an
## empty name. Every action in the set is answered before this returns: a set
## resolved by short-circuiting would leave the direction the stick swung *away*
## from still latched, and swallow that direction's next gesture.
func step(event: InputEvent, actions: Array) -> StringName:
	var fired: StringName = &""
	for action: StringName in actions:
		if pressed(event, action) and fired.is_empty():
			fired = action
	return fired


## True exactly once per directional gesture. `action` is any input-map action;
## an event that maps to a different one is simply not this direction's.
func pressed(event: InputEvent, action: StringName) -> bool:
	var motion := event as InputEventJoypadMotion
	if motion == null:
		return event.is_action_pressed(action, true)
	if not event.is_action(action):
		return false
	var key := "%d/%s" % [motion.device, action]
	var now := event.is_action_pressed(action)
	var was: bool = _latched.get(key, false)
	_latched[key] = now
	return now and not was
