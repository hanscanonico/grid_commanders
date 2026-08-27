extends GutTest
## The pairing itself: when an event is due, the command that applies it, what
## the tally remembers about it across a save, and what the authoring gate
## refuses.
##
## Two properties carry the milestone. Triggers are a **conjunction**, which is
## what makes seven of them expressive — "did it, and did it fast" is two of
## them. And a `once` event fires exactly once **including across a reload**: the
## board does not remember having had a column landed on it, so the fired set is
## recorded in the mission's tally and saved with it.

const RIDGE := "res://maps/fixtures/ridge.txt"

const FIELD := """
[terrain]
CCQ...
....BF
[owners]
1 0 0
2 1 0
2 2 0
1 4 1
[units]
1 i 3 0 courier
2 t 4 0 siege_gun
2 i 5 0 garrison
1 p 3 1 truck
"""


func _state() -> GameState:
	return Fixture.state(FIELD)


func _map() -> MapData:
	return MapData.parse(FIELD, Fixture.terrain_db())


func _day(day: int) -> DayReachedTrigger:
	var trigger := DayReachedTrigger.new()
	trigger.day = day
	return trigger


func _hand_over(cell: Vector2i, team: int) -> SetOwnerEffect:
	var effect := SetOwnerEffect.new()
	effect.team = team
	effect.cells = [cell]
	return effect


func _land(cell: Vector2i, tag: StringName) -> SpawnUnitsEffect:
	var spawn := MissionSpawn.new()
	spawn.unit_type = Fixture.unit_db().by_symbol("t")
	spawn.cell = cell
	spawn.tag = tag
	var effect := SpawnUnitsEffect.new()
	effect.team = 2
	effect.units = [spawn]
	return effect


func _secret(cell: Vector2i, objective_id: StringName) -> CaptureCellObjective:
	var objective := CaptureCellObjective.new()
	objective.cell = cell
	objective.id = objective_id
	objective.hidden = true
	return objective


func _reveal(objective_id: StringName) -> RevealObjectiveEffect:
	var effect := RevealObjectiveEffect.new()
	effect.objective_id = objective_id
	return effect


func _event(id: StringName, triggers: Array[MissionTrigger]) -> MissionEvent:
	var event := MissionEvent.new()
	event.id = id
	event.triggers = triggers
	event.effects = [_hand_over(Vector2i(1, 0), 1)]
	return event


## A launchable mission on this board, for the authoring-gate cases.
func _mission() -> MissionDefinition:
	var mission := CampaignFixture.capture_mission(&"fixture", Vector2i(1, 0))
	mission.map_path = RIDGE
	return mission


# --- when an event is due ---------------------------------------------------


func test_every_trigger_has_to_hold() -> void:
	var state := _state()
	var progress := MissionProgress.new()
	var quick := DayBeforeTrigger.new()
	quick.day = 4
	var event := _event(&"quick_work", [_day(3), quick])
	assert_false(event.is_due(state, 1, progress), "day 1: only the second holds")
	state.day = 5
	assert_false(event.is_due(state, 1, progress), "day 5: only the first holds")
	state.day = 3
	assert_true(event.is_due(state, 1, progress), "day 3: both")


func test_a_once_event_is_due_only_until_it_has_fired() -> void:
	var state := _state()
	var progress := MissionProgress.new()
	var event := _event(&"iron_relief", [_day(1)])
	assert_true(event.is_due(state, 1, progress))
	progress.record_fired(event.id)
	assert_false(event.is_due(state, 1, progress), "it has already happened")


func test_a_repeating_event_stays_due() -> void:
	var event := _event(&"barrage", [_day(1)])
	event.once = false
	var progress := MissionProgress.new()
	progress.record_fired(event.id)
	assert_true(
		event.is_due(_state(), 1, progress), "a bombardment every day is authored, not a bug"
	)


# --- what a save remembers about it -----------------------------------------


func test_the_fired_and_revealed_sets_survive_a_save_and_a_resume() -> void:
	var missions: Array[MissionDefinition] = [CampaignFixture.mission(&"one")]
	var campaign := CampaignFixture.campaign(&"__probe_events", missions)
	var progress := CampaignState.begin(campaign)
	progress.active_mission = &"one"
	var tally := MissionProgress.new()
	tally.record_fired(&"iron_relief")
	tally.reveal(&"the_real_target")
	var data := CampaignSaveCodec.encode(progress, {"probe": true}, tally)
	assert_eq(CampaignSaveCodec.validate(data), "", "the flags are counters like any other")
	var back := CampaignSaveCodec.tally_of(data)
	assert_true(back.has_fired(&"iron_relief"), "a resumed mission does not land the column twice")
	assert_true(back.is_revealed(&"the_real_target"))
	assert_false(back.has_fired(&"something_else"))


