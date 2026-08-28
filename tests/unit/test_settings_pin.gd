extends GutTest
## What `pin` stands back, and what outranks it.
##
## A capture must not depend on the machine that took it, and four preferences
## reach a photographed pixel: the map menu's Sound row reads the volume, the two
## animation toggles draw their own checkmarks, and the end-turn check decides
## whether a scripted End Turn opens the guard at all.
##
## Read off a fresh instance of the script rather than the live autoload, and
## pinned before anything is written back, so nothing here touches
## user://settings.cfg. Same terms as test_menu_animations beside it.

const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")


func test_a_pinned_launch_stands_every_photographed_preference_back() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.end_turn_confirm = not Settings.DEFAULT_END_TURN_CONFIRM
	fresh.menu_animations = false
	fresh.battle_animations = false
	fresh.volume = Settings.OFF_ID
	fresh.pin(GameSpeed.DEFAULT_ID)
	assert_eq(
		fresh.end_turn_confirm, Settings.DEFAULT_END_TURN_CONFIRM, "the end-turn check stands back"
	)
	assert_eq(fresh.menu_animations, Settings.DEFAULT_MENU_ANIMATIONS, "menu motion stands back")
	assert_eq(
		fresh.battle_animations, Settings.DEFAULT_BATTLE_ANIMATIONS, "the cut-in toggle stands back"
	)
	assert_eq(fresh.volume, Settings.DEFAULT_VOLUME, "and so does the volume")


func test_the_defaults_are_what_a_fresh_install_carries() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	assert_eq(fresh.battle_animations, Settings.DEFAULT_BATTLE_ANIMATIONS, "cut-ins play")
	assert_eq(fresh.volume, Settings.DEFAULT_VOLUME, "at the loudest step")
	assert_eq(Settings.DEFAULT_VOLUME, Settings.FULL_ID, "which is Full")


## Both per-launch overrides are asked for on the very runs that pin, so a pin
## that stood them back would leave neither flag anything to do.
func test_an_explicit_mute_outranks_the_pin() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.apply_args(PackedStringArray([Settings.MUTE_ARG]))
	assert_eq(fresh.volume, Settings.OFF_ID, "the flag silences the launch")
	fresh.pin(GameSpeed.DEFAULT_ID)
	assert_eq(fresh.volume, Settings.OFF_ID, "and the pin leaves it silenced")


func test_an_explicit_no_battle_anim_outranks_the_pin() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.apply_args(PackedStringArray([Settings.NO_ANIM_ARG]))
	assert_false(fresh.battle_animations, "the flag turns the cut-in off")
	fresh.pin(GameSpeed.DEFAULT_ID)
	assert_false(fresh.battle_animations, "and the pin leaves it off")


## The speed latch is the shape the two above are written on, so it is checked
## beside them: a capture pins the tier it needs, an explicit flag outranks it.
func test_an_explicit_speed_outranks_the_pin() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	var wanted := GameSpeed.CAPTURE_ID
	fresh.apply_args(PackedStringArray([Settings.SPEED_ARG + String(wanted)]))
	fresh.pin(GameSpeed.DEFAULT_ID)
	assert_eq(fresh.speed.id, wanted, "the pin declines the tier the flag already chose")
