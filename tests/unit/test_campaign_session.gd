extends GutTest
## The session's lifecycle across scene changes: armed by `begin`, silent for
## every skirmish, and emptied whole by `clear`.
##
## The gate for the whole campaign feature is that a match outside one is
## unchanged, and `clear` is where that was breakable: a session that kept its
## runtime after the player abandoned a mission would evaluate that mission's
## objectives against the next skirmish board, and a kept verdict would caption
## the next victory screen with a mission nobody was playing. Both are pinned
## here.
##
## CampaignSession is an autoload rather than a Node-free class, which is
## normally outside what tests/ targets. It earns MatchConfig's exception the
## same way: the singleton is up for the whole run and reachable without a
## scene, and its lifecycle is exactly what these tests are about.

const PROBE := &"__probe_session_campaign"
const FIRST_STEPS := "res://maps/first_steps.txt"

## Two cities and an HQ on one row; team 1 already owns (0,0), so a mission
## whose objective is that cell is decided by the first board it is asked about.
const ROW := """
[terrain]
CCQ.
[owners]
1 0 0
2 1 0
2 2 0
[units]
1 i 3 0
2 i 1 0
"""

## The same row with a third army, because a rout on a duel board is also a
## verdict: the fallen-army guard can only be read where somebody is still
## fighting.
const THREE_ARMIES := """
[terrain]
CCQ.
[owners]
1 0 0
2 1 0
3 2 0
[units]
1 i 3 0
2 i 1 0
3 i 2 0
"""

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	CampaignSession.clear()
	CampaignProfile.erase(PROBE)


func after_each() -> void:
	CampaignSession.clear()
	CampaignProfile.erase(PROBE)


func _campaign() -> CampaignDefinition:
	var missions: Array[MissionDefinition] = [CampaignFixture.capture_mission(&"probe_one")]
	return CampaignFixture.campaign(PROBE, missions)


func _state() -> GameState:
	var state := Fixture.state(ROW)
	assert_not_null(state)
	return state


func _begin(campaign: CampaignDefinition, resumed: MissionProgress = null) -> MatchRequest:
	return CampaignSession.begin(
		campaign, campaign.missions[0], CampaignState.begin(campaign), resumed
	)


## `campaign` with one scripted beat on it, due from day one and handing the
## enemy's city over.
func _with_a_beat(campaign: CampaignDefinition, id: StringName = &"the_gate_opens") -> MissionEvent:
	var trigger := DayReachedTrigger.new()
	trigger.day = 1
	var event := MissionEvent.new()
	event.id = id
	event.triggers = [trigger]
	event.effects = [_hand_over_to(1)]
	campaign.missions[0].events.append(event)
	return event


## The enemy's city handed to `team`.
func _hand_over_to(team: int) -> SetOwnerEffect:
	var effect := SetOwnerEffect.new()
	effect.team = team
	effect.cells = [Vector2i(1, 0)]
	return effect


## `_campaign` with a deadline on it the board below is past, so `decide` loses it.
func _doomed_campaign() -> CampaignDefinition:
	var campaign := _campaign()
	var deadline := DayDeadlineObjective.new()
	deadline.last_day = 2
	campaign.missions[0].failures.append(deadline)
	return campaign


## The mission lost, the way the live seam loses it: a mid-mission save on disk,
## a board past the deadline, the verdict taken and recorded.
func _lose(state: GameState) -> void:
	assert_true(CampaignSession.save_battle({"version": 8, "day": 3}))
	assert_false(CampaignProfile.load_battle(PROBE).is_empty(), "the attempt is on disk")
	state.day = 3
	assert_true(CampaignSession.decide(state))
	assert_eq(CampaignSession.outcome.status, MissionRuntime.Status.FAILURE)
	CampaignSession.record(state)


## One beat fired the way the live seam fires it: the command applies to the
## board and the session records what it did to the mission.
func _fire(state: GameState, event: MissionEvent) -> MissionEventCommand:
	var command := MissionEventCommand.new(event, 1)
	assert_eq(command.validate(state), "")
	command.apply(state)
	CampaignSession.record_event(command)
	return command


## The fixture is real: armed, the session decides the board its objective is
## already met on. Without this the clearing tests below would pass vacuously.
func test_an_armed_session_decides_the_board_its_objective_is_met_on() -> void:
	_begin(_campaign())
	assert_true(CampaignSession.decide(_state()))
	assert_eq(CampaignSession.outcome.status, MissionRuntime.Status.SUCCESS)


func test_a_cleared_session_decides_nothing_for_the_next_match() -> void:
	_begin(_campaign())
	CampaignSession.clear()
	assert_false(CampaignSession.decide(_state()), "an abandoned mission cannot end a skirmish")
	assert_null(CampaignSession.outcome, "and no verdict is left for the victory screen")


func test_clear_drops_a_decided_verdict_with_everything_else() -> void:
	_begin(_campaign())
	assert_true(CampaignSession.decide(_state()))
	CampaignSession.clear()
	assert_null(CampaignSession.outcome)
	assert_eq(CampaignSession.max_stars(), 0)
	assert_false(CampaignSession.decide(_state()))


