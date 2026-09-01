extends GutTest
## A loss is spoken like a win: `defeat` is a page of `MissionLine`s held to the
## bars the briefing and the victory page already clear, and a mission with none
## is refused before it ships silent.

const HELD := &"greenwater_held"


func _line(speaker: StringName, text: String, condition: FlagCondition = null) -> MissionLine:
	var line := MissionLine.of(speaker, text)
	line.requires = condition
	return line


func _condition(flag: StringName) -> FlagCondition:
	var condition := FlagCondition.new()
	condition.flag = flag
	condition.at_least = 1
	return condition


## A mission that clears every content bar but the one under test.
func _scripted() -> MissionDefinition:
	var mission := CampaignFixture.mission(&"probe_one")
	mission.events.append(MissionEvent.new())
	return mission


func test_a_mission_with_nothing_to_say_when_lost_is_refused() -> void:
	var mission := _scripted()
	assert_eq(
		mission.content_error(Fixture.commander_db()),
		"mission 'probe_one' has nothing to say when it is lost"
	)
	mission.defeat.append(_line(&"", "The road stayed shut."))
	assert_eq(mission.content_error(Fixture.commander_db()), "")


func test_a_defeat_line_needs_a_speaker_on_the_roster() -> void:
	var mission := CampaignFixture.mission(&"probe_one")
	mission.defeat.append(_line(&"nobody_at_all", "You paid the toll."))
	assert_string_contains(mission.story_error(Fixture.commander_db()), "not on the roster")


func test_a_narrated_defeat_line_is_spoken() -> void:
	var mission := CampaignFixture.mission(&"probe_one")
	mission.defeat.append(_line(&"", "The road stayed shut."))
	assert_eq(mission.story_error(Fixture.commander_db()), "")


func test_a_defeat_every_line_of_which_is_gated_is_refused() -> void:
	var mission := CampaignFixture.mission(&"probe_one")
	mission.defeat.append(_line(&"", "The relay fell with it.", _condition(HELD)))
	assert_string_contains(
		mission.story_error(Fixture.commander_db()), "one of them has to be the words"
	)
	mission.defeat.push_front(_line(&"", "The road stayed shut."))
	assert_eq(mission.story_error(Fixture.commander_db()), "", "an unconditional line rescues it")


func test_read_flags_names_the_fact_a_defeat_line_reads() -> void:
	var mission := CampaignFixture.mission(&"probe_one")
	mission.defeat.append(_line(&"", "The road stayed shut."))
	mission.defeat.append(_line(&"", "The relay fell with it.", _condition(HELD)))
	assert_has(mission.read_flags(), HELD)
