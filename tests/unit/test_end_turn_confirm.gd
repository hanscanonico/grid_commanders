extends GutTest
## The end-of-day check: a device preference (COM-124), on until a player says
## otherwise, offered as a pause-menu row beside Speed and Sound.
##
## The default is read off a fresh instance of the script rather than the live
## autoload, which has already loaded whatever this machine's player chose.
## Nothing here is added to the tree and nothing here calls a setter, so the
## preference file is never written.

const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")


func test_the_check_ships_on() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	assert_true(fresh.end_turn_confirm, "a fresh install still confirms the day away")


func test_the_row_says_which_way_it_is_set() -> void:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	assert_eq(fresh.row_label(Settings.END_TURN_ROW), "End-turn check: On")
	fresh.end_turn_confirm = false
	assert_eq(fresh.row_label(Settings.END_TURN_ROW), "End-turn check: Off")


func test_it_is_a_value_row_the_menu_offers() -> void:
	assert_true(
		Settings.END_TURN_ROW in Settings.VALUE_ROWS,
		"the pause menu cycles it like the two beside it"
	)
	var ids: Array = BattleMenus.map_actions(Fixture.state("[terrain]\nB.")).map(
		func(row: Dictionary) -> StringName: return row["id"]
	)
	assert_eq(ids.count(Settings.END_TURN_ROW), 1, "exactly one End-turn check row")
