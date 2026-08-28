extends GutTest
## What may name a fact in the consequence ledger, where a name is held against
## the war, and what a profile may carry it in.
##
## `test_campaign_ledger.gd`'s sibling and split from it at the ceiling the save
## codec's suite was split at: that one is what a mission *writes* and what a later
## one *reads*, this one is the vocabulary and the file. The failures here are the
## silent ones — a misspelled flag reads zero forever, so the variant line simply
## never speaks and the gated beat never fires, and only the whole campaign can see
## that nothing writes the name.
##
## Every rejection asserts the exact reason string: a bare `assert_ne(error, "")`
## passes on any refusal, so a branch that started answering with its neighbour's
## message would have kept the suite green.

const PROBE := &"__probe_ledger_names_campaign"
const HELD := &"greenwater_held"
const SAVED := &"towns_saved"

## Two cities and an HQ on one row, with a named garrison on army 2 — the fixture
## board its sibling plays on, so a beat that removes a unit is authored the same
## way in both.
const ROW := """
[terrain]
CCQ..
[owners]
1 0 0
2 1 0
2 2 0
[units]
1 i 3 0
2 i 1 0 garrison
2 i 4 0
"""


func _campaign(ids: Array = [&"probe_one", &"probe_two"]) -> CampaignDefinition:
	var missions: Array[MissionDefinition] = []
	for id: StringName in ids:
		missions.append(CampaignFixture.capture_mission(id))
	return CampaignFixture.campaign(PROBE, missions)


func _condition(flag: StringName, at_least := 1, at_most := -1) -> FlagCondition:
	var condition := FlagCondition.new()
	condition.flag = flag
	condition.at_least = at_least
	condition.at_most = at_most
	return condition


func _writes(flag: StringName, value := 1, accumulates := false) -> SetFlagEffect:
	var effect := SetFlagEffect.new()
	effect.flag = flag
	effect.value = value
	effect.mode = SetFlagEffect.Mode.ADD if accumulates else SetFlagEffect.Mode.SET
	effect.note = "Greenwater held."
	return effect


## A beat due from day one, doing whatever it is handed.
func _beat(
	id: StringName, effects: Array[MissionEffect], gate: FlagCondition = null
) -> MissionEvent:
	var day := DayReachedTrigger.new()
	day.day = 1
	var event := MissionEvent.new()
	event.id = id
	event.triggers = [day]
	if gate != null:
		var flag := FlagTrigger.new()
		flag.condition = gate
		event.triggers.append(flag)
	event.effects = effects
	return event


## The defenders a flag takes off an opening board, for a beat that has to read the
## war before it does anything.
func _garrison_withdrawn() -> RemoveUnitsEffect:
	var effect := RemoveUnitsEffect.new()
	effect.tags = [&"garrison"]
	return effect


# --- the file ------------------------------------------------------------------


func test_a_profile_from_before_the_ledger_opens_with_an_empty_one() -> void:
	var campaign := _campaign()
	var older := CampaignSaveCodec.encode(CampaignState.begin(campaign))
	older["version"] = 1
	older.erase("flags")
	assert_eq(CampaignSaveCodec.validate(older), "", "a version 1 profile is still a profile")
	var decoded := CampaignSaveCodec.decode(older)
	assert_not_null(decoded)
	assert_eq(decoded.flags, {} as Dictionary[StringName, int])
	assert_eq(decoded.flag(HELD), 0, "and every fact in it reads as never written")


## The compatibility promise reads one way only: a profile from before the ledger
## opens with an empty one, and a profile from before the ledger holding a *fact*
## is a file no writer could have produced.
func test_a_profile_older_than_the_ledger_may_not_carry_a_fact() -> void:
	var older := CampaignSaveCodec.encode(CampaignState.begin(_campaign()))
	older["version"] = 2
	older["flags"] = {"greenwater_held": 1}
	assert_string_contains(CampaignSaveCodec.validate(older), "the ledger arrived in")
	older["flags"] = {}
	assert_eq(
		CampaignSaveCodec.validate(older), "", "and an empty section carries no ledger at all"
	)


func test_the_ledger_survives_a_round_trip() -> void:
	var state := CampaignState.begin(_campaign())
	state.flags[HELD] = 1
	state.flags[SAVED] = 4
	var decoded := CampaignSaveCodec.decode(CampaignSaveCodec.encode(state))
	assert_not_null(decoded)
	assert_eq(decoded.flag(HELD), 1)
	assert_eq(decoded.flag(SAVED), 4)