func test_a_tally_refuses_a_flag_no_writer_could_have_produced() -> void:
	assert_ne(MissionProgress.tally_error({"fired:not an id": 1}), "")
	assert_ne(MissionProgress.tally_error({"revealed:": 1}), "")
	assert_eq(MissionProgress.tally_error({"fired:iron_relief": 1, "revealed:the_hq": 1}), "")


# --- the command ------------------------------------------------------------


func test_the_command_applies_every_effect_in_the_order_authored() -> void:
	var state := _state()
	var event := _event(&"the_gate", [_day(1)])
	event.effects = [_hand_over(Vector2i(1, 0), 1), _hand_over(Vector2i(1, 0), 2)]
	var command := MissionEventCommand.new(event, 1)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(state.owner_at(Vector2i(1, 0)), 2, "the last word is the last effect's")


func test_the_command_collects_what_the_effects_said_about_the_mission() -> void:
	var state := _state()
	var reveal := RevealObjectiveEffect.new()
	reveal.objective_id = &"the_real_target"
	var ending := EndMissionEffect.new()
	ending.reason = "The garrison opened the gate."
	var event := _event(&"the_turn", [_day(1)])
	event.effects = [reveal, ending]
	var command := MissionEventCommand.new(event, 1)
	command.apply(state)
	assert_eq(command.revealed.size(), 1)
	assert_eq(command.revealed[0], &"the_real_target")
	assert_eq(command.ending, ending, "the fact the runtime reads, not a verdict taken here")


func test_the_command_refuses_a_board_it_would_corrupt() -> void:
	var state := _state()
	var event := _event(&"iron_relief", [_day(1)])
	var spawn := SpawnUnitsEffect.new()
	spawn.team = 3
	var landing := MissionSpawn.new()
	landing.unit_type = Fixture.unit_db().by_symbol("t")
	landing.cell = Vector2i(0, 1)
	spawn.units = [landing]
	event.effects = [spawn]
	assert_ne(MissionEventCommand.new(event, 1).validate(state), "", "army 3 is not at this table")
	spawn.team = 2
	assert_eq(MissionEventCommand.new(event, 1).validate(state), "")


func test_the_command_refuses_a_match_that_is_already_decided() -> void:
	var state := _state()
	var event := _event(&"iron_relief", [_day(1)])
	state.eliminate(2)
	assert_ne(MissionEventCommand.new(event, 1).validate(state), "", "nobody is playing this board")


func test_the_command_refuses_an_event_that_does_nothing() -> void:
	var state := _state()
	var event := _event(&"empty", [_day(1)])
	event.effects = []
	assert_ne(MissionEventCommand.new(event, 1).validate(state), "")
	assert_ne(MissionEventCommand.new(null, 1).validate(state), "")


# --- the authoring gate -----------------------------------------------------


func test_a_mission_refuses_two_events_with_one_name() -> void:
	var mission := _mission()
	mission.events = [_event(&"iron_relief", [_day(3)]), _event(&"iron_relief", [_day(5)])]
	assert_ne(mission.definition_error(_map(), Fixture.unit_db()), "")
	mission.events[1].id = &"second_wave"
	assert_eq(mission.definition_error(_map(), Fixture.unit_db()), "")


func test_a_mission_refuses_an_event_that_waits_for_nothing() -> void:
	var mission := _mission()
	var event := _event(&"iron_relief", [_day(3)])
	event.triggers = []
	mission.events = [event]
	assert_ne(mission.definition_error(_map(), Fixture.unit_db()), "", "'at the opening' is day 1")
	event.triggers = [_day(1)]
	event.id = &"Iron Relief"
	assert_ne(mission.definition_error(_map(), Fixture.unit_db()), "", "a fired-set key is a name")


func test_a_mission_holds_an_events_conditions_to_its_own_board() -> void:
	var mission := _mission()
	var trigger := UnitDestroyedTrigger.new()
	trigger.tag = &"nobody"
	var event := _event(&"the_gun", [trigger])
	mission.events = [event]
	assert_ne(mission.definition_error(_map(), Fixture.unit_db()), "", "no unit carries that name")
	trigger.tag = &"siege_gun"
	assert_eq(mission.definition_error(_map(), Fixture.unit_db()), "")


