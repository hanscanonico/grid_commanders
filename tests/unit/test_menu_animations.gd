extends GutTest
## Menu motion: the device preference that holds the menus still (COM-242) — the
## board drifting behind the main menu, its blinking PRESS START and the campaign
## pages' staggered reveals.
##
## Read off a fresh instance of the script rather than the live autoload, which has
## already loaded whatever this machine's player chose, and pinned before anything
## is set, which latches the preference file shut — so nothing here writes
## user://settings.cfg. Same terms as test_end_turn_confirm beside it.

const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")


func test_the_menus_move_on_a_fresh_install() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	assert_true(fresh.menu_animations, "a fresh install drifts the backdrop")
	assert_true(Settings.DEFAULT_MENU_ANIMATIONS, "and the default says so")


## A capture poses the menu still whatever this preference says, so all a stored
## "off" could reach is the toggle's own checkmark in the frame — which is exactly
## what a pin is for.
func test_a_pinned_launch_stands_the_motion_at_its_default() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.menu_animations = false
	fresh.pin(GameSpeed.DEFAULT_ID)
	assert_eq(
		fresh.menu_animations,
		Settings.DEFAULT_MENU_ANIMATIONS,
		"a pinned launch ignores what this machine's player chose"
	)


func test_the_setter_moves_the_preference_both_ways() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.pin(GameSpeed.DEFAULT_ID)
	fresh.set_menu_animations(false)
	assert_false(fresh.menu_animations, "the checkbox turns it off")
	fresh.set_menu_animations(true)
	assert_true(fresh.menu_animations, "and back on")


## It is a preference of its own, so it cannot be written into the file under a key
## another preference already owns.
func test_it_stores_under_a_key_of_its_own() -> void:
	var keys := [
		Settings.SPEED_KEY,
		Settings.BATTLE_ANIMATIONS_KEY,
		Settings.MENU_ANIMATIONS_KEY,
		Settings.VOLUME_KEY,
		Settings.END_TURN_CONFIRM_KEY,
		Settings.FULLSCREEN_KEY,
		Settings.HINTS_KEY,
	]
	assert_eq(keys.size(), 7, "seven preferences")
	var seen: Array = []
	for key: String in keys:
		assert_false(key in seen, "%s is stored twice" % key)
		seen.append(key)
