extends GutTest
## Campaign progress and its save envelope.
##
## The rules worth pinning are the ones a player would notice going wrong: a bad
## replay must never cost a star already earned, a save must never be able to
## claim a mission is in progress without saying which, and a profile that
## outlives a renamed mission must lose that record rather than the whole run.

var campaign: CampaignDefinition


func before_each() -> void:
	campaign = _campaign([&"one", &"two", &"three"])


func _mission(id: StringName) -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.id = id
	mission.title = String(id)
	mission.map_path = "res://maps/first_steps.txt"
	return mission


func _campaign(ids: Array) -> CampaignDefinition:
	var definition := CampaignDefinition.new()
	definition.id = &"probe"
	definition.title = "Probe"
	for id: StringName in ids:
		definition.missions.append(_mission(id))
	return definition


# --- ordering ---------------------------------------------------------------


func test_the_order_is_the_lists_order() -> void:
	assert_eq(campaign.first_mission_id(), &"one")
	assert_eq(campaign.next_mission_id(&"one"), &"two")
	assert_eq(campaign.next_mission_id(&"three"), &"", "nothing follows the last one")
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
	campaign.missions.append(_mission(&"one"))
	assert_ne(campaign.definition_error(), "")


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


func test_the_resume_point_is_the_first_unlocked_mission_not_yet_cleared() -> void:
	var state := CampaignState.begin(campaign)
	assert_eq(state.resume_point(campaign), &"one")
	state.complete(campaign, &"one", 1, 3)
	assert_eq(state.resume_point(campaign), &"two")


func test_a_mission_in_progress_is_where_a_returning_player_lands() -> void:
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 1, 3)
	state.active_mission = &"two"
	assert_eq(state.resume_point(campaign), &"two")


func test_a_campaign_is_complete_only_when_every_mission_is() -> void:
	var state := CampaignState.begin(campaign)
	for id: StringName in [&"one", &"two"]:
		state.complete(campaign, id, 1, 3)
	assert_false(state.is_complete(campaign))
	state.complete(campaign, &"three", 1, 3)
	assert_true(state.is_complete(campaign))


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
	assert_ne(CampaignSaveCodec.validate(data), "")


func test_a_shapeless_save_is_refused() -> void:
	assert_ne(CampaignSaveCodec.validate({}), "")
	assert_ne(CampaignSaveCodec.validate({"version": 1}), "")
	assert_ne(
		CampaignSaveCodec.validate(
			{"version": 1, "campaign_id": "", "unlocked": [], "records": {}}
		),
		"",
		"a campaign with no name"
	)
	assert_ne(
		CampaignSaveCodec.validate(
			{"version": 1, "campaign_id": "probe", "unlocked": [], "records": {}}
		),
		"",
		"nothing unlocked and nothing cleared is no profile at all"
	)


func test_a_record_for_a_mission_the_campaign_no_longer_has_is_tolerated() -> void:
	# A renamed mission should cost its own record, never the whole profile.
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 2, 4)
	var data := CampaignSaveCodec.encode(state)
	data["records"]["a_mission_that_moved"] = {"stars": 1, "best_day": 2}
	assert_eq(CampaignSaveCodec.validate(data), "")
	assert_not_null(CampaignSaveCodec.decode(data))
