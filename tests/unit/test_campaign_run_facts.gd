extends GutTest
## The run's own facts: what the mission just played says about itself —
## stars, par, losses, first clear, new best, how it was lost — placed on the
## profile under `run:` so a victory or defeat line reads them through the one
## condition vocabulary authors already have.
##
## Three things are pinned. They are read through `flag` and named through
## `flag_name_error` like any fact. `CampaignSession.record` writes them on a win
## and on a loss, against the record as it stood *before* the run, and `begin`
## and `clear` drop them. And they never leave the session: the codec does not
## store them, and the content gate refuses them anywhere but a victory line.
##
## CampaignSession is an autoload; this suite earns the exception
## `test_campaign_session.gd` does, for the same lifecycle reason.

const PROBE := &"__probe_run_facts_campaign"
const PAR := 3

## Team 1 already owns (0,0), so the fixture objective is met on the first board
## the session is asked about; team 2 keeps a second unit so nothing routs it.
const ROW := """
[terrain]
CCQ..
[owners]
1 0 0
2 1 0
2 2 0
[units]
1 i 3 0
2 i 1 0
2 i 4 0
"""


func before_each() -> void:
	CampaignSession.clear()
	CampaignProfile.erase(PROBE)


func after_each() -> void:
	CampaignSession.clear()
	CampaignProfile.erase(PROBE)


func _campaign() -> CampaignDefinition:
	var mission := CampaignFixture.capture_mission(&"probe_one")
	mission.par_day = PAR
	var missions: Array[MissionDefinition] = [
		mission, CampaignFixture.capture_mission(&"probe_two")
	]
	return CampaignFixture.campaign(PROBE, missions)


func _condition(flag: StringName, at_least := 1, at_most := -1) -> FlagCondition:
	var condition := FlagCondition.new()
	condition.flag = flag
	condition.at_least = at_least
	condition.at_most = at_most
	return condition


func _line(flag: StringName) -> MissionLine:
	var line := MissionLine.of(&"", "Said only on one kind of run.")
	line.requires = _condition(flag)
	return line


func _deadline(last_day: int) -> DayDeadlineObjective:
	var objective := DayDeadlineObjective.new()
	objective.last_day = last_day
	objective.text = "The relay went dark."
	return objective


## The profile on disk, or the fresh one a first opening begins.
func _progress(campaign: CampaignDefinition) -> CampaignState:
	var loaded := CampaignProfile.load_progress(PROBE)
	return loaded if loaded != null else CampaignState.begin(campaign)


## A whole mission played to its verdict on `day`: begin, decide, record.
func _play(campaign: CampaignDefinition, day: int) -> CampaignState:
	var state := Fixture.state(ROW)
	state.day = day
	CampaignSession.begin(campaign, campaign.missions[0], _progress(campaign))
	CampaignSession.open_board(state)
	assert_true(CampaignSession.decide(state), "the fixture is decided on its opening board")
	CampaignSession.record(state)
	return CampaignSession.progress


# --- the name and the read -----------------------------------------------------


func test_a_run_fact_is_read_off_the_run_and_not_the_ledger() -> void:
	var state := CampaignState.begin(_campaign())
	assert_eq(state.flag(&"run:par"), 0, "nothing recorded yet")
	state.run[&"run:par"] = 1
	assert_eq(state.flag(&"run:par"), 1)
	state.flags[&"run:par"] = 0
	assert_eq(state.flag(&"run:par"), 1, "a stored copy could never answer for it")


func test_only_the_nine_facts_a_run_records_may_be_named() -> void:
	assert_eq(CampaignState.flag_name_error(&"run:par"), "")
	assert_eq(CampaignState.flag_name_error(&"run:nope"), "'run:nope' is not a fact a run records")
	for name: StringName in CampaignState.RUN_FACTS:
		assert_eq(CampaignState.flag_name_error(name), "", String(name))
	assert_eq(CampaignState.RUN_FACTS.size(), 9)


func test_a_run_fact_is_derived_and_about_no_mission() -> void:
	assert_true(CampaignState.is_derived(&"run:par"), "so a beat cannot write one")
	assert_true(CampaignState.is_run_fact(&"run:par"))
	assert_false(CampaignState.is_run_fact(&"stars:probe_one"))
	assert_eq(CampaignState.derived_mission(&"run:par"), &"", "'par' is not a mission id")
	assert_eq(CampaignState.derived_mission(&"stars:probe_one"), &"probe_one", "and that still is")


# --- the write ------------------------------------------------------------------


func test_a_first_clear_inside_par_is_first_and_not_best() -> void:
	var progress := _play(_campaign(), PAR)
	assert_eq(progress.flag(&"run:par"), 1)
	assert_eq(progress.flag(&"run:first"), 1)
	assert_eq(progress.flag(&"run:best"), 0, "there was no record to beat")
	assert_eq(progress.flag(&"run:stars"), 2)
	assert_eq(progress.flag(&"run:full"), 1)
	assert_eq(progress.flag(&"run:day"), PAR)
	assert_eq(progress.flag(&"run:losses"), 0)
	assert_eq(progress.flag(&"run:cause"), MissionRuntime.Cause.NONE)
	assert_eq(progress.flag(&"run:failure"), 0)