func test_a_mission_pairs_every_hidden_objective_with_the_event_that_reveals_it() -> void:
	var mission := _mission()
	var secret := CaptureCellObjective.new()
	secret.cell = Vector2i(2, 0)
	secret.id = &"the_hq"
	secret.hidden = true
	mission.objectives.append(secret)
	assert_ne(mission.definition_error(_map(), Fixture.unit_db()), "", "nothing reveals it")
	var reveal := RevealObjectiveEffect.new()
	reveal.objective_id = &"the_wrong_one"
	var event := _event(&"the_turn", [_day(3)])
	event.effects = [reveal]
	mission.events = [event]
	assert_ne(
		mission.definition_error(_map(), Fixture.unit_db()), "", "and that names no objective"
	)
	reveal.objective_id = &"the_hq"
	assert_eq(mission.definition_error(_map(), Fixture.unit_db()), "")


func test_a_mission_refuses_two_beats_that_land_one_name() -> void:
	var mission := _mission()
	var first := _event(&"iron_relief", [_day(3)])
	first.effects = [_land(Vector2i(0, 1), &"relief")]
	var second := _event(&"second_wave", [_day(5)])
	second.effects = [_land(Vector2i(1, 1), &"relief")]
	mission.events = [first, second]
	assert_ne(
		mission.definition_error(_map(), Fixture.unit_db()),
		"",
		"a tag names one unit on a board, and the save refuses a board where it names two"
	)
	second.effects = [_land(Vector2i(1, 1), &"reserve")]
	assert_eq(mission.definition_error(_map(), Fixture.unit_db()), "")


func test_a_mission_refuses_a_beat_that_lands_a_name_the_board_already_carries() -> void:
	var mission := _mission()
	var event := _event(&"iron_relief", [_day(3)])
	event.effects = [_land(Vector2i(0, 1), &"courier")]
	mission.events = [event]
	assert_ne(
		mission.definition_error(_map(), Fixture.unit_db()),
		"",
		"the board stands a courier already"
	)


func test_a_repeating_beat_may_not_land_a_named_unit() -> void:
	var mission := _mission()
	var event := _event(&"barrage", [_day(3)])
	event.once = false
	event.effects = [_land(Vector2i(0, 1), &"relief")]
	mission.events = [event]
	assert_ne(
		mission.definition_error(_map(), Fixture.unit_db()),
		"",
		"a beat that repeats would land that name a second time"
	)
	event.effects = [_land(Vector2i(0, 1), &"")]
	assert_eq(
		mission.definition_error(_map(), Fixture.unit_db()), "", "an unnamed column may repeat"
	)


func test_a_mission_refuses_an_objective_id_no_save_could_key() -> void:
	var mission := _mission()
	var secret := _secret(Vector2i(2, 0), &"depot-1")
	mission.objectives.append(secret)
	var event := _event(&"the_turn", [_day(3)])
	event.effects = [_reveal(&"depot-1")]
	mission.events = [event]
	assert_ne(
		mission.definition_error(_map(), Fixture.unit_db()),
		"",
		"the revealed set is keyed by it, and the profile refuses a key it could not have written"
	)
	secret.id = &"the_depot"
	event.effects = [_reveal(&"the_depot")]
	assert_eq(mission.definition_error(_map(), Fixture.unit_db()), "")


func test_a_mission_refuses_two_objectives_with_one_id() -> void:
	var mission := _mission()
	var secret := _secret(Vector2i(2, 0), &"the_hq")
	var also := _secret(Vector2i(0, 0), &"the_hq")
	mission.objectives.append(secret)
	mission.objectives.append(also)
	var event := _event(&"the_turn", [_day(3)])
	event.effects = [_reveal(&"the_hq")]
	mission.events = [event]
	assert_ne(
		mission.definition_error(_map(), Fixture.unit_db()), "", "one reveal would bring both live"
	)
	also.id = &"the_depot"
	event.effects = [_reveal(&"the_hq"), _reveal(&"the_depot")]
	assert_eq(mission.definition_error(_map(), Fixture.unit_db()), "")


func test_a_mission_holds_an_events_lines_to_the_roster() -> void:
	var mission := _mission()
	var event := _event(&"the_turn", [_day(3)])
	event.lines = [MissionLine.of(&"nobody_at_all", "The wardens are yours.")]
	mission.events = [event]
	var db := Fixture.commander_db()
	assert_ne(mission.story_error(db), "", "a speaker who is not on the roster prints as a blank")
	event.lines = [MissionLine.of(&"ivar_thorne", "The wardens are yours.")]
	assert_eq(mission.story_error(db), "")
