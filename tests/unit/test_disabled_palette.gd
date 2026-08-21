extends GutTest
## A disabled button reads as present but unavailable, on the HUD's slate and on
## a cream panel alike: its plate keeps the opacity it was drawn with, its label
## keeps its own, and the two stay at least 3:1 apart. The shipped pair before
## `DisabledPalette` measured 2.2:1 with the plate at 45% alpha over the bottom
## bar, which is what put END TURN off the page.

const MIN_CONTRAST := 3.0


func test_a_disabled_cream_button_stays_readable() -> void:
	_assert_reads_as_disabled("secondary", UiTheme.PAPER, UiTheme.HARD_BORDER, UiTheme.INK)


func test_a_disabled_faction_button_stays_readable() -> void:
	for theme in CommanderVisuals.faction_themes():
		_assert_reads_as_disabled(theme.display, theme.color, theme.color_dark, theme.ink)


func test_a_disabled_ghost_keeps_no_plate_and_an_opaque_label() -> void:
	var clear := Color(0, 0, 0, 0)
	var plate := DisabledPalette.plate(clear, clear)
	assert_eq(plate.a, 0.0, "a GHOST button carries no plate in any state")
	var ink := DisabledPalette.label(UiTheme.WHITE, plate)
	assert_eq(ink.a, 1.0, "a disabled label is muted, never faded")
	assert_gt(
		_contrast(ink, UiTheme.SLATE_800),
		MIN_CONTRAST,
		"a ghost label is read on the dark surface it floats over"
	)
	assert_lt(
		ink.get_luminance(), UiTheme.WHITE.get_luminance(), "and it is dimmer than the live one"
	)


func _assert_reads_as_disabled(name: String, fill: Color, border: Color, fg: Color) -> void:
	var plate := DisabledPalette.plate(fill, border)
	assert_eq(plate.a, fill.a, "%s: a disabled plate keeps its own opacity" % name)
	assert_lt(plate.get_luminance(), fill.get_luminance(), "%s: and is visibly muted by it" % name)
	var ink := DisabledPalette.label(fg, plate)
	assert_eq(ink.a, fg.a, "%s: a disabled label keeps its own opacity" % name)
	assert_gt(_contrast(ink, plate), MIN_CONTRAST, "%s: label against its own plate" % name)


## WCAG relative-luminance contrast, the ratio the 3:1 floor above is stated in.
func _contrast(a: Color, b: Color) -> float:
	var lighter := maxf(_relative_luminance(a), _relative_luminance(b))
	var darker := minf(_relative_luminance(a), _relative_luminance(b))
	return (lighter + 0.05) / (darker + 0.05)


func _relative_luminance(color: Color) -> float:
	return 0.2126 * _linear(color.r) + 0.7152 * _linear(color.g) + 0.0722 * _linear(color.b)


func _linear(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)