func test_a_faster_replay_is_best_and_not_first() -> void:
	var campaign := _campaign()
	var slow := _play(campaign, PAR + 2)
	assert_eq(slow.flag(&"run:par"), 0)
	assert_eq(slow.flag(&"run:full"), 0, "the par star was missed")
	assert_eq(slow.flag(&"run:first"), 1)
	CampaignSession.clear()
	var fast := _play(campaign, PAR)
	assert_eq(fast.flag(&"run:first"), 0, "the ledger took the first run")
	assert_eq(fast.flag(&"run:best"), 1, "two stars over one, and day 3 over day 5")
	assert_eq(fast.flag(&"run:par"), 1)


func test_a_replay_no_better_than_the_record_is_neither() -> void:
	var campaign := _campaign()
	_play(campaign, PAR)
	CampaignSession.clear()
	var again := _play(campaign, PAR)
	assert_eq(again.flag(&"run:first"), 0)
	assert_eq(again.flag(&"run:best"), 0)


func test_a_loss_records_its_cause_and_none_of_the_winning_facts() -> void:
	var campaign := _campaign()
	campaign.missions[0].failures.append(_deadline(2))
	var progress := _play(campaign, 3)
	assert_eq(CampaignSession.outcome.status, MissionRuntime.Status.FAILURE)
	assert_eq(progress.flag(&"run:cause"), MissionRuntime.Cause.FAILURE)
	assert_eq(progress.flag(&"run:failure"), 1)
	assert_eq(progress.flag(&"run:day"), 3, "a defeat line can say which day it was lost on")
	assert_eq(progress.flag(&"run:stars"), 0)
	assert_eq(progress.flag(&"run:par"), 0, "a loss on day 3 is not inside par 3")
	assert_eq(progress.flag(&"run:first"), 0)
	assert_eq(progress.flag(&"run:best"), 0)


func test_begin_and_clear_both_drop_the_run() -> void:
	var campaign := _campaign()
	var progress := _play(campaign, PAR)
	assert_false(progress.run.is_empty(), "the premise")
	CampaignSession.begin(campaign, campaign.missions[1], progress)
	assert_true(progress.run.is_empty(), "the next mission opens on no run")
	progress.run[&"run:stars"] = 2
	CampaignSession.clear()
	assert_true(progress.run.is_empty(), "and the profile the menu keeps carries none")


## The reason the facts exist: a victory line conditioned on one is said on the
## run it was written for and on no other.
func test_a_victory_line_reads_the_run() -> void:
	var campaign := _campaign()
	var lines: Array[MissionLine] = [_line(&"run:full")]
	var full := _play(campaign, PAR)
	assert_eq(MissionLine.spoken(lines, full), lines)
	CampaignSession.clear()
	var late := _play(campaign, PAR + 2)
	assert_true(MissionLine.spoken(lines, late).is_empty())


# --- never stored, never misplaced ----------------------------------------------


func test_the_codec_drops_the_run() -> void:
	var state := CampaignState.begin(_campaign())
	state.run[&"run:stars"] = 2
	var data := CampaignSaveCodec.encode(state)
	assert_false(data.has("run"))
	assert_true((data["flags"] as Dictionary).is_empty())
	var decoded := CampaignSaveCodec.decode(data)
	assert_not_null(decoded)
	assert_true(decoded.run.is_empty())
	assert_eq(decoded.flag(&"run:stars"), 0)


func test_a_victory_line_may_read_a_run_fact() -> void:
	var campaign := _campaign()
	campaign.missions[0].victory.append(_line(&"run:stars"))
	assert_eq(campaign.run_fact_error(), "")
	assert_eq(campaign.ledger_error(), "")


func test_a_briefing_line_may_not() -> void:
	var campaign := _campaign()
	campaign.missions[0].briefing.append(_line(&"run:stars"))
	var expected := (
		"campaign '%s': mission 'probe_one' reads 'run:stars', which only a victory or defeat line can"
		% PROBE
	)
	assert_eq(campaign.run_fact_error(), expected)
	assert_eq(campaign.ledger_error(), expected, "and the gate asks it there")


func test_a_gate_a_trigger_and_an_interlude_may_not_either() -> void:
	var gated := _campaign()
	gated.missions[1].unlock_requires = _condition(&"run:full")
	assert_ne(gated.run_fact_error(), "")

	var triggered := _campaign()
	var trigger := FlagTrigger.new()
	trigger.condition = _condition(&"run:best")
	var event := MissionEvent.new()
	event.id = &"the_best_beat"
	event.triggers = [trigger]
	triggered.missions[0].events.append(event)
	assert_ne(triggered.run_fact_error(), "")

	var paged := _campaign()
	paged.block_titles = ["One"]
	paged.block_lengths = [2]
	var page := CampaignInterlude.new()
	page.after_block = 0
	page.lines.append(_line(&"run:losses"))
	paged.interludes.append(page)
	assert_eq(
		paged.run_fact_error(),
		(
			(
				"campaign '%s': the interlude after block 0 reads 'run:losses', "
				+ "which only a victory or defeat line can"
			)
			% PROBE
		)
	)
