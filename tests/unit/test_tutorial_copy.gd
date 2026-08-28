extends GutTest
## The first-match onboarding's step script (COM-12): what the mission strip
## teaches, and in what order.
##
## Two jobs. The retirement logic is real logic — "which step is next" is a pure
## function of what the player has already done, and it is what makes the strip
## disappear for good — so it is tested like any resolver. The character caps are
## an editorial ruler in the tradition of test_commander_quotes.gd: nothing
## clips at 63 characters, but a hint that long has stopped being a hint on a
## 640x360 canvas.
##
## The key legend the top bar prints is the other Node-free copy registry and is
## test_control_hints.gd's.
##
## Presentation stays out of here, exactly as CLAUDE.md says: MissionStrip is a
## Node and is verified by driving the scene (the `mission_strip` and
## `mission_strip_retired` smoke scenarios).


func _all() -> Array[StringName]:
	return TutorialHints.ids()


func _body(id: StringName) -> String:
	for step: Dictionary in TutorialHints.STEPS:
		if step.id == id:
			return String(step.body)
	return ""


# --- the step script ----------------------------------------------------------


func test_steps_are_the_loop_in_teaching_order() -> void:
	# The order is the order a first turn performs them, which is the whole
	# premise of "teach by doing" — a strip that asked for a capture before a
	# selection would be a manual, not a hint.
	assert_eq(_all(), [&"select", &"move", &"capture", &"build", &"end_turn"] as Array[StringName])


func test_nothing_retired_teaches_the_first_step() -> void:
	var empty: Array[StringName] = []
	assert_eq(TutorialHints.next_step(empty).get("id"), &"select")


func test_retiring_a_step_advances_to_the_next() -> void:
	var retired: Array[StringName] = [&"select"]
	assert_eq(TutorialHints.next_step(retired).get("id"), &"move")


func test_retirement_is_by_id_not_by_position() -> void:
	# The player captures before they build, or never builds at all. Each id
	# retires on its own event, so an out-of-order match still walks the list.
	var retired: Array[StringName] = [&"select", &"move", &"build"]
	assert_eq(TutorialHints.next_step(retired).get("id"), &"capture")


func test_all_retired_leaves_no_step() -> void:
	# The empty dictionary is what hides the strip permanently, so it is the one
	# return value the presentation actually branches on.
	assert_true(TutorialHints.next_step(_all()).is_empty())


func test_later_labels_exclude_the_current_and_the_retired() -> void:
	var retired: Array[StringName] = [&"select"]
	assert_eq(
		TutorialHints.later_labels(retired), PackedStringArray(["CAPTURE", "BUILD", "END TURN"])
	)


func test_later_labels_are_empty_on_the_last_step() -> void:
	var retired: Array[StringName] = [&"select", &"move", &"capture", &"build"]
	assert_eq(TutorialHints.later_labels(retired).size(), 0)


# --- the strip's vocabulary ---------------------------------------------------


func test_the_strip_speaks_display_names_not_data_keys() -> void:
	# The capture hint used to say "a foot unit": a move_class id, which reads
	# against the game's own data as excluding the Mech, and the Mech captures.
	# Both halves are read off the roster, so a new capturer or a renamed move
	# class fails here rather than on a first-time player's board.
	var capture := _body(&"capture")
	for type: UnitType in Fixture.unit_db().all():
		if type.can_capture:
			assert_true(
				capture.contains(type.display_name), "capture hint omits %s" % type.display_name
			)
	for step: Dictionary in TutorialHints.STEPS:
		for word in String(step.body).to_lower().split(" ", false):
			var bare := String(word).lstrip(".,").rstrip(".,")
			for type: UnitType in Fixture.unit_db().all():
				assert_ne(
					bare,
					String(type.move_class),
					"step %s names a move class: %s" % [step.id, bare]
				)


# --- the editorial ruler ------------------------------------------------------


func test_every_step_fits_the_strip() -> void:
	for step: Dictionary in TutorialHints.STEPS:
		assert_lt(
			String(step.label).length(),
			TutorialHints.MAX_LABEL_CHARS + 1,
			"step label too long: %s" % step.label
		)
		assert_lt(
			String(step.body).length(),
			TutorialHints.MAX_BODY_CHARS + 1,
			"hint body too long: %s" % step.body
		)


func test_objective_fits_the_strip() -> void:
	assert_lt(TutorialHints.OBJECTIVE.length(), TutorialHints.MAX_BODY_CHARS + 1)


func test_step_ids_are_unique() -> void:
	var seen: Array[StringName] = []
	for id in _all():
		assert_false(id in seen, "duplicate step id: %s" % id)
		seen.append(id)


# --- the capture pin ----------------------------------------------------------
#
# Settings is an autoload, which GUT can reach and the rest of the suite has no
# reason to. Both calls below leave the preference file alone — pinning latches
# it shut, which is the whole point of it — so this mutates nothing on disk.


func test_pinning_retires_every_step() -> void:
	# What every capture but the strip's own does. A pin that failed would leave
	# the frame showing whatever this machine's player had already learned, which
	# is exactly the machine-dependence the pin exists to remove — and it failed
	# silently once already, on an untyped empty array.
	Settings.pin_hints(true)
	assert_eq(Settings.retired_hints, _all())
	assert_true(TutorialHints.next_step(Settings.retired_hints).is_empty())


func test_pinning_empty_is_the_fresh_install_state() -> void:
	Settings.pin_hints(false)
	assert_eq(Settings.retired_hints.size(), 0)
	assert_eq(TutorialHints.next_step(Settings.retired_hints).get("id"), &"select")
