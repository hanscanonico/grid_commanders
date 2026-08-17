extends GutTest
## The volume ladder and the pause-menu row that cycles it.
##
## Settings is an autoload, but the ladder is static and pure — the same terms
## GameSpeed's table is checked on — so nothing here needs a scene, and nothing
## here writes the preference file.


func _ids(rows: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for row in rows:
		ids.append(row["id"])
	return ids


func test_every_step_has_its_own_id() -> void:
	var seen: Array[StringName] = []
	for step: Dictionary in Settings.VOLUME_STEPS:
		assert_false(step["id"] in seen, "%s is named twice" % step["id"])
		seen.append(step["id"])
	assert_eq(seen.size(), 4, "four steps, loudest first")


func test_the_named_ends_are_the_first_and_last_steps() -> void:
	assert_eq(Settings.volume_index(Settings.FULL_ID), 0, "Full is the loudest step")
	assert_eq(
		Settings.volume_index(Settings.OFF_ID),
		Settings.VOLUME_STEPS.size() - 1,
		"Off is the quietest step"
	)


func test_cycling_wraps_through_every_step() -> void:
	var id: StringName = Settings.FULL_ID
	var walked: Array[StringName] = []
	for _i in Settings.VOLUME_STEPS.size():
		walked.append(id)
		id = Settings.stepped_volume(id, 1)
	assert_eq(walked.size(), Settings.VOLUME_STEPS.size(), "the walk visits every step once")
	assert_eq(id, Settings.FULL_ID, "and comes back round to where it started")


func test_stepping_back_is_the_exact_inverse_of_stepping_on() -> void:
	for step: Dictionary in Settings.VOLUME_STEPS:
		var id: StringName = step["id"]
		assert_eq(
			Settings.stepped_volume(Settings.stepped_volume(id, 1), -1),
			id,
			"left undoes right on the volume ladder"
		)
	for tier in GameSpeed.ordered():
		assert_eq(
			Settings.stepped_speed(Settings.stepped_speed(tier.id, 1), -1),
			tier.id,
			"and on the speed ladder beside it"
		)


func test_off_is_the_mute_floor_and_full_is_untouched() -> void:
	assert_eq(Settings.volume_db(Settings.OFF_ID), -80.0, "Off is the floor the bus mutes at")
	assert_eq(Settings.volume_db(Settings.FULL_ID), 0.0, "Full plays the game as mixed")


func test_an_unknown_id_reads_as_the_loudest_step() -> void:
	assert_eq(Settings.volume_index(&"deafening"), -1, "a stranger names no step")
	assert_eq(
		Settings.volume_label(&"deafening"),
		Settings.volume_label(Settings.FULL_ID),
		"a stored id this version cannot place falls back rather than muting"
	)


func test_the_map_menu_offers_one_sound_row_reading_off_settings() -> void:
	var rows := BattleMenus.map_actions(Fixture.state("[terrain]\nB."))
	var ids := _ids(rows)
	assert_eq(ids.count(&"sound"), 1, "exactly one Sound row")
	var label := ""
	for row in rows:
		if row["id"] == &"sound":
			label = row["label"]
	assert_eq(
		label,
		"Sound: %s" % Settings.volume_label(Settings.volume),
		"the row reads the volume off its owner"
	)


func test_every_value_row_is_offered_once_and_declares_how_it_steps() -> void:
	var rows := BattleMenus.map_actions(Fixture.state("[terrain]\nB."))
	var ids := _ids(rows)
	for row: StringName in Settings.VALUE_ROWS:
		assert_eq(ids.count(row), 1, "exactly one %s row" % row)
	for entry in rows:
		var cycles: bool = entry.get("cycle", Callable()).is_valid()
		assert_eq(
			cycles,
			entry["id"] in Settings.VALUE_ROWS,
			"%s is stepped in place, never chosen, exactly when it carries a value" % entry["id"]
		)
