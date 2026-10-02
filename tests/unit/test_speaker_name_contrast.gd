extends GutTest
## A speaker's name is printed in their faction's colour, and that colour has a
## floor against the panel under it: the Iron Dominion's slate was a field colour
## that vanished as text on the dark panels and the blue dialogue window.

const DIALOGUE_BLUE := Color("#3a5ac8")


func _general_of(key: StringName) -> CommanderType:
	for commander: CommanderType in CommanderDB.load_default().all():
		if CommanderVisuals.theme_for(commander).key == key:
			return commander
	return null


func test_every_faction_clears_the_floor_on_the_dark_panel() -> void:
	for key: StringName in CommanderVisuals.FACTION_ORDER:
		var ink := CommanderVisuals.name_color(_general_of(key), UiTheme.SLATE_800)
		assert_gte(
			CommanderVisuals.contrast(ink, UiTheme.SLATE_800),
			CommanderVisuals.NAME_CONTRAST,
			"%s reads on the dark panel" % key
		)


func test_every_faction_clears_the_floor_on_the_dialogue_window() -> void:
	for key: StringName in CommanderVisuals.FACTION_ORDER:
		var ink := CommanderVisuals.name_color(_general_of(key), DIALOGUE_BLUE)
		assert_gte(
			CommanderVisuals.contrast(ink, DIALOGUE_BLUE),
			CommanderVisuals.NAME_CONTRAST,
			"%s reads on the blue window" % key
		)


func test_a_colour_that_already_reads_is_left_as_it_is() -> void:
	var meridian := _general_of(&"meridian")
	assert_eq(
		CommanderVisuals.name_color(meridian, UiTheme.SLATE_800),
		CommanderVisuals.theme_for(meridian).color,
		"the floor lifts only a name that needs it"
	)


func test_iron_is_lifted_off_its_field_colour() -> void:
	var iron := _general_of(&"iron")
	var field := CommanderVisuals.theme_for(iron).color
	assert_lt(CommanderVisuals.contrast(field, UiTheme.SLATE_800), CommanderVisuals.NAME_CONTRAST)
	assert_ne(CommanderVisuals.name_color(iron, UiTheme.SLATE_800), field)


func test_a_light_ground_sinks_the_name_instead() -> void:
	var ink := CommanderVisuals.name_color(_general_of(&"gold"), UiTheme.PAPER)
	assert_gte(CommanderVisuals.contrast(ink, UiTheme.PAPER), CommanderVisuals.NAME_CONTRAST)


func test_contrast_runs_from_one_to_twenty_one() -> void:
	assert_almost_eq(CommanderVisuals.contrast(Color.WHITE, Color.WHITE), 1.0, 0.001)
	assert_almost_eq(CommanderVisuals.contrast(Color.BLACK, Color.WHITE), 21.0, 0.001)