# --- the scripted beats (campaign-depth CD3) -----------------------------------


func test_a_skirmish_is_due_no_beats_at_all() -> void:
	assert_true(CampaignSession.due_events(_state()).is_empty())
	assert_eq(CampaignSession.campaign_id(), &"", "and names no mission for a recording either")
	assert_eq(CampaignSession.mission_id(), &"")


## The whole of the once rule at this level: due, fired, recorded, and never due
## again — which is what stops a relief column landing at every boundary of the
## rest of the mission.
func test_a_fired_beat_is_never_due_again() -> void:
	var campaign := _campaign()
	var event := _with_a_beat(campaign)
	_begin(campaign)
	var state := _state()
	CampaignSession.open_board(state)
	assert_eq(CampaignSession.due_events(state), [event], "day one is what this beat waits for")
	_fire(state, event)
	assert_true(CampaignSession.tally.has_fired(&"the_gate_opens"))
	assert_true(CampaignSession.due_events(state).is_empty(), "and it has now happened")


## The resume, which is the reason the fired set is a saved counter rather than
## something derived from the board: the board does not remember having had a
## column landed on it, so a mission picked up again would land it a second time.
func test_a_beat_fired_before_a_save_does_not_fire_again_after_the_resume() -> void:
	var campaign := _campaign()
	var event := _with_a_beat(campaign)
	_begin(campaign)
	var state := _state()
	CampaignSession.open_board(state)
	_fire(state, event)
	assert_true(CampaignSession.save_battle(SaveCodec.encode(state, [2] as Array[int])))

	var resumed := CampaignProfile.load_in_progress(PROBE)
	CampaignSession.clear()
	_begin(campaign, resumed.tally)
	CampaignSession.open_board(state)
	assert_true(CampaignSession.tally.has_fired(&"the_gate_opens"), "the resume owes what it did")
	assert_true(CampaignSession.due_events(state).is_empty(), "so the column does not land twice")


## A beat that ends the mission is a `MissionRuntime` reason like any other
## (campaign-depth D3): the session collects it and the verdict taken at the same
## boundary reads it, precedence untouched.
func test_a_beat_that_ends_the_mission_ends_it_in_its_own_words() -> void:
	var campaign := _campaign()
	campaign.missions[0].objectives.clear()
	var ending := EndMissionEffect.new()
	ending.success = true
	ending.reason = "The relief column arrived."
	var event := _with_a_beat(campaign)
	event.effects = [ending]
	_begin(campaign)
	var state := _state()
	assert_false(CampaignSession.decide(state), "with nothing left to satisfy, nothing ends it")
	_fire(state, event)
	assert_true(CampaignSession.decide(state))
	assert_eq(CampaignSession.outcome.reason, "The relief column arrived.")


## A beat is not due once the mission is over, however many boundaries the scene
## still settles: a column landing on a decided board changes a match nobody is
## playing.
func test_a_decided_mission_is_due_no_further_beats() -> void:
	var campaign := _campaign()
	var event := _with_a_beat(campaign)
	_begin(campaign)
	var state := _state()
	assert_true(CampaignSession.decide(state), "the fixture objective is met at the opening")
	assert_true(CampaignSession.due_events(state).is_empty())
	assert_ne(event, null)


## The boundary a shot ends the match on. The mission has not been judged yet —
## `decide` runs after the beats — so the session is undecided and the beat's own
## triggers still hold, but `MissionEventCommand` refuses a decided board by
## design. Offering the beat there is asking for a refusal, and the live seam
## reports a refusal as an authoring fault.
func test_a_decided_match_is_due_no_beats_though_the_mission_is_still_unjudged() -> void:
	var campaign := _campaign()
	var event := _with_a_beat(campaign)
	_begin(campaign)
	var state := _state()
	assert_eq(CampaignSession.due_events(state), [event], "day one is what this beat waits for")
	state.eliminate(2)
	assert_ne(state.winner, 0, "the last rival is gone")
	assert_null(CampaignSession.outcome, "and the verdict has not been taken yet")
	assert_true(CampaignSession.due_events(state).is_empty())
	assert_ne(
		MissionEventCommand.new(event, 1).validate(state),
		"",
		"which is the refusal that would otherwise have been shouted about"
	)


## The boundary a rout empties a seat on, with the fight still running. Nothing
## strikes a `once` beat off the fired set but landing it, so a beat offered here
## would be refused, shouted about as an authoring fault, and offered again at
## every boundary left in the mission.
func test_a_beat_aimed_at_an_army_that_has_fallen_is_due_no_longer() -> void:
	var campaign := _campaign()
	var event := _with_a_beat(campaign)
	event.effects = [_hand_over_to(3)]
	_begin(campaign)
	var state := Fixture.state(THREE_ARMIES)
	assert_eq(CampaignSession.due_events(state), [event], "day one is what this beat waits for")
	state.eliminate(3)
	assert_eq(state.winner, 0, "two armies are left, so the match runs on")
	assert_true(CampaignSession.due_events(state).is_empty())
	assert_false(CampaignSession.tally.has_fired(&"the_gate_opens"), "and it never fired")
	assert_ne(
		MissionEventCommand.new(event, 1).validate(state),
		"",
		"which is the refusal that would otherwise be shouted at every boundary left"
	)


