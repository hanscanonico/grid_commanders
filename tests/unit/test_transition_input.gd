extends GutTest
## The one answer to "did the player press something?" at a state boundary
## (COM-15). Node-free and pure, like CmdArgs, so it is testable at all.
##
## Worth its own suite because both callers act on a *true* here — a banner
## retires, the outcome lockup swallows the press — so an event class it answers
## wrong for is either a beat that cannot be skipped or one that skips itself.
## The keyboard half is the only branch the smoke scenarios drive; the mouse,
## controller and echo branches have no other check.


func test_a_key_press_is_a_press() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	assert_true(TransitionInput.is_press(event))


func test_a_key_release_is_not() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = false
	assert_false(TransitionInput.is_press(event))


## A held key repeats. Only the first of those may retire a beat, or a player
## resting on a key skips the banner and lands on whatever it revealed.
func test_an_auto_repeat_echo_is_not_a_press() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	event.echo = true
	assert_false(TransitionInput.is_press(event))


func test_a_mouse_button_press_is_a_press() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	assert_true(TransitionInput.is_press(event))


func test_a_mouse_button_release_is_not() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	assert_false(TransitionInput.is_press(event))


func test_a_controller_button_press_is_a_press() -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	assert_true(TransitionInput.is_press(event))


func test_a_controller_button_release_is_not() -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.pressed = false
	assert_false(TransitionInput.is_press(event))


func test_a_synthesised_action_press_is_a_press() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	assert_true(TransitionInput.is_press(event))


func test_a_synthesised_action_release_is_not() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = false
	assert_false(TransitionInput.is_press(event))


## Moving the mouse over a banner must not retire it, and neither may a stick
## resting off centre: only a deliberate press counts.
func test_pointer_motion_is_not_a_press() -> void:
	assert_false(TransitionInput.is_press(InputEventMouseMotion.new()))


func test_a_stick_axis_is_not_a_press() -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = 1.0
	assert_false(TransitionInput.is_press(event))
