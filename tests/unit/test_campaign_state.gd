extends GutTest
## Campaign progress and its save envelope.
##
## The rules worth pinning are the ones a player would notice going wrong: a bad
## replay must never cost a star already earned, a save must never be able to
## claim a mission is in progress without saying which, and a profile that
## outlives a renamed mission must lose that record rather than the whole run.
##
## Which mission a war opens next, and when it has run out of them, is the route's
## and lives in `test_campaign_route.gd`.
##
## Every rejection asserts the exact reason string: a bare `assert_ne(error, "")`
## passes on any refusal, so a branch that started answering with its neighbour's
## message would have kept the suite green.

var campaign: CampaignDefinition


func before_each() -> void:
	campaign = _campaign([&"one", &"two", &"three"])


func _campaign(ids: Array) -> CampaignDefinition:
	var missions: Array[MissionDefinition] = []
	for id: StringName in ids:
		missions.append(CampaignFixture.mission(id))
	return CampaignFixture.campaign(&"probe", missions)


# --- ordering ---------------------------------------------------------------


func test_the_order_is_the_lists_order() -> void:
	assert_eq(campaign.missions[0].id, &"one")
	assert_eq(campaign.index_of(&"two"), 1)
	assert_null(campaign.mission(&"nope"))


func test_blocks_are_a_label_over_a_run_of_that_same_order() -> void:
	campaign.block_titles = ["First", "Second"]
	campaign.block_lengths = [1, 2]
	assert_eq(campaign.definition_error(), "")
	assert_eq(campaign.block_of(&"one"), 0)
	assert_eq(campaign.block_of(&"two"), 1)
	assert_eq(campaign.block_of(&"three"), 1)


func test_blocks_that_do_not_cover_the_campaign_are_refused() -> void:
	campaign.block_titles = ["First"]
	campaign.block_lengths = [2]
	assert_ne(campaign.definition_error(), "", "two of three missions is not a covering")


func test_a_campaign_naming_one_mission_twice_is_refused() -> void:
	campaign.missions.append(CampaignFixture.mission(&"one"))
	assert_eq(campaign.definition_error(), "campaign 'probe' names mission 'one' twice")


# --- progress ---------------------------------------------------------------


func test_a_fresh_profile_opens_only_the_first_mission() -> void:
	var state := CampaignState.begin(campaign)
	assert_true(state.is_unlocked(&"one"))
	assert_false(state.is_unlocked(&"two"))
	assert_eq(state.total_stars(), 0)


func test_clearing_a_mission_opens_the_next() -> void:
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 2, 5)
	assert_true(state.is_cleared(&"one"))
	assert_true(state.is_unlocked(&"two"))
	assert_eq(state.stars_for(&"one"), 2)
	assert_eq(state.total_stars(), 2)


func test_a_worse_replay_never_costs_a_star_already_earned() -> void:
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 3, 4)
	state.complete(campaign, &"one", 1, 9)
	assert_eq(state.stars_for(&"one"), 3, "best, not last")
	assert_eq(state.records[&"one"].best_day, 4, "and the faster day stands")


func test_stars_and_days_are_judged_separately() -> void:
	# A run can earn a third star while taking longer. Keeping the pair from the
	# better *run* would silently discard whichever half that run was worse at.
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 1, 4)
	state.complete(campaign, &"one", 3, 9)
	assert_eq(state.stars_for(&"one"), 3)
	assert_eq(state.records[&"one"].best_day, 4)


# --- the save envelope ------------------------------------------------------


func test_progress_survives_a_round_trip() -> void:
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 3, 4)
	state.active_mission = &"two"
	var decoded := CampaignSaveCodec.decode(CampaignSaveCodec.encode(state))
	assert_not_null(decoded)
	assert_eq(decoded.campaign_id, &"probe")
	assert_true(decoded.is_unlocked(&"two"))
	assert_eq(decoded.stars_for(&"one"), 3)
	assert_eq(decoded.records[&"one"].best_day, 4)
	assert_eq(decoded.active_mission, &"two")


func test_the_battle_snapshot_is_carried_whole_and_never_re_encoded() -> void:
	var state := CampaignState.begin(campaign)
	state.active_mission = &"one"
	var battle := {"version": 8, "day": 3, "anything": "the skirmish codec's business"}
	var data := CampaignSaveCodec.encode(state, battle)
	assert_eq(CampaignSaveCodec.battle_of(data), battle)
	assert_eq(CampaignSaveCodec.validate(data), "")


