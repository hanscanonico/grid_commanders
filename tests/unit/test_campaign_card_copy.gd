extends GutTest
## What the picker's card says beyond its tally: the whole premise, wrapped to as
## many lines as it takes — the card is the one place a war's pitch is printed —
## and the flagship's START HERE only until the war's first clear.

const PREMISE := "For twenty years the Ninth kept the peace. Then someone burned the hall."


func _flagship() -> CampaignDefinition:
	var missions: Array[MissionDefinition] = [
		CampaignFixture.mission(&"one"), CampaignFixture.mission(&"two")
	]
	return CampaignFixture.campaign(CampaignDB.FLAGSHIP_ID, missions)


func test_a_premise_is_given_every_line_it_wraps_to() -> void:
	var line := UiTheme.stat().get_string_size(
		PREMISE, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_STAT
	)
	assert_eq(CampaignPickerPanel.premise_lines(PREMISE, line.x + 1.0), 1, "one line when it fits")
	assert_gte(
		CampaignPickerPanel.premise_lines(PREMISE, line.x / 3.0),
		3,
		"a third of the width takes at least three lines"
	)


func test_no_premise_takes_no_lines() -> void:
	assert_eq(CampaignPickerPanel.premise_lines("", 300.0), 0)


func test_the_flagship_says_start_here_before_its_first_clear() -> void:
	var campaign := _flagship()
	assert_string_contains(CampaignPickerPanel.row_text(campaign, null), "START HERE")
	assert_string_contains(
		CampaignPickerPanel.row_text(campaign, CampaignState.begin(campaign)),
		"START HERE",
		"a profile with nothing cleared has not started yet"
	)


func test_the_flagship_stops_saying_start_here_once_a_mission_is_cleared() -> void:
	var campaign := _flagship()
	var progress := CampaignState.begin(campaign)
	progress.complete(campaign, &"one", 2, 4)
	assert_false(CampaignPickerPanel.row_text(campaign, progress).contains("START HERE"))


func test_a_saved_mission_is_named_on_the_card() -> void:
	var campaign := _flagship()
	var progress := CampaignState.begin(campaign)
	progress.active_mission = &"two"
	var text := CampaignPickerPanel.row_text(campaign, progress, true)
	assert_string_contains(text, "02 IN PROGRESS")
	assert_false(text.contains("START HERE"), "where the player left off outranks where to start")


func test_an_active_mission_with_no_saved_board_is_not_named() -> void:
	var campaign := _flagship()
	var progress := CampaignState.begin(campaign)
	progress.active_mission = &"two"
	assert_false(CampaignPickerPanel.row_text(campaign, progress).contains("IN PROGRESS"))
