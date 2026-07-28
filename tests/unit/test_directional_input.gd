extends GutTest
## One step per directional gesture (COM-39). Node-free and pure, like
## TransitionInput, so it is testable at all.
##
## Worth its own suite because no pad exists in CI and the difference it holds is
## invisible to a single injected sample: Godot emits an InputEventJoypadMotion
## per axis sample, every one of them above the deadzone reports pressed, and the
## board cursor and both menus act on a *true* here. Un-latched, one push of the
## stick would walk as far as its ramp had samples.

const UP_AXIS := JOY_AXIS_LEFT_Y
const LEFT_AXIS := JOY_AXIS_LEFT_X

var _dirs: DirectionalInput


func before_each() -> void:
	_dirs = DirectionalInput.new()


func _motion(axis: JoyAxis, value: float, device: int = 0) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event


func _button(index: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	return event


func _key(keycode: Key, pressed: bool, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	return event


## The whole point: pushing the stick to its stop is one gesture, however many
## samples the ramp takes to get there.
func test_an_axis_ramp_is_one_step() -> void:
	var steps := 0
	for value in [-0.2, -0.4, -0.6, -0.8, -1.0, -1.0]:
		if _dirs.pressed(_motion(UP_AXIS, value), &"cursor_up"):
			steps += 1
	assert_eq(steps, 1)


## Samples under the action's deadzone are not a gesture at all — stick drift
## must never move the cursor.
func test_a_sample_inside_the_deadzone_is_no_step() -> void:
	assert_false(_dirs.pressed(_motion(UP_AXIS, -0.4), &"cursor_up"))


func test_centring_the_stick_arms_the_next_gesture() -> void:
	assert_true(_dirs.pressed(_motion(UP_AXIS, -1.0), &"cursor_up"))
	assert_false(_dirs.pressed(_motion(UP_AXIS, -1.0), &"cursor_up"))
	assert_false(_dirs.pressed(_motion(UP_AXIS, 0.0), &"cursor_up"))
	assert_true(_dirs.pressed(_motion(UP_AXIS, -1.0), &"cursor_up"))


## Swinging to the other end of the same axis is a fresh gesture each way, and
## crossing back must not be swallowed by the latch the first push left.
func test_opposite_directions_each_step_once() -> void:
	assert_eq(
		_dirs.step(_motion(LEFT_AXIS, -1.0), [&"cursor_left", &"cursor_right"]), &"cursor_left"
	)
	assert_eq(
		_dirs.step(_motion(LEFT_AXIS, 1.0), [&"cursor_left", &"cursor_right"]), &"cursor_right"
	)
	assert_eq(
		_dirs.step(_motion(LEFT_AXIS, -1.0), [&"cursor_left", &"cursor_right"]), &"cursor_left"
	)


## The direction set is answered whole, so a stick that jumps from one axis's
## stop to another's does not leave the abandoned direction latched.
func test_a_resolved_set_clears_the_direction_left_behind() -> void:
	var actions := DirectionalInput.new()
	var all: Array = [&"cursor_up", &"cursor_down", &"cursor_left", &"cursor_right"]
	assert_eq(actions.step(_motion(UP_AXIS, 1.0), all), &"cursor_down")
	assert_eq(actions.step(_motion(LEFT_AXIS, -1.0), all), &"cursor_left")
	assert_eq(actions.step(_motion(UP_AXIS, 0.0), all), &"")
	assert_eq(actions.step(_motion(UP_AXIS, 1.0), all), &"cursor_down")


## Latches are per device, so a second pad — or any device id the OS hands out —
## cannot spend the first one's gesture.
func test_each_device_latches_on_its_own() -> void:
	assert_true(_dirs.pressed(_motion(UP_AXIS, -1.0, 7), &"cursor_up"))
	assert_true(_dirs.pressed(_motion(UP_AXIS, -1.0, 3), &"cursor_up"))
	assert_false(_dirs.pressed(_motion(UP_AXIS, -1.0, 7), &"cursor_up"))
	assert_false(_dirs.pressed(_motion(UP_AXIS, -1.0, 3), &"cursor_up"))


## The d-pad is digital: a press is one step and the release that follows is not
## a second one.
func test_a_dpad_press_is_one_step_and_its_release_is_none() -> void:
	assert_true(_dirs.pressed(_button(JOY_BUTTON_DPAD_UP, true), &"cursor_up"))
	assert_false(_dirs.pressed(_button(JOY_BUTTON_DPAD_UP, false), &"cursor_up"))


## A held arrow key repeats through the OS, and that repeat is how the keyboard
## has always walked the cursor — the latch must not take it away.
func test_a_held_arrow_key_still_repeats() -> void:
	assert_true(_dirs.pressed(_key(KEY_UP, true), &"cursor_up"))
	assert_true(_dirs.pressed(_key(KEY_UP, true, true), &"cursor_up"))
	assert_true(_dirs.pressed(_key(KEY_UP, true, true), &"cursor_up"))
	assert_false(_dirs.pressed(_key(KEY_UP, false), &"cursor_up"))


func test_another_direction_key_is_not_this_one() -> void:
	assert_false(_dirs.pressed(_key(KEY_DOWN, true), &"cursor_up"))


## The menus navigate on Godot's built-in pair as well; both must latch.
func test_the_builtin_ui_actions_latch_too() -> void:
	assert_true(_dirs.pressed(_motion(UP_AXIS, 1.0), &"ui_down"))
	assert_false(_dirs.pressed(_motion(UP_AXIS, 1.0), &"ui_down"))


## An axis this direction is not mapped to is simply not its business, and must
## not clear the latch it is holding.
func test_an_unrelated_axis_leaves_the_latch_alone() -> void:
	assert_true(_dirs.pressed(_motion(UP_AXIS, -1.0), &"cursor_up"))
	assert_false(_dirs.pressed(_motion(LEFT_AXIS, 0.0), &"cursor_up"))
	assert_false(_dirs.pressed(_motion(UP_AXIS, -1.0), &"cursor_up"))


func test_no_direction_names_nothing() -> void:
	assert_eq(_dirs.step(_motion(UP_AXIS, 0.0), [&"cursor_up", &"cursor_down"]), &"")
