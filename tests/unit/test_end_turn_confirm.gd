extends GutTest
## The end-of-day check: a device preference (COM-124), on until a player says
## otherwise, offered as a pause-menu row beside Speed and Sound — and the row
## stepper all three share, which is what turns a left or right press into a new
## setting and a new label.
##
## Every setting here is read off a fresh instance of the script rather than the
## live autoload, which has already loaded whatever this machine's player chose.
## Nothing here is added to the tree, and every instance that is about to be
## stepped is pinned first, which latches the preference file shut — so no test
## here writes user://settings.cfg.

const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")


## A pinned instance at the tier a fresh install plays at, so a row stepped from
## it steps from a known place on the ladder and nothing it sets is persisted.
func _pinned_settings() -> Variant:
	var fresh = autofree(SETTINGS_SCRIPT.new())
	fresh.pin(GameSpeed.DEFAULT_ID)
	return fresh


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


func test_the_speed_row_steps_its_own_ladder_both_ways() -> void:
	var fresh: Variant = _pinned_settings()
	var at_rest := "Speed: %s" % GameSpeed.by_id(GameSpeed.DEFAULT_ID).display_name
	var next_id := Settings.stepped_speed(GameSpeed.DEFAULT_ID, 1)
	assert_eq(
		fresh.cycle_row(Settings.SPEED_ROW, 1),
		"Speed: %s" % GameSpeed.by_id(next_id).display_name,
		"right steps to the tier after the one it was on"
	)
	assert_eq(fresh.speed.id, next_id, "and the row moved the setting, not only the label")
	assert_eq(
		fresh.cycle_row(Settings.SPEED_ROW, -1),
		at_rest,
		"left is the exact inverse through the row"
	)


func test_the_end_turn_row_takes_either_direction_as_the_other_value() -> void:
	var fresh: Variant = _pinned_settings()
	assert_eq(
		fresh.cycle_row(Settings.END_TURN_ROW, -1),
		"End-turn check: Off",
		"a left press on a two-state row lands on the other state"
	)
	assert_false(fresh.end_turn_confirm, "and the row moved the setting, not only the label")
	assert_eq(
		fresh.cycle_row(Settings.END_TURN_ROW, -1),
		"End-turn check: On",
		"and the same press again lands back"
	)


## The one row here that reaches outside the instance: every step it takes is
## applied to the real master bus, so this walks a whole lap and then hands the
## bus back the level the suite was playing at rather than leaving it on the step
## the last press landed on.
func test_the_sound_row_walks_the_volume_ladder_and_wraps() -> void:
	var db := AudioServer.get_bus_volume_db(Settings.MASTER_BUS)
	var muted := AudioServer.is_bus_mute(Settings.MASTER_BUS)
	var fresh: Variant = _pinned_settings()
	var walked: Array[String] = []
	var expected: Array[String] = []
	for i in Settings.VOLUME_STEPS.size():
		walked.append(fresh.cycle_row(Settings.SOUND_ROW, 1))
		var id: StringName = Settings.stepped_volume(Settings.FULL_ID, i + 1)
		expected.append("Sound: %s" % Settings.volume_label(id))
	AudioServer.set_bus_volume_db(Settings.MASTER_BUS, db)
	AudioServer.set_bus_mute(Settings.MASTER_BUS, muted)
	assert_eq(walked, expected, "each right press reads the next step of the ladder")
	assert_eq(
		walked[-1],
		"Sound: %s" % Settings.volume_label(Settings.FULL_ID),
		"and a whole lap comes back to where it started"
	)
