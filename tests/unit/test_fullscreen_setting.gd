extends GutTest
## The window mode: a device preference like the others in Settings, offered as a
## pause-menu row and flipped from anywhere by F11.
##
## Read off a fresh instance of the script rather than the live autoload, and
## pinned before anything is set, which latches the preference file shut — so
## nothing here writes user://settings.cfg. Same terms as test_menu_animations
## beside it; the two cases that ask the pause menu are the exception, and they
## only read the autoload. No real window stands either: `pin` and the setter
## both reach DisplayServer, which is the headless driver under `make test`.

const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")


func _pinned_settings() -> Variant:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.pin(GameSpeed.DEFAULT_ID)
	return fresh


func test_a_fresh_install_plays_in_a_window() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	assert_false(fresh.fullscreen, "a fresh install opens windowed")
	assert_false(Settings.DEFAULT_FULLSCREEN, "and the default says so")


## The strongest of the pin's reasons: a full-screen machine frames a capture at
## its own monitor, so every smoke frame would be the screen it was taken on.
func test_a_pinned_launch_stands_the_window_back() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.fullscreen = true
	fresh.pin(GameSpeed.DEFAULT_ID)
	assert_eq(
		fresh.fullscreen,
		Settings.DEFAULT_FULLSCREEN,
		"a pinned launch ignores what this machine's player chose"
	)


func test_the_row_says_which_way_it_is_set() -> void:
	var fresh = _pinned_settings()
	assert_eq(fresh.row_label(Settings.WINDOW_ROW), "Window: Windowed")
	fresh.set_fullscreen(true)
	assert_eq(fresh.row_label(Settings.WINDOW_ROW), "Window: Fullscreen")


func test_the_row_steps_the_setting_either_way() -> void:
	var fresh = _pinned_settings()
	assert_eq(fresh.cycle_row(Settings.WINDOW_ROW, 1), "Window: Fullscreen", "one press fills")
	assert_true(fresh.fullscreen, "and the row moved the setting, not only the label")
	assert_eq(fresh.cycle_row(Settings.WINDOW_ROW, -1), "Window: Windowed", "the other way back")
	assert_false(fresh.fullscreen)


func test_it_is_a_value_row_the_menu_offers() -> void:
	assert_true(
		Settings.WINDOW_ROW in Settings.VALUE_ROWS, "the pause menu cycles it like Sound beside it"
	)
	var ids: Array = BattleMenus.map_actions(Fixture.state(Fixture.NEUTRAL_BASE)).map(
		func(row: Dictionary) -> StringName: return row["id"]
	)
	assert_eq(ids.count(Settings.WINDOW_ROW), 1, "exactly one Window row")


## A phone's game fills the screen whatever anyone prefers, so the row is not
## offered there at all (mobile plan D5). Asked of the pause menu itself and not
## only of the answer it asks: the constant the menu used to read still holds the
## Window row, so a menu reading it again is caught here and nowhere else.
func test_a_touch_build_is_offered_no_window_row() -> void:
	var fresh = _pinned_settings()
	MobileProfile.pin(true)
	var rows: Array[StringName] = fresh.offered_rows()
	var ids: Array = BattleMenus.map_actions(Fixture.state(Fixture.NEUTRAL_BASE)).map(
		func(row: Dictionary) -> StringName: return row["id"]
	)
	MobileProfile.unpin()
	assert_false(Settings.WINDOW_ROW in rows, "a phone has no window to stand anywhere but full")
	assert_true(Settings.SOUND_ROW in rows, "and every other row is still offered")
	assert_false(Settings.WINDOW_ROW in ids, "so the pause menu prints no Window row on a phone")
	assert_true(Settings.SOUND_ROW in ids, "while the rows it does offer are still printed")


## The key is the whole of this setting's reach outside a menu, so the action has
## to be in the input map under the name Settings listens for.
func test_f11_is_bound_to_the_action_settings_listens_for() -> void:
	assert_true(
		InputMap.has_action(Settings.FULLSCREEN_ACTION),
		"%s is missing from the input map" % Settings.FULLSCREEN_ACTION
	)
	var keys: Array[int] = []
	for event in InputMap.action_get_events(Settings.FULLSCREEN_ACTION):
		if event is InputEventKey:
			keys.append((event as InputEventKey).keycode)
	assert_true(KEY_F11 in keys, "F11 is the key that flips the window")
