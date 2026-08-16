extends GutTest
## The authoring traps `make campaigns` refuses, on fixtures rather than on
## shipped content.
##
## Each one is a slip that leaves no mark anywhere a player or an author would
## look: the mission plays, the beat speaks, the page turns, and the thing the
## file said would happen simply does not. `test_campaign_content.gd` holds the
## 108 to the same bar; this is where each check is shown to catch what it claims
## and to leave the honest shape alone.

const HELD := &"greenwater_held"
## Two seats, an HQ each and a city between them, so a board question has a home
## headquarters to ask after.
const BOARD := """
[terrain]
Q.C.Q
.....
[owners]
1 0 0
2 4 0
[units]
1 i 0 1
2 i 4 1
"""
## The same board with a third army on it, so felling one enemy leaves another.
const THREE_SEAT_BOARD := """
[terrain]
Q.C.Q
..Q..
.....
[owners]
1 0 0
2 4 0
3 2 1
[units]
1 i 0 2
2 i 4 2
3 i 2 2
"""


func _mission(id: StringName = &"probe_one") -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.id = id
	mission.title = String(id)
	mission.map_path = "res://maps/first_steps.txt"
	mission.player_team = 1
	return mission


func _campaign(ids: Array = [&"one", &"two"]) -> CampaignDefinition:
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


## A beat on `mission` writing `flag`, waiting for whatever it is handed.
func _writes(mission: MissionDefinition, flag: StringName, trigger: MissionTrigger) -> void:
	var effect := SetFlagEffect.new()
	effect.flag = flag
	effect.value = 1
	var event := MissionEvent.new()
	event.id = &"writes_it"
	event.effects.append(effect)
	event.triggers.append(trigger)
	mission.events.append(event)


func _on_day(day: int) -> DayReachedTrigger:
	var trigger := DayReachedTrigger.new()
	trigger.day = day
	return trigger


## A beat waiting for ground the player has to take, which is the shape of a fact
## that reads two ways.
func _on_the_relay() -> CellOwnedTrigger:
	var trigger := CellOwnedTrigger.new()
	trigger.cell = Vector2i(2, 0)
	trigger.holder = CellOwnedTrigger.Holder.OURS
	return trigger


func _capture(cell: Vector2i) -> CaptureCellObjective:
	var objective := CaptureCellObjective.new()
	objective.cell = cell
	objective.text = "Take %s." % cell
	return objective


# --- a fact nothing can vary ------------------------------------------------


func test_a_fact_only_the_calendar_writes_is_refused_where_something_reads_it() -> void:
	var campaign := _campaign()
	campaign.missions[0].par_day = 5
	_writes(campaign.missions[0], HELD, _on_day(3))
	campaign.missions[1].unlock_requires = _condition(HELD)
	assert_string_contains(campaign.constant_fact_error(), "reads the same on every route")


func test_a_fact_the_board_decides_is_a_consequence() -> void:
	var campaign := _campaign()
	_writes(campaign.missions[0], HELD, _on_the_relay())
	campaign.missions[1].unlock_requires = _condition(HELD)
	assert_eq(campaign.constant_fact_error(), "")


## Past par the beat is one a player who is quick genuinely avoids, which is how
## the ledger records "was careful" rather than only "went wrong".
func test_a_beat_past_the_missions_own_par_still_varies() -> void:
	var campaign := _campaign()
	campaign.missions[0].par_day = 5
	_writes(campaign.missions[0], HELD, _on_day(7))
	campaign.missions[1].unlock_requires = _condition(HELD)
	assert_eq(campaign.constant_fact_error(), "")


## `ledger_error`'s rule at this width: a road the player may decline is the
## ordinary shape of a fact that sometimes goes unwritten.
func test_a_beat_on_a_gated_mission_varies_whatever_it_waits_for() -> void:
	var campaign := _campaign([&"one", &"two", &"three"])
	_writes(campaign.missions[0], &"first_fact", _on_the_relay())
	campaign.missions[1].unlock_requires = _condition(&"first_fact")
	campaign.missions[1].par_day = 5
	_writes(campaign.missions[1], HELD, _on_day(1))
	campaign.missions[2].unlock_requires = _condition(HELD)
	assert_eq(campaign.constant_fact_error(), "")


## A fact nobody conditions anything on is a note in the ledger, which is allowed
## to be true of every run.
func test_a_fact_nothing_reads_is_left_alone() -> void:
	var campaign := _campaign()
	campaign.missions[0].par_day = 5
	_writes(campaign.missions[0], HELD, _on_day(1))
	assert_eq(campaign.constant_fact_error(), "")


