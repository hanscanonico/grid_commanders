extends GutTest
## The pages between the blocks: where one belongs, what it says, and the checks
## that keep an unplayable one out of the tree.
##
## It says something and decides nothing, so what is worth pinning is where it is
## placed and which of its lines are spoken — a block that went badly reading the
## same as one that went well is the whole feature failing silently, and it is
## `MissionLine`'s conditions doing the reading rather than a second mechanism.

const HELD := &"greenwater_held"


## Four missions in two blocks of two, and a page after the first.
func _campaign() -> CampaignDefinition:
	var missions: Array[MissionDefinition] = []
	for id: StringName in [&"one", &"two", &"three", &"four"]:
		missions.append(CampaignFixture.mission(id))
	var campaign := CampaignFixture.campaign(&"probe", missions)
	campaign.block_titles = ["First", "Second"]
	campaign.block_lengths = [2, 2]
	campaign.interludes.append(_interlude(0))
	return campaign


func _interlude(after_block: int) -> CampaignInterlude:
	var page := CampaignInterlude.new()
	page.after_block = after_block
	page.title = "The Crack"
	page.lines.append(MissionLine.of(&"", "The border did not hold and everybody knew it."))
	page.lines.append(_variant("Greenwater still stands.", _condition(1, -1)))
	page.lines.append(_variant("Greenwater is a name on a map now.", _condition(0, 0)))
	return page


func _variant(text: String, requires: FlagCondition) -> MissionLine:
	var line := MissionLine.of(&"", text)
	line.requires = requires
	return line


func _condition(at_least: int, at_most: int) -> FlagCondition:
	var condition := FlagCondition.new()
	condition.flag = HELD
	condition.at_least = at_least
	condition.at_most = at_most
	return condition


func _spoken(page: CampaignInterlude, ledger: CampaignState) -> Array[String]:
	var said: Array[String] = []
	for line: MissionLine in MissionLine.spoken(page.lines, ledger):
		said.append(line.text)
	return said


# --- where a page belongs ----------------------------------------------------


func test_a_block_is_closed_by_its_last_mission_and_no_other() -> void:
	var campaign := _campaign()
	assert_eq(campaign.closes_block(&"one"), -1)
	assert_eq(campaign.closes_block(&"two"), 0)
	assert_eq(campaign.closes_block(&"four"), 1)


func test_the_page_after_a_block_is_the_one_that_names_it() -> void:
	var campaign := _campaign()
	assert_not_null(campaign.interlude_after(0))
	assert_null(campaign.interlude_after(1), "a block with no page hands back to the hub")


func test_a_block_is_its_run_of_missions_and_the_runs_cover_the_list() -> void:
	var campaign := _campaign()
	assert_eq(campaign.block_mission_ids(0), [&"one", &"two"] as Array[StringName])
	assert_eq(campaign.block_mission_ids(1), [&"three", &"four"] as Array[StringName])
	assert_eq(campaign.block_mission_ids(2).size(), 0, "a block the campaign does not have")
	var covered := 0
	for block in campaign.block_lengths.size():
		covered += campaign.block_mission_ids(block).size()
	assert_eq(covered, campaign.mission_count())


func test_only_the_last_block_closes_the_war() -> void:
	var campaign := _campaign()
	assert_false(campaign.is_last_block(0))
	assert_true(campaign.is_last_block(1))
	assert_false(campaign.is_last_block(-1))


# --- what the act came to ----------------------------------------------------


func test_a_block_tallies_the_stars_its_missions_earned_out_of_those_on_offer() -> void:
	var campaign := _campaign()
	campaign.missions[1].par_day = 5
	assert_eq(campaign.block_stars(0, null), Vector2i(0, 3), "a null ledger earned nothing")
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 1, 4)
	state.complete(campaign, &"two", 2, 5)
	assert_eq(campaign.block_stars(0, state), Vector2i(3, 3))
	assert_eq(campaign.block_stars(1, state), Vector2i(0, 2), "the next block is untouched")


## The hub's rule for the war, at the width a block has: a mission the route
## walked past could never be cleared, so it is not on offer either.
func test_a_mission_the_route_skipped_is_not_on_offer() -> void:
	var campaign := _campaign()
	campaign.missions[2].unlock_requires = _condition(1, -1)
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 1, 4)
	state.complete(campaign, &"two", 1, 4)
	state.complete(campaign, &"four", 1, 4)
	assert_true(state.is_skipped(campaign, &"three"))
	assert_eq(campaign.block_stars(1, state), Vector2i(1, 1))


# --- what it says ------------------------------------------------------------


func test_a_block_that_went_badly_reads_differently_from_one_that_went_well() -> void:
	var campaign := _campaign()
	var page := campaign.interlude_after(0)
	var state := CampaignState.new()
	assert_eq(_spoken(page, state).size(), 2, "the narration and the one that fits")
	assert_eq(_spoken(page, state)[1], "Greenwater is a name on a map now.")
	state.flags[HELD] = 1
	assert_eq(_spoken(page, state)[1], "Greenwater still stands.")


func test_a_page_read_outside_a_profile_says_the_unconditional_lines() -> void:
	var page := _campaign().interlude_after(0)
	assert_eq(_spoken(page, null).size(), 2, "a null ledger reads every fact as zero")


# --- the checks --------------------------------------------------------------


func test_a_page_with_nothing_to_say_is_refused() -> void:
	var page := CampaignInterlude.new()
	assert_string_contains(page.definition_error(Fixture.commander_db()), "nothing to say")


func test_a_page_whose_speaker_is_not_on_the_roster_is_refused() -> void:
	var page := _interlude(0)
	page.lines.append(MissionLine.of(&"nobody_at_all", "A general nobody has heard of."))
	assert_string_contains(page.definition_error(Fixture.commander_db()), "not on the roster")


func test_a_page_after_a_block_the_campaign_does_not_have_is_refused() -> void:
	var campaign := _campaign()
	campaign.interludes[0].after_block = 4
	assert_string_contains(campaign.definition_error(), "interlude after block 4")


func test_two_pages_after_one_block_are_refused() -> void:
	var campaign := _campaign()
	campaign.interludes.append(_interlude(0))
	assert_string_contains(campaign.definition_error(), "two interludes after block 0")


## The campaign-wide check `ledger_error` already makes of a mission, at the width
## a page has: a variant nobody can ever hear is silent otherwise.
func test_a_page_reading_a_fact_no_mission_writes_is_refused() -> void:
	assert_string_contains(_campaign().ledger_error(), "the interlude after block 0 reads")
