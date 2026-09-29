extends GutTest
## The board view: flat or 3D, a device preference like the window mode beside it,
## offered as a pause-menu row and flipped from inside a battle by V.
##
## Read off fresh instances of the script rather than the live autoload, pinned or
## flagged before anything is set, which latches the preference file shut — so
## nothing here writes user://settings.cfg (test_fullscreen_setting's terms).

const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")


func _pinned_settings() -> Variant:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.pin(GameSpeed.DEFAULT_ID)
	return fresh


func test_a_fresh_install_plays_on_the_flat_board() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	assert_false(fresh.board_3d, "the flat board every capture was taken of is the default")


func test_the_row_says_which_board_is_up_and_flips_it() -> void:
	var fresh = _pinned_settings()
	assert_eq(fresh.row_label(Settings.VIEW_ROW), "View: 2D")
	assert_eq(fresh.cycle_row(Settings.VIEW_ROW, 1), "View: 3D")
	assert_true(fresh.board_3d, "the row moved the setting, not only the label")
	assert_eq(fresh.cycle_row(Settings.VIEW_ROW, -1), "View: 2D")


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


func test_it_is_a_value_row_the_pause_menu_offers() -> void:
	assert_true(Settings.VIEW_ROW in Settings.VALUE_ROWS)
	var ids: Array = BattleMenus.map_actions(Fixture.state(Fixture.NEUTRAL_BASE)).map(
		func(row: Dictionary) -> StringName: return row["id"]
	)
	assert_eq(ids.count(Settings.VIEW_ROW), 1, "exactly one View row")


func test_the_view_keys_are_bound() -> void:
	var wanted := {&"toggle_view": KEY_V, &"turn_view_left": KEY_C, &"turn_view_right": KEY_B}
	for action: StringName in wanted:
		assert_true(InputMap.has_action(action), "%s is missing from the input map" % action)
		var keys: Array[int] = []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys.append((event as InputEventKey).keycode)
		assert_true(wanted[action] in keys, "%s is on its key" % action)