# --- a block closed by a mission not everybody plays -------------------------


func test_a_gated_mission_may_not_close_a_block_that_has_a_page() -> void:
	var campaign := _campaign()
	campaign.block_titles = ["Spring"]
	campaign.block_lengths = [2]
	var page := CampaignInterlude.new()
	page.after_block = 0
	page.title = "Spring"
	campaign.interludes.append(page)
	_writes(campaign.missions[0], HELD, _on_the_relay())
	campaign.missions[1].unlock_requires = _condition(HELD)
	assert_string_contains(campaign.block_error(), "closes block 0")


func test_a_gated_mission_inside_a_block_is_fine() -> void:
	var campaign := _campaign([&"one", &"two", &"three"])
	campaign.block_titles = ["Spring"]
	campaign.block_lengths = [3]
	var page := CampaignInterlude.new()
	page.after_block = 0
	page.title = "Spring"
	campaign.interludes.append(page)
	_writes(campaign.missions[0], HELD, _on_the_relay())
	campaign.missions[1].unlock_requires = _condition(HELD)
	assert_eq(campaign.block_error(), "")


# --- the board a mission opens on -------------------------------------------


func test_a_mission_already_won_before_the_first_command_is_refused() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(0, 0)))
	assert_string_contains(
		mission.board_error(Fixture.state(BOARD)), "already over on the board it opens on"
	)


func test_a_mission_still_to_be_played_passes() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(2, 0)))
	assert_eq(mission.board_error(Fixture.state(BOARD)), "")


## Tactical victory outranks the objective list, so taking the last enemy's home
## headquarters wins the mission with everything beside it still unticked.
func test_an_objective_beside_a_match_ending_one_is_refused() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(4, 0)))
	mission.objectives.append(_capture(Vector2i(2, 0)))
	assert_string_contains(mission.board_error(Fixture.state(BOARD)), "ends the match")


func test_a_match_ending_objective_on_its_own_is_the_mission() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(4, 0)))
	assert_eq(mission.board_error(Fixture.state(BOARD)), "")


## Felling one army of two enemies resolves nothing, so the objective beside it
## is judged exactly as it reads.
func test_a_headquarters_that_leaves_another_enemy_standing_ends_nothing() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(4, 0)))
	mission.objectives.append(_capture(Vector2i(2, 0)))
	assert_eq(mission.board_error(Fixture.state(THREE_SEAT_BOARD)), "")


# --- a page that can render with no words -----------------------------------


func _line(text: String, condition: FlagCondition = null) -> MissionLine:
	var line := MissionLine.of(&"", text)
	line.requires = condition
	return line


func test_a_briefing_every_line_of_which_is_gated_is_refused() -> void:
	var mission := _mission()
	mission.briefing.append(_line("The relay held.", _condition(HELD)))
	mission.briefing.append(_line("The relay fell.", _condition(HELD, 0, 0)))
	assert_string_contains(
		mission.story_error(Fixture.commander_db()), "one of them has to be the words"
	)


func test_a_briefing_with_one_line_every_player_hears_is_fine() -> void:
	var mission := _mission()
	mission.briefing.append(_line("Move on the relay at dawn."))
	mission.briefing.append(_line("The relay held.", _condition(HELD)))
	assert_eq(mission.story_error(Fixture.commander_db()), "")


## The debrief is asked on its own, so an unconditional briefing cannot vouch for
## a victory page that every route can leave empty.
func test_an_all_gated_debrief_beside_a_plain_briefing_is_refused() -> void:
	var mission := _mission()
	mission.briefing.append(_line("Move on the relay at dawn."))
	mission.victory.append(_line("And it held.", _condition(HELD)))
	assert_string_contains(
		mission.story_error(Fixture.commander_db()), "one of them has to be the words"
	)


func test_an_interlude_every_line_of_which_is_gated_is_refused() -> void:
	var page := CampaignInterlude.new()
	page.after_block = 0
	page.title = "Spring"
	page.lines.append(_line("The relay held.", _condition(HELD)))
	assert_string_contains(
		page.definition_error(Fixture.commander_db()), "one of them has to be the words"
	)


# --- content somebody meant to write ----------------------------------------
#
# One test per authority rather than per bar: this file sits at the repo's
# max-public-methods ceiling, and a bar that stopped firing still names itself in
# the assert that catches it.


func _deadline(last_day: int) -> DayDeadlineObjective:
	var deadline := DayDeadlineObjective.new()
	deadline.last_day = last_day
	return deadline


