extends GutTest
## What the top bar says to a hand with no keyboard (mobile QA).
##
## Its own suite rather than more of test_tutorial_copy.gd: that file holds the
## key legend and was at the public-method ceiling, and these are the same rules
## read for the other hand.

# --- the legend a finger reads ------------------------------------------------


## The touch table answers for every context the key table does. A context with
## no touch line would print a keyboard legend on a phone, which is the defect
## this table exists to end rather than a gap it may leave.
func test_the_touch_legend_answers_for_every_context() -> void:
	assert_eq(
		ControlHints.TOUCH_LEGENDS.keys().size(),
		ControlHints.LEGENDS.keys().size(),
		"the two legend tables name different contexts"
	)
	for context: StringName in ControlHints.LEGENDS:
		assert_true(ControlHints.TOUCH_LEGENDS.has(context), "no touch legend for %s" % context)


func test_every_touch_legend_fits_the_top_bar() -> void:
	for context: StringName in ControlHints.TOUCH_LEGENDS:
		assert_lt(
			String(ControlHints.TOUCH_LEGENDS[context]).length(),
			ControlHints.MAX_CHARS + 1,
			"touch legend too long for the bar: %s" % context
		)


## A phone has none of these. The dock says BACK, RESUME and STEP and carries the
## zoom, so a touch line naming a key is either a lie or a duplicate.
func test_no_touch_legend_names_a_key() -> void:
	for context: StringName in ControlHints.TOUCH_LEGENDS:
		var legend: String = ControlHints.TOUCH_LEGENDS[context]
		for key in ["ENTER", "ESC", "UP/DN", "L/R", "+/-", "ANY KEY", "S · STEP"]:
			assert_false(key in legend, "%s touch legend names %s: %s" % [context, key, legend])


func test_touch_legends_are_ascii_only() -> void:
	for context: StringName in ControlHints.TOUCH_LEGENDS:
		var legend: String = ControlHints.TOUCH_LEGENDS[context]
		for i in legend.length():
			var code := legend.unicode_at(i)
			assert_true(
				code < 128 or code == 0x00B7, "non-ASCII in %s touch legend: %s" % [context, legend]
			)


## Which hand is playing picks the table, and an unknown context still falls back
## inside the table it picked rather than crossing to the other one.
func test_the_hand_playing_picks_the_table() -> void:
	assert_eq(
		ControlHints.legend_for(ControlHints.IDLE, true),
		String(ControlHints.TOUCH_LEGENDS[ControlHints.IDLE])
	)
	assert_eq(
		ControlHints.legend_for(ControlHints.IDLE, false),
		String(ControlHints.LEGENDS[ControlHints.IDLE])
	)
	assert_eq(
		ControlHints.legend_for(&"no_such_context", true),
		String(ControlHints.TOUCH_LEGENDS[ControlHints.IDLE])
	)


## Every chip the top bar may print has a touch word, held to the same two rules
## the key words are — and the desktop bar is untouched, which is what keeps the
## 85-frame sweep byte-stable.
func test_every_chip_has_a_touch_word() -> void:
	for chip in ControlHints.CHIPS:
		assert_true(ControlHints.TOUCH_CHIPS.has(chip), "no touch word for chip: %s" % chip)
		assert_eq(ControlHints.chip_for(chip, false), chip, "the desktop chip moved: %s" % chip)
		var word: String = ControlHints.TOUCH_CHIPS[chip]
		assert_lt(word.length(), ControlHints.MAX_CHARS / 3, "touch chip too wide: %s" % word)
		for i in word.length():
			assert_true(word.unicode_at(i) < 128, "non-ASCII touch chip: %s" % word)


## NEXT is the one chip a touch build drops, because the dock carries that control
## and chrome that says it twice is chrome that fits once.
func test_the_touch_bar_leaves_next_to_the_dock() -> void:
	assert_eq(ControlHints.chip_for(ControlHints.NEXT_CHIP, true), "")
	assert_eq(ControlHints.chip_for(ControlHints.THREAT_CHIP, true), "THREAT")