func test_a_profile_between_missions_carries_no_battle() -> void:
	var data := CampaignSaveCodec.encode(CampaignState.begin(campaign))
	assert_false(data.has("battle"))
	assert_eq(CampaignSaveCodec.battle_of(data), {})


func test_a_battle_with_no_mission_to_belong_to_is_refused() -> void:
	var state := CampaignState.begin(campaign)
	var data := CampaignSaveCodec.encode(state, {"version": 8})
	assert_ne(CampaignSaveCodec.validate(data), "", "a board with no mission is nobody's")


func test_a_save_from_a_later_build_is_refused_rather_than_guessed_at() -> void:
	var data := CampaignSaveCodec.encode(CampaignState.begin(campaign))
	data["version"] = CampaignSaveCodec.VERSION + 1
	assert_eq(
		CampaignSaveCodec.validate(data),
		(
			"save claims version %d; this build writes %d"
			% [CampaignSaveCodec.VERSION + 1, CampaignSaveCodec.VERSION]
		)
	)


func test_a_shapeless_save_is_refused() -> void:
	assert_eq(CampaignSaveCodec.validate({}), "save has no version")
	assert_eq(
		CampaignSaveCodec.validate({"version": 1}),
		"save names no campaign",
		"version 1 is a legal older profile, so what is missing is the campaign's name"
	)
	assert_eq(
		CampaignSaveCodec.validate(
			{"version": 1, "campaign_id": "", "unlocked": [], "records": {}}
		),
		"save names an empty campaign"
	)
	assert_eq(
		CampaignSaveCodec.validate(
			{"version": 1, "campaign_id": "probe", "unlocked": [], "records": {}}
		),
		"save has neither an unlocked mission nor a cleared one"
	)


## Where a hand-edited profile lands first: every section is refused for being the
## wrong *kind* of thing before anything reads inside it.
func test_a_section_that_is_not_the_container_it_should_be_is_refused() -> void:
	var state := CampaignState.begin(campaign)
	state.active_mission = &"one"
	for section: String in ["unlocked", "records", "flags", "roster", "battle"]:
		var data := CampaignSaveCodec.encode(state, {"version": 8})
		data[section] = "not a section"
		assert_ne(CampaignSaveCodec.validate(data), "", "'%s' as text" % section)
	var tally := CampaignSaveCodec.encode(state, {"version": 8})
	tally["mission_progress"] = "not a set of counters"
	assert_ne(CampaignSaveCodec.validate(tally), "", "and a tally is counters")


func test_a_profile_keyed_by_something_that_is_not_a_name_is_refused() -> void:
	var state := CampaignState.begin(campaign)
	var data := CampaignSaveCodec.encode(state)
	data["unlocked"] = [7]
	assert_ne(CampaignSaveCodec.validate(data), "", "a mission id is text")
	data = CampaignSaveCodec.encode(state)
	data["records"] = {7: {"stars": 1, "best_day": 2}}
	assert_ne(CampaignSaveCodec.validate(data), "", "and so is the key of a record")
	data = CampaignSaveCodec.encode(state)
	data["records"] = {"one": 3}
	assert_ne(CampaignSaveCodec.validate(data), "", "a record is a result, not a number")
	data = CampaignSaveCodec.encode(state)
	data["records"] = {"one": {"stars": -1, "best_day": 2}}
	assert_ne(CampaignSaveCodec.validate(data), "", "nobody earned fewer than no stars")
	data = CampaignSaveCodec.encode(state)
	data["flags"] = {7: 1}
	assert_ne(CampaignSaveCodec.validate(data), "", "and a fact is named, never numbered")


func test_a_profile_the_codec_refuses_decodes_to_nothing_and_says_why() -> void:
	var data := CampaignSaveCodec.encode(CampaignState.begin(campaign))
	data["flags"] = {"greenwater held": 1}
	assert_null(CampaignSaveCodec.decode(data), "a refused profile is never half-loaded")
	assert_push_error_count(1, "and the refusal is named in the log")


func test_a_record_for_a_mission_the_campaign_no_longer_has_is_tolerated() -> void:
	# A renamed mission should cost its own record, never the whole profile.
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 2, 4)
	var data := CampaignSaveCodec.encode(state)
	data["records"]["a_mission_that_moved"] = {"stars": 1, "best_day": 2}
	assert_eq(CampaignSaveCodec.validate(data), "")
	assert_not_null(CampaignSaveCodec.decode(data))