## A mission that clears every content bar, which each assert below then breaks
## exactly one of.
func _authored() -> MissionDefinition:
	var mission := _mission()
	_writes(mission, HELD, _on_day(1))
	mission.commanders = {1: &"tomas_reed"}
	mission.briefing.append(_line("Move on the relay at dawn."))
	mission.victory.append(_line("And it held."))
	mission.par_day = 4
	mission.failures.append(_deadline(6))
	return mission


func test_a_mission_somebody_authored_clears_every_content_bar() -> void:
	assert_eq(_authored().content_error(Fixture.commander_db()), "")
	var on_the_last_day := _authored()
	on_the_last_day.par_day = 6
	assert_eq(
		on_the_last_day.content_error(Fixture.commander_db()),
		"",
		"par on the deadline's own last day is still earnable"
	)


func test_every_content_bar_names_what_the_mission_is_missing() -> void:
	var db := Fixture.commander_db()
	var unscripted := _authored()
	unscripted.events.clear()
	assert_string_contains(unscripted.content_error(db), "scripts nothing")
	var silent := _authored()
	silent.victory.clear()
	assert_string_contains(silent.content_error(db), "nothing to say when it is won")
	var miscast := _authored()
	miscast.commanders = {2: &"nobody_at_all"}
	assert_string_contains(miscast.content_error(db), "not on the roster")
	var deadline_as_goal := _authored()
	deadline_as_goal.objectives.append(_deadline(6))
	assert_string_contains(deadline_as_goal.content_error(db), "files a deadline as a goal")
	var deadline_as_star := _authored()
	deadline_as_star.bonus_objectives.append(_deadline(6))
	assert_string_contains(
		deadline_as_star.content_error(db), "files a deadline as a goal", "a bonus reads the same"
	)
	var slow_par := _authored()
	slow_par.par_day = 9
	assert_string_contains(slow_par.content_error(db), "past its own deadline")


# --- a goal that costs nothing ----------------------------------------------


func _own(count: int) -> OwnPropertiesObjective:
	var objective := OwnPropertiesObjective.new()
	objective.count = count
	objective.text = "Hold %d properties." % count
	return objective


## The player opens holding their own headquarters, so a one-property goal is a
## free checkmark — on either list, and with the mission not over either way.
func test_a_goal_already_met_at_deploy_is_refused() -> void:
	var primary := _mission()
	primary.objectives.append(_capture(Vector2i(2, 0)))
	primary.objectives.append(_own(1))
	assert_string_contains(
		primary.board_error(Fixture.state(BOARD)), "is met before the first command"
	)
	var bonus := _mission()
	bonus.objectives.append(_capture(Vector2i(2, 0)))
	bonus.bonus_objectives.append(_own(1))
	assert_string_contains(
		bonus.board_error(Fixture.state(BOARD)), "is met before the first command", "a star too"
	)


## The two goals that open true by design: a hidden one is not judged until a
## beat reveals it, and "keep the marshal in the field" is the one goal that can
## fall back false.
func test_a_goal_that_opens_true_by_design_is_left_alone() -> void:
	var hidden := _mission()
	hidden.objectives.append(_capture(Vector2i(2, 0)))
	var prize := _own(1)
	prize.hidden = true
	prize.id = &"the_quiet_prize"
	hidden.bonus_objectives.append(prize)
	assert_eq(hidden.board_error(Fixture.state(BOARD)), "")
	var escort := _mission()
	escort.objectives.append(_capture(Vector2i(2, 0)))
	var ally := AllySurvivesObjective.new()
	ally.team = 2
	ally.text = "Keep the marshal in the field."
	escort.objectives.append(ally)
	assert_eq(escort.board_error(Fixture.state(BOARD)), "")


# --- a war told in narration -------------------------------------------------


func _speaks(mission: MissionDefinition, speaker: StringName, lines: int) -> void:
	for i in lines:
		var line := _line("Line %d." % i)
		line.speaker = speaker
		mission.briefing.append(line)


func test_a_campaign_more_narrated_than_spoken_is_refused() -> void:
	var campaign := _campaign()
	_speaks(campaign.missions[0], &"tomas_reed", 1)
	_speaks(campaign.missions[1], &"", 2)
	assert_string_contains(campaign.speech_error(), "only 1 of 3 story lines have a speaker")


## And a war with no story lines at all is a ratio with no denominator rather
## than a war told in narration.
func test_a_campaign_mostly_spoken_is_fine() -> void:
	var campaign := _campaign()
	_speaks(campaign.missions[0], &"tomas_reed", 2)
	_speaks(campaign.missions[1], &"", 1)
	assert_eq(campaign.speech_error(), "")
	assert_eq(_campaign().speech_error(), "", "and a war that says nothing is not judged")
