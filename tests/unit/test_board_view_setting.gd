extends GutTest
## The board view: flat or 3D, a device preference like the window mode beside it,
## flipped by V or the view chip, and never offered as a pause-menu row.
##
## Read off fresh instances of the script rather than the live autoload, pinned or
## flagged before anything is set, which latches the preference file shut — so
## nothing here writes user://settings.cfg (test_fullscreen_setting's terms).

const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")


func _pinned_settings() -> Variant:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.pin(GameSpeed.DEFAULT_ID)
	return fresh


func test_a_fresh_install_plays_on_the_3d_board() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	assert_true(fresh.board_3d, "the 3D board is what a new player starts on")


## Every save wrote the old key whether or not the player touched the view, so a
## stored false there is the old default speaking, not a choice.
func test_the_old_key_is_left_unread() -> void:
	var config := ConfigFile.new()
	config.set_value(Settings.SECTION, "board_3d", false)
	assert_true(
		Settings.stored_view(config, Settings.DEFAULT_BOARD_3D),
		"a stored board_3d=false does not shadow the 3D default"
	)


func test_the_view_key_round_trips() -> void:
	for chosen: bool in [false, true]:
		var config := ConfigFile.new()
		config.set_value(Settings.SECTION, Settings.BOARD_VIEW_KEY, chosen)
		assert_eq(Settings.stored_view(config, not chosen), chosen, "a choice made now persists")


func test_a_flip_is_announced_so_a_running_battle_can_swap_boards() -> void:
	var fresh = _pinned_settings()
	watch_signals(fresh)
	fresh.set_board_3d(true)
	assert_signal_emit_count(fresh, "board_view_changed", 1)


## A capture must not photograph this machine's preference, and a battle may
## already be standing on the 3D board when the pin lands — so the pin says so.
func test_a_pinned_launch_stands_the_flat_board_back_and_says_so() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.board_3d = true
	watch_signals(fresh)
	fresh.pin(GameSpeed.DEFAULT_ID)
	assert_false(fresh.board_3d, "a pinned launch ignores what this machine's player chose")
	assert_signal_emit_count(fresh, "board_view_changed", 1)


func test_the_view_flag_outranks_a_capture_pin() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.apply_args(Fixture.args(["--view=3d"]))
	fresh.pin(GameSpeed.DEFAULT_ID)
	assert_true(fresh.board_3d, "asking for a capture of the 3D board is what the flag is for")


func test_the_pause_menu_has_no_view_row() -> void:
	var ids: Array = BattleMenus.map_actions(Fixture.state(Fixture.NEUTRAL_BASE)).map(
		func(row: Dictionary) -> StringName: return row["id"]
	)
	assert_false(&"view" in ids, "the switch is the on-screen chip now")
	assert_false(&"view" in Settings.VALUE_ROWS)


func test_the_view_keys_are_bound() -> void:
	var wanted := {&"toggle_view": KEY_V, &"turn_view_left": KEY_C, &"turn_view_right": KEY_B}
	for action: StringName in wanted:
		assert_true(InputMap.has_action(action), "%s is missing from the input map" % action)
		var keys: Array[int] = []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys.append((event as InputEventKey).keycode)
		assert_true(wanted[action] in keys, "%s is on its key" % action)
