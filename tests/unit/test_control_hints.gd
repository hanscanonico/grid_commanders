extends GutTest
## The key legend the top bar prints (COM-12): which words each board context
## shows, and the lens chips that stand beside them.
##
## An editorial ruler in the tradition of test_commander_quotes.gd — nothing
## clips at MAX_CHARS, but a legend that long has stopped fitting the bar on a
## 640x360 canvas — plus the two hand-edited InputMap promises the legend makes,
## which is why the keys themselves are pinned here rather than left to a
## playtest.
##
## Split from test_tutorial_copy.gd, which keeps the onboarding step script.
## CLAUDE.md names TutorialHints and ControlHints as two Node-free copy
## registries sharing that character-cap rule; they are two subjects.
##
## Presentation stays out of here, exactly as CLAUDE.md says: the bar is a Node
## and is verified by driving the scene.


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