func test_a_ledger_no_writer_could_have_produced_is_refused() -> void:
	var data := CampaignSaveCodec.encode(CampaignState.begin(_campaign()))
	data["flags"] = {"greenwater held": 1}
	assert_ne(CampaignSaveCodec.validate(data), "", "a flag is an identifier")
	data["flags"] = {"greenwater_held": -1}
	assert_ne(CampaignSaveCodec.validate(data), "", "and a fact is never negative")
	data["flags"] = {"cleared:probe_one": 1}
	assert_ne(CampaignSaveCodec.validate(data), "", "the campaign's own record is not stored")
	data["flags"] = {"a_fact_no_mission_writes_any_more": 2}
	assert_eq(CampaignSaveCodec.validate(data), "", "but a renamed fact costs itself, not the run")


func test_the_stored_ledger_is_in_name_order_whatever_order_it_was_written_in() -> void:
	var first := CampaignState.begin(_campaign())
	first.flags[SAVED] = 2
	first.flags[HELD] = 1
	var second := CampaignState.begin(_campaign())
	second.flags[HELD] = 1
	second.flags[SAVED] = 2
	assert_eq(
		JSON.stringify(CampaignSaveCodec.encode(first)),
		JSON.stringify(CampaignSaveCodec.encode(second))
	)


# --- what the campaign answers for itself --------------------------------------


func test_a_cleared_mission_is_a_fact_read_off_the_record_it_already_is() -> void:
	var campaign := _campaign()
	var state := CampaignState.begin(campaign)
	assert_eq(state.flag(&"cleared:probe_one"), 0)
	assert_eq(state.flag(&"stars:probe_one"), 0)
	state.complete(campaign, &"probe_one", 2, 5)
	assert_eq(state.flag(&"cleared:probe_one"), 1)
	assert_eq(state.flag(&"stars:probe_one"), 2)
	assert_eq(state.flags, {} as Dictionary[StringName, int], "and nothing is stored twice")


func test_a_beat_may_not_write_the_campaigns_own_record() -> void:
	var map := MapData.parse(ROW, Fixture.terrain_db())
	assert_eq(
		_writes(&"cleared:probe_one").definition_error(map, 1, Fixture.unit_db()),
		"'cleared:probe_one' is the campaign's own record of a mission, not a fact a beat writes"
	)
	assert_eq(
		_writes(&"a flag with spaces").definition_error(map, 1, Fixture.unit_db()),
		"'a flag with spaces' is not an identifier"
	)
	assert_eq(_writes(HELD).definition_error(map, 1, Fixture.unit_db()), "")


# --- the names, against the war that writes them -------------------------------


## The failure this check exists for: a misspelled flag reads zero forever, so the
## variant line never speaks and nothing anywhere says a word. Only the whole
## campaign can catch it — the mission reading it is perfectly well formed, which
## is why neither its own `definition_error` nor `story_error` can.
func test_a_flag_no_mission_of_the_campaign_writes_is_refused() -> void:
	var campaign := _campaign()
	assert_eq(campaign.ledger_error(), "", "a campaign that reads nothing reads nothing wrong")

	var thanks := MissionLine.of(&"", "The Greenwater wardens hold our flank.")
	thanks.requires = _condition(HELD)
	campaign.missions[1].briefing = [MissionLine.of(&"", "Kestrel Pass."), thanks]
	assert_string_contains(campaign.ledger_error(), String(HELD))

	# Written *anywhere* in the campaign answers every read of it: a fact only an
	# optional mission writes is one the reader is meant to tolerate reading zero,
	# and what this refuses is a name nobody wrote rather than a road not taken.
	campaign.missions[0].events.append(_beat(&"the_town_holds", [_writes(HELD)]))
	assert_eq(campaign.ledger_error(), "")


func test_a_beat_gated_on_a_flag_nobody_writes_is_refused_too() -> void:
	var campaign := _campaign()
	var withdrawn: Array[MissionEffect] = [_garrison_withdrawn()]
	campaign.missions[1].events.append(_beat(&"the_garrison_leaves", withdrawn, _condition(SAVED)))
	assert_string_contains(campaign.ledger_error(), String(SAVED))
	campaign.missions[0].events.append(_beat(&"a_town_saved", [_writes(SAVED, 1, true)]))
	assert_eq(campaign.ledger_error(), "")


## The derived half, which is cheap and exact: the campaign answers `cleared:` and
## `stars:` off its own records, so a name about a mission it does not run is a
## fact it can never answer with anything but zero.
func test_a_derived_name_must_be_about_a_mission_the_campaign_runs() -> void:
	var campaign := _campaign()
	var line := MissionLine.of(&"", "Kestrel fell without us.")
	line.requires = _condition(&"cleared:probe_three")
	campaign.missions[1].briefing = [line]
	assert_string_contains(campaign.ledger_error(), "probe_three")
	line.requires = _condition(&"stars:probe_one")
	assert_eq(campaign.ledger_error(), "", "and a mission of its own needs no beat to write it")
