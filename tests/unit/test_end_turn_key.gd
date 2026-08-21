extends GutTest
## End Turn's key, and the chip that prints it on the bottom bar's button.
##
## Both halves are Node-free reads — an InputMap action and a copy constant — the
## same terms `test_fast_forward.gd` and `test_tutorial_copy.gd` are checked on.
## The key is pinned because the button's label promises it: a binding that moved
## leaves the bar advertising a key that does nothing, which is exactly what
## ControlHints exists to prevent. That the press is live only where the button is
## is BattleLegend.commands_board's answer, checked in `test_battle_legend.gd`;
## `end_turn_ready_units` in the smoke sweep drives the press itself.

const _KEY_TEXT := "E"


func test_the_input_map_holds_the_action_on_e_and_a_free_pad_button() -> void:
	assert_true(InputMap.has_action(&"end_turn"), "the action ships in project.godot")
	var keys: Array[int] = []
	var buttons: Array[int] = []
	for event in InputMap.action_get_events(&"end_turn"):
		if event is InputEventKey:
			keys.append((event as InputEventKey).keycode)
		elif event is InputEventJoypadButton:
			buttons.append((event as InputEventJoypadButton).button_index)
	assert_eq(keys, [KEY_E] as Array[int], "the key the button prints")
	assert_eq(
		buttons,
		[JOY_BUTTON_RIGHT_STICK] as Array[int],
		"and the one ordinary pad button no other board action had taken"
	)


func test_the_key_it_is_bound_to_is_the_key_the_button_prints() -> void:
	assert_eq(OS.get_keycode_string(KEY_E), _KEY_TEXT, "the engine names KEY_E what the chip does")
	assert_true(
		ControlHints.END_TURN_CHIP.begins_with(_KEY_TEXT + " · "),
		"the chip leads with its key: %s" % ControlHints.END_TURN_CHIP
	)
	assert_true(
		ControlHints.END_TURN_CHIP.ends_with("END TURN"),
		"and still says what it does: %s" % ControlHints.END_TURN_CHIP
	)


## The bottom bar's button is not the top bar's chrome, so this chip is
## deliberately out of CHIPS — it never shares a row with a legend running at
## MAX_CHARS. The other rule that set is held to is the bar's font, which this
## one shares, so it is checked here rather than left unsaid.
func test_the_chip_is_ascii_and_out_of_the_top_bars_set() -> void:
	assert_false(ControlHints.END_TURN_CHIP in ControlHints.CHIPS, "not a top-bar chip")
	for i in ControlHints.END_TURN_CHIP.length():
		var code := ControlHints.END_TURN_CHIP.unicode_at(i)
		assert_true(code < 128 or code == 0x00B7, "non-ASCII in %s" % ControlHints.END_TURN_CHIP)


## No other action the board listens for may answer E, or a press would do two
## things at once. The engine's own `ui_*` set is skipped: it is the text and
## focus vocabulary of widgets, never of the board, and `E` legitimately walks a
## caret to the end of a line inside a text field.
func test_no_other_action_answers_the_same_key() -> void:
	for action in InputMap.get_actions():
		if action == &"end_turn" or String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			assert_false(key != null and key.keycode == KEY_E, "%s also answers E" % action)
			var button := event as InputEventJoypadButton
			assert_false(
				button != null and button.button_index == JOY_BUTTON_RIGHT_STICK,
				"%s also answers the right stick" % action
			)
