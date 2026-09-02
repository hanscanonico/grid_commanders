extends GutTest
## What the debrief says a clear was worth: the record the run was measured
## against, and the line printed off the two.
##
## `CampaignSession.record` copies the mission's record *before* `complete`
## improves it in place, and exposes the copy as `previous_record` — null on a
## first clear, dropped by `clear`. `CampaignDebriefPanel.worth_line` and
## `standing_line` are static and pure over an outcome, a record and a ledger, so
## the wording is pinned without the page. CampaignSession is an autoload; this
## suite earns the exception `test_campaign_session.gd` does.

const PROBE := &"__probe_debrief_report_campaign"
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


func _outcome(stars: int, day: int) -> MissionRuntime.Outcome:
	return MissionRuntime.Outcome.new(MissionRuntime.Status.SUCCESS, "", stars, [], day)


# --- the record before the run ---------------------------------------------------


func test_a_first_clear_was_measured_against_nothing() -> void:
	_play(_campaign(), PAR)
	assert_null(CampaignSession.previous_record(), "no record to beat")


func test_a_second_clear_exposes_the_first_runs_numbers() -> void:
	var campaign := _campaign()
	_play(campaign, PAR + 2)
	CampaignSession.clear()
	var progress := _play(campaign, PAR)
	var previous := CampaignSession.previous_record()
	assert_not_null(previous)
	assert_eq(previous.stars, 1, "the slow run missed the par star")
	assert_eq(previous.best_day, PAR + 2)
	var now: CampaignState.MissionRecord = progress.records[&"probe_one"]
	assert_eq(now.stars, 2, "and the record itself has moved on")
	assert_eq(now.best_day, PAR)


func test_the_record_before_is_a_copy() -> void:
	var campaign := _campaign()
	_play(campaign, PAR + 2)
	CampaignSession.clear()
	var progress := _play(campaign, PAR)
	var previous := CampaignSession.previous_record()
	var record: CampaignState.MissionRecord = progress.records[&"probe_one"]
	assert_false(previous == record, "not the record the ledger improves in place")
	record.stars = 3
	record.best_day = 1
	assert_eq(previous.stars, 1, "unchanged by a later write to the profile")
	assert_eq(previous.best_day, PAR + 2)


func test_clear_drops_the_record_before() -> void:
	var campaign := _campaign()
	_play(campaign, PAR + 2)
	CampaignSession.clear()
	_play(campaign, PAR)
	assert_not_null(CampaignSession.previous_record(), "the premise")
	CampaignSession.clear()
	assert_null(CampaignSession.previous_record())


# --- the line ----------------------------------------------------------------------


func test_a_first_clear_says_so() -> void:
	assert_eq(CampaignDebriefPanel.worth_line(_outcome(2, 5), null), "FIRST CLEAR")


func test_a_faster_clear_names_both_days() -> void:
	var previous := CampaignState.MissionRecord.new(1, 9)
	assert_eq(CampaignDebriefPanel.worth_line(_outcome(1, 6), previous), "BEST DAY 9 → 6")


func test_more_stars_name_both_counts() -> void:
	var previous := CampaignState.MissionRecord.new(1, 6)
	assert_eq(CampaignDebriefPanel.worth_line(_outcome(3, 8), previous), "★ 1 → 3")


func test_a_run_that_beat_the_record_on_both_says_both() -> void:
	var previous := CampaignState.MissionRecord.new(1, 9)
	assert_eq(
		CampaignDebriefPanel.worth_line(_outcome(3, 6), previous), "BEST DAY 9 → 6   ·   ★ 1 → 3"
	)


func test_a_run_no_better_than_the_record_says_no_change() -> void:
	var previous := CampaignState.MissionRecord.new(2, 5)
	assert_eq(CampaignDebriefPanel.worth_line(_outcome(2, 5), previous), "NO CHANGE")
	assert_eq(CampaignDebriefPanel.worth_line(_outcome(1, 7), previous), "NO CHANGE")


func test_the_standing_counts_what_the_route_offers() -> void:
	var campaign := _campaign()
	var progress := CampaignState.begin(campaign)
	progress.complete(campaign, &"probe_one", 2, PAR)
	assert_eq(
		CampaignDebriefPanel.standing_line(campaign, progress),
		"%s   1 / 2 · 2 ★" % String(PROBE).to_upper()
	)
