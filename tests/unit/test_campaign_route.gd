extends GutTest
## Branching (campaign-depth D7): which mission a war opens next, which it walks
## past, and when it has run out of them.
##
## The rules worth pinning are the two the decision is made of. **A mission the
## route opened can never close** — conditions read both ways, so a war that goes
## on to record something must not be able to take back a mission the player is
## already standing on. And **a road not taken is not a campaign unfinished** — a
## player who was never offered the optional mission has finished the war, or the
## last mission of every branching campaign reads as an unfinished one forever.
##
## `test_campaign_state.gd` owns progress and its save envelope; this is the
## walk laid over it, and `test_campaign_content.gd` holds the shipped content to
## the same bar.

const HELD := &"greenwater_held"


func _mission(id: StringName) -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.id = id
	mission.title = String(id)
	mission.map_path = "res://maps/first_steps.txt"
	return mission


func _campaign(ids: Array = [&"one", &"two", &"three"]) -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.id = &"probe"
	campaign.title = "Probe"
	for id: StringName in ids:
		campaign.missions.append(_mission(id))
	return campaign


func _condition(flag: StringName, at_least := 1, at_most := -1) -> FlagCondition:
	var condition := FlagCondition.new()
	condition.flag = flag
	condition.at_least = at_least
	condition.at_most = at_most
	return condition


## A beat on `mission` that writes `flag`, so the campaign-wide checks can see a
## writer for it.
func _writes(mission: MissionDefinition, flag: StringName) -> void:
	var effect := SetFlagEffect.new()
	effect.flag = flag
	effect.value = 1
	var event := MissionEvent.new()
	event.id = &"writes_it"
	event.effects.append(effect)
	mission.events.append(event)


# --- the walk ---------------------------------------------------------------


func test_a_mission_with_no_condition_opens_exactly_as_it_always_did() -> void:
	var campaign := _campaign()
	var state := CampaignState.begin(campaign)
	assert_true(state.is_unlocked(&"one"))
	assert_false(state.is_unlocked(&"two"))
	state.complete(campaign, &"one", 2, 5)
	assert_true(state.is_unlocked(&"two"))
	assert_eq(state.open_mission(campaign), &"two")


func test_the_route_walks_past_a_mission_the_war_closed() -> void:
	var campaign := _campaign()
	campaign.missions[1].unlock_requires = _condition(HELD)
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 1, 3)
	assert_false(state.is_unlocked(&"two"), "nothing wrote the fact it opens on")
	assert_true(state.is_unlocked(&"three"), "so the one behind it opens instead")
	assert_true(state.is_skipped(campaign, &"two"))


func test_a_mission_opens_on_a_fact_the_mission_before_it_wrote() -> void:
	var campaign := _campaign()
	campaign.missions[1].unlock_requires = _condition(HELD)
	var state := CampaignState.begin(campaign)
	state.flags[HELD] = 1
	state.complete(campaign, &"one", 1, 3)
	assert_true(state.is_unlocked(&"two"))
	assert_false(state.is_skipped(campaign, &"two"))


## The ledger has to have taken the finished mission's own facts before the route
## is read, or a mission can never open the one behind it.
func test_a_mission_can_open_the_next_one_with_a_fact_of_its_own() -> void:
	var campaign := _campaign()
	campaign.missions[1].unlock_requires = _condition(HELD)
	var state := CampaignState.begin(campaign)
	var tally := MissionProgress.new()
	tally.stage_flag(HELD, 1, false)
	state.complete(campaign, &"one", 1, 3, tally)
	assert_true(state.is_unlocked(&"two"))


func test_a_mission_already_open_is_never_closed_by_what_the_war_records_next() -> void:
	var campaign := _campaign()
	# The shape an optional mission takes: it opens while the fact is *absent*.
	campaign.missions[1].unlock_requires = _condition(HELD, 0, 0)
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 1, 3)
	assert_true(state.is_unlocked(&"two"))
	state.flags[HELD] = 1
	assert_true(state.is_unlocked(&"two"), "the latch holds")
	assert_eq(state.open_mission(campaign), &"two", "and the route still offers it")
	assert_false(state.is_skipped(campaign, &"two"))


## The route only moves forward. A fact written late must not drag the player
## back to ground the war has already gone past, whatever it now says.
func test_a_fact_written_late_does_not_reopen_a_road_already_passed() -> void:
	var campaign := _campaign([&"one", &"two", &"three", &"four"])
	campaign.missions[1].unlock_requires = _condition(HELD)
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 1, 3)
	state.complete(campaign, &"three", 1, 3)
	state.flags[HELD] = 1
	assert_eq(state.open_mission(campaign), &"four")
	assert_false(state.is_unlocked(&"two"))


