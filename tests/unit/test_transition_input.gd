extends GutTest
## The one answer to "did the player press something?" at a state boundary
## (COM-15). Node-free and pure, like CmdArgs, so it is testable at all.
##
## Worth its own suite because both callers act on a *true* here — a banner
## retires, the outcome lockup swallows the press — so an event class it answers
## wrong for is either a beat that cannot be skipped or one that skips itself.
## The keyboard half is the only branch the smoke scenarios drive; the mouse,
## controller, touch and echo branches have no other check.


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


## One finger is one press, and that is the whole of the touch contract. With
## `emulate_mouse_from_touch` on — the shipped setting — the engine delivers a
## tap as *both* a screen touch and a synthesised click, and both reach
## `_unhandled_input`, so the finger door stays shut and the click answers. These
## run under the shipped setting, which is the configuration the game ships in.
func test_the_finger_door_is_shut_while_the_engine_emulates_a_click() -> void:
	assert_true(TransitionInput._mouse_emulated, "the game ships with mouse emulation on")
	var event := InputEventScreenTouch.new()
	event.pressed = true
	assert_false(TransitionInput.is_touch_press(event))
	assert_false(TransitionInput.is_press(event), "the emulated click is the press")
	assert_false(TransitionInput.is_confirm(event))


## With emulation off there is no click to answer, so the finger speaks for
## itself — which is the whole point of naming the class rather than leaning on
## an engine default.
func test_the_finger_speaks_for_itself_with_emulation_off() -> void:
	var was: bool = TransitionInput._mouse_emulated
	TransitionInput._mouse_emulated = false
	var event := InputEventScreenTouch.new()
	event.pressed = true
	assert_true(TransitionInput.is_touch_press(event))
	assert_true(TransitionInput.is_press(event))
	assert_true(TransitionInput.is_confirm(event))
	event.pressed = false
	assert_false(TransitionInput.is_press(event), "a lifted finger is not a press")
	assert_false(TransitionInput.is_confirm(event))
	TransitionInput._mouse_emulated = was


## A finger sliding across a banner is not a press, for the reason a moving
## mouse is not one — in either configuration.
func test_a_screen_drag_is_never_a_press() -> void:
	var was: bool = TransitionInput._mouse_emulated
	for emulated: bool in [true, false]:
		TransitionInput._mouse_emulated = emulated
		assert_false(TransitionInput.is_press(InputEventScreenDrag.new()))
		assert_false(TransitionInput.is_confirm(InputEventScreenDrag.new()))
	TransitionInput._mouse_emulated = was


## Moving the mouse over a banner must not retire it, and neither may a stick
## resting off centre: only a deliberate press counts.
func test_pointer_motion_is_not_a_press() -> void:
	assert_false(TransitionInput.is_press(InputEventMouseMotion.new()))


func test_a_stick_axis_is_not_a_press() -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = 1.0
	assert_false(TransitionInput.is_press(event))


## `is_confirm` is the narrower question the handoff and the computer turn's
## refusal both ask. It moved here out of Battle because two boundaries answering
## different presses is the drift this class exists to prevent — and here it is
## checked without booting the scene.
func test_the_confirm_action_is_a_confirm() -> void:
	var event := InputEventAction.new()
	event.action = &"confirm"
	event.pressed = true
	assert_true(TransitionInput.is_confirm(event))


func test_a_left_click_is_a_confirm_and_its_release_is_not() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	assert_true(TransitionInput.is_confirm(event))
	event.pressed = false
	assert_false(TransitionInput.is_confirm(event))


func test_a_right_click_is_not_a_confirm() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	assert_false(TransitionInput.is_confirm(event))
	assert_true(TransitionInput.is_press(event), "though it is still a press")