func test_save_battle_is_refused_outside_a_campaign() -> void:
	assert_false(CampaignSession.save_battle({"day": 1}))
	assert_null(CampaignProfile.load_progress(PROBE))


## The whole mid-mission loop: the save lands in the campaign's profile with the
## board embedded, and a request naming the campaign resumes exactly that board.
func test_a_saved_mission_resumes_from_the_campaign_profile() -> void:
	var campaign := _campaign()
	_begin(campaign)
	var map := MapData.load_from_file(FIRST_STEPS, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = FIRST_STEPS
	state.day = 12
	assert_true(CampaignSession.save_battle(SaveCodec.encode(state, [2] as Array[int])))
	var progress := CampaignProfile.load_progress(PROBE)
	assert_eq(progress.active_mission, &"probe_one", "the profile names the mission it holds")
	var request := MatchRequest.new()
	request.campaign_resume = PROBE
	var built := BattleSetup.build(request, terrain_db, unit_db, Fixture.commander_db())
	assert_not_null(built)
	assert_eq(built.game.day, 12, "the saved board, not day one of the mission")
	assert_eq(built.game.map_path, FIRST_STEPS)


# --- the developer override (`--unlock-missions`) ----------------------------


## The flagless case the one below is against: a won mission is recorded.
func test_a_won_mission_is_written_to_the_profile() -> void:
	_begin(_campaign())
	var state := _state()
	assert_true(CampaignSession.decide(state))
	CampaignSession.record(state)
	assert_not_null(CampaignProfile.load_progress(PROBE))


## A lost mission drops the board it was being kept with. The profile stays —
## the war is not forgotten — but the attempt is not on it, so the hub offers a
## fresh start rather than a resume of a board already lost.
func test_a_lost_mission_clears_the_profile_of_its_board() -> void:
	_begin(_doomed_campaign())
	_lose(_state())
	assert_true(CampaignProfile.load_battle(PROBE).is_empty(), "the lost board is dropped")
	var progress := CampaignProfile.load_progress(PROBE)
	assert_not_null(progress, "the profile itself stands")
	assert_eq(progress.active_mission, &"", "and names no mission in progress")
	assert_false(progress.is_cleared(&"probe_one"), "a loss clears nothing")


## The tally follows the board: a retry after a loss opens owing nothing, so a
## loss limit is spent only against the attempt being played.
func test_a_retry_after_a_loss_opens_with_no_losses() -> void:
	var campaign := _doomed_campaign()
	_begin(campaign)
	var state := _state()
	CampaignSession.open_board(state)
	state.remove_unit(state.units_of(1)[0])
	_lose(state)
	assert_eq(CampaignSession.tally.losses(), 1, "the lost attempt did cost a unit")
	assert_true(CampaignProfile.load_in_progress(PROBE).tally.is_empty(), "nothing to resume")
	CampaignSession.clear()
	_begin(campaign)
	assert_eq(CampaignSession.tally.losses(), 0)
	assert_true(CampaignSession.tally.is_empty())


## A resumed board is the tally's baseline, not its first command: the losses it
## owes are kept, and the first command's casualties are counted exactly once.
func test_a_resumed_board_baselines_before_the_first_command() -> void:
	_begin(_campaign(), MissionProgress.from_dict({"losses": 2}))
	var state := _state()
	CampaignSession.open_board(state)
	state.remove_unit(state.units_of(1)[0])
	assert_true(CampaignSession.decide(state))
	assert_eq(CampaignSession.tally.losses(), 3, "the two owed, plus the one this command cost")


## A mission won through the override banks nothing at all. Recording it would
## clear a mission the player may not have reached, which walks the route past
## every mission behind it and reads the war back as finished.
func test_a_mission_won_through_the_override_writes_nothing() -> void:
	var campaign := _campaign()
	var progress := CampaignState.begin(campaign)
	progress.unlock_all = true
	CampaignSession.begin(campaign, campaign.missions[0], progress)
	var state := _state()
	assert_true(CampaignSession.decide(state))
	CampaignSession.record(state)
	assert_null(CampaignProfile.load_progress(PROBE), "the win is not banked")
	assert_false(
		CampaignSession.save_battle(SaveCodec.encode(state, [2] as Array[int])),
		"and a mid-mission save is refused by the same door"
	)
	assert_null(CampaignProfile.load_progress(PROBE))


## A campaign resume with nothing to resume is a refusal, never a quiet fresh
## start: day one of the mission would look exactly like the resume working,
## with the player's half-played attempt silently gone.
func test_a_campaign_resume_with_no_snapshot_is_refused() -> void:
	var request := MatchRequest.new()
	request.campaign_resume = PROBE
	assert_null(BattleSetup.build(request, terrain_db, unit_db, Fixture.commander_db()))
	assert_push_error("holds no mission in progress")
