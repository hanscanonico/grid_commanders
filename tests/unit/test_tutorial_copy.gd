extends GutTest
## The first-match onboarding's two Node-free halves (COM-12): the step script
## the mission strip teaches and the key legend the top bar prints.
##
## Two jobs. The retirement logic is real logic — "which step is next" is a pure
## function of what the player has already done, and it is what makes the strip
## disappear for good — so it is tested like any resolver. The character caps are
## an editorial ruler in the tradition of test_commander_quotes.gd: nothing
## clips at 63 characters, but a hint that long has stopped being a hint on a
## 640x360 canvas.
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


# --- the key legend -----------------------------------------------------------


func test_every_legend_fits_the_top_bar() -> void:
	for context: StringName in ControlHints.LEGENDS:
		assert_lt(
			String(ControlHints.LEGENDS[context]).length(),
			ControlHints.MAX_CHARS + 1,
			"legend too long for the bar: %s" % context
		)


func test_unknown_context_falls_back_to_the_resting_legend() -> void:
	# Battle maps its State to a context key; a state that grows without one must
	# leave the bar telling the truth rather than blank. The hand is named rather
	# than defaulted: this file answers for the keyboard's table, so a sibling
	# suite's pin of MobileProfile can never decide which table it read.
	assert_eq(
		ControlHints.legend_for(&"no_such_context", false), ControlHints.LEGENDS[ControlHints.IDLE]
	)


func test_legends_are_ascii_only() -> void:
	# Silkscreen carries no arrows: a non-ASCII glyph beyond the middot the HUD
	# already prints would fall through to a system face at another size.
	for context: StringName in ControlHints.LEGENDS:
		var legend: String = ControlHints.LEGENDS[context]
		for i in legend.length():
			var code := legend.unicode_at(i)
			assert_true(
				code < 128 or code == 0x00B7, "non-ASCII in %s legend: %s" % [context, legend]
			)


## How the legends name their keys, held over the family rather than per line.
## The value menu is the only one where left and right do anything, so an L/R that
## leaked into MENU would advertise a dead key on every menu in the game; and the
## vertical pair is spelled "UP/DN" everywhere, because it read "UP/DOWN" in two of
## the four legends that name it and "UP/DN" in the other two — the pause menu
## respelling the key the action menu underneath it had just named. MAX_CHARS is
## what settles which spelling wins: the two crowded legends cannot carry the long
## one at all. MENU's exact words stay pinned so a change to them is deliberate.
func test_the_legends_name_a_key_one_way() -> void:
	assert_true(
		"L/R" in String(ControlHints.LEGENDS[ControlHints.VALUE_MENU]), "no L/R in the value menu"
	)
	for context: StringName in ControlHints.LEGENDS:
		var legend: String = ControlHints.LEGENDS[context]
		assert_false("UP/DOWN" in legend, "%s legend spells the pair long: %s" % [context, legend])
	assert_eq(
		String(ControlHints.LEGENDS[ControlHints.MENU]),
		"UP/DN · PICK   ENTER · OK   ESC · BACK",
		"the action menu's legend moved"
	)


## The lens chips stand beside the legend rather than inside it, so they are held
## to the same two rules by hand: each shares the bar's width with a legend that
## may already be running at MAX_CHARS, and each is printed in the same Silkscreen.
func test_the_lens_chips_fit_beside_the_legend() -> void:
	for chip in ControlHints.CHIPS:
		assert_lt(chip.length(), ControlHints.MAX_CHARS / 3, "chip too wide: %s" % chip)


## CHIPS is the set the two rules above are checked over, so a chip the bar
## prints and the array never heard of is a chip nothing holds to them.
func test_every_named_chip_is_in_the_set() -> void:
	for chip in [
		ControlHints.THREAT_CHIP,
		ControlHints.RANGE_CHIP,
		ControlHints.OBJECTIVES_CHIP,
		ControlHints.NEXT_CHIP
	]:
		assert_true(chip in ControlHints.CHIPS, "chip missing from CHIPS: %s" % chip)


func test_the_lens_chips_are_ascii_only() -> void:
	for chip in ControlHints.CHIPS:
		for i in chip.length():
			assert_true(
				chip.unicode_at(i) < 128 or chip.unicode_at(i) == 0x00B7, "non-ASCII: %s" % chip
			)


## The legend promises "+/- · ZOOM" as permanent chrome, so every key a player
## reads that as has to reach the action: unshifted "=", shifted "+", and both
## keypad keys. The InputMap is hand-edited in project.godot, which is why the
## promise is pinned here rather than left to a playtest.
func test_every_key_the_zoom_legend_promises_reaches_its_action() -> void:
	assert_true("+/-" in String(ControlHints.LEGENDS[ControlHints.IDLE]), "legend lost its zoom")
	for keycode: Key in [KEY_EQUAL, KEY_KP_ADD]:
		assert_true(_key(keycode).is_action_pressed(&"zoom_in"), "no zoom_in: %d" % keycode)
	assert_true(_key(KEY_EQUAL, true).is_action_pressed(&"zoom_in"), "shift+= misses zoom_in")
	for keycode: Key in [KEY_MINUS, KEY_KP_SUBTRACT]:
		assert_true(_key(keycode).is_action_pressed(&"zoom_out"), "no zoom_out: %d" % keycode)


## A mouse player selects, moves and picks menu rows with the mouse, so backing
## out has to be a mouse gesture too. Pinned here for the reason above: the
## binding is hand-edited in project.godot.
func test_right_click_reaches_cancel() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	assert_true(event.is_action_pressed(&"cancel"), "right-click misses cancel")


func _key(keycode: Key, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.shift_pressed = shift
	event.pressed = true
	return event