func test_a_mission_ahead_of_the_route_is_locked_rather_than_skipped() -> void:
	var state := CampaignState.begin(_campaign())
	assert_false(state.is_skipped(_campaign(), &"three"))


# --- what "complete" now means ----------------------------------------------


func test_a_campaign_with_a_skipped_optional_mission_reports_complete() -> void:
	var campaign := _campaign()
	campaign.missions[1].unlock_requires = _condition(HELD)
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 1, 3)
	assert_false(state.is_complete(campaign))
	state.complete(campaign, &"three", 1, 3)
	assert_true(state.is_complete(campaign), "the road not taken is not a war unfinished")
	assert_false(state.is_cleared(&"two"))


func test_a_war_counts_the_missions_it_can_still_offer() -> void:
	var campaign := _campaign()
	campaign.missions[1].unlock_requires = _condition(HELD)
	var state := CampaignState.begin(campaign)
	assert_eq(state.offered_count(campaign), 3, "nothing has been walked past yet")
	state.complete(campaign, &"one", 1, 3)
	assert_eq(state.offered_count(campaign), 2, "and the road not taken leaves the total")


## The picker is the other surface that says how far a war has got, and it has to
## say the same thing the hub does: one campaign, one notion of finished.
func test_the_campaign_list_reads_a_war_finished_off_the_route() -> void:
	var campaign := _campaign()
	campaign.missions[1].unlock_requires = _condition(HELD)
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 1, 3)
	assert_string_contains(
		CampaignPickerPanel.row_text(campaign, state), "1/2", "out of what is left to play"
	)
	state.complete(campaign, &"three", 1, 3)
	assert_string_contains(
		CampaignPickerPanel.row_text(campaign, state),
		"complete",
		"a war with nothing left to offer is finished on the list as well as in the route"
	)


func test_the_campaign_list_says_new_for_a_war_with_no_profile() -> void:
	assert_string_contains(CampaignPickerPanel.row_text(_campaign(), null), "new")


func test_a_campaign_is_unfinished_while_any_mission_it_opened_is() -> void:
	var campaign := _campaign()
	var state := CampaignState.begin(campaign)
	for id: StringName in [&"one", &"two"]:
		state.complete(campaign, id, 1, 3)
	assert_false(state.is_complete(campaign))
	state.complete(campaign, &"three", 1, 3)
	assert_true(state.is_complete(campaign))


# --- the reachability check --------------------------------------------------


func test_a_mission_opening_on_a_fact_nothing_before_it_writes_is_refused() -> void:
	var campaign := _campaign()
	campaign.missions[1].unlock_requires = _condition(HELD)
	_writes(campaign.missions[2], HELD)
	assert_string_contains(campaign.route_error(), "no mission before it writes")


## The one shape that is authoring rather than error: a fact only an optional
## mission writes is a road the player may decline, and the reader is meant to
## tolerate reading zero.
func test_a_fact_an_optional_mission_writes_is_a_road_not_an_error() -> void:
	var campaign := _campaign()
	_writes(campaign.missions[0], &"prologue_seen")
	# Two is optional and three opens on what two writes: decline the first and
	# the second closes with it, which is a route rather than a slip.
	campaign.missions[1].unlock_requires = _condition(&"prologue_seen", 0, 0)
	_writes(campaign.missions[1], HELD)
	campaign.missions[2].unlock_requires = _condition(HELD)
	assert_eq(campaign.route_error(), "")


func test_a_mission_opening_on_a_mission_behind_it_is_allowed_and_ahead_is_not() -> void:
	var campaign := _campaign()
	campaign.missions[2].unlock_requires = _condition(&"stars:one", 3)
	assert_eq(campaign.route_error(), "")
	campaign.missions[2].unlock_requires = _condition(&"cleared:three")
	assert_string_contains(campaign.route_error(), "is not behind it")


func test_a_condition_nothing_could_hold_is_refused_when_the_mission_loads() -> void:
	var mission := _mission(&"one")
	mission.unlock_requires = _condition(HELD, 3, 1)
	var map := MapData.load_from_file(mission.map_path, Fixture.terrain_db())
	assert_string_contains(mission.definition_error(map, Fixture.unit_db()), "opens on")


func test_the_fact_a_mission_opens_on_is_one_the_campaign_has_to_write() -> void:
	var campaign := _campaign()
	campaign.missions[1].unlock_requires = _condition(HELD)
	assert_string_contains(campaign.ledger_error(), "which no mission of it writes")
