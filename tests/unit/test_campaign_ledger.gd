extends GutTest
## The consequence ledger (campaign-depth D5): the named facts one mission writes
## and a later one reads.
##
## The rules worth pinning are the ones a player would notice going wrong. A
## mission that went badly and was retried must write the war once, not once per
## attempt, and the debrief must report what was *committed* rather than what was
## staged. And a flag must reach the next mission by choosing what is *used* — a
## briefing line, whether a beat happens — never by moving a number: the last test
## here is that a fact written to the ledger leaves the board it was written on
## byte-for-byte where it was, which is also why the ledger can never break a
## replay.
##
## What may name a fact, what a profile may carry it in, and the campaign-wide
## check that every name is one the war writes are `test_campaign_ledger_names.gd`'s.

const PROBE := &"__probe_ledger_campaign"
const HELD := &"greenwater_held"
const SAVED := &"towns_saved"

## Two cities and an HQ on one row. Team 1 already owns (0,0), so a mission whose
## objective is that cell is won on the first board it is asked about, and army 2
## fields a named garrison plus a second unit — so taking the garrison off is a
## board that opens differently rather than an army that has been routed.
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


func before_each() -> void:
	CampaignSession.clear()
	CampaignProfile.erase(PROBE)


func after_each() -> void:
	CampaignSession.clear()
	CampaignProfile.erase(PROBE)


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


## One beat fired the way the live seam fires it: the command applies to the
## board and the session records what it did to the mission.
func _fire(state: GameState, event: MissionEvent) -> void:
	var command := MissionEventCommand.new(event, 1)
	assert_eq(command.validate(state), "")
	command.apply(state)
	CampaignSession.record_event(command)


## The profile on disk, or the fresh one a first opening begins.
func _progress(campaign: CampaignDefinition) -> CampaignState:
	var loaded := CampaignProfile.load_progress(PROBE)
	return loaded if loaded != null else CampaignState.begin(campaign)


## A whole mission played to the verdict its fixture objective is already at:
## begin, fire the beats the opening board is due, decide, record.
func _play(campaign: CampaignDefinition, mission: MissionDefinition, state: GameState) -> void:
	CampaignSession.begin(campaign, mission, _progress(campaign))
	CampaignSession.open_board(state)
	for event: MissionEvent in CampaignSession.due_events(state):
		_fire(state, event)
	assert_true(CampaignSession.decide(state), "the fixture objective is met at the opening")
	CampaignSession.record(state)


# --- the condition -------------------------------------------------------------


func test_a_condition_reads_both_bounds() -> void:
	var state := CampaignState.begin(_campaign())
	state.flags[SAVED] = 3
	assert_true(_condition(SAVED).holds(state), "at least one town")
	assert_true(_condition(SAVED, 3).holds(state))
	assert_false(_condition(SAVED, 4).holds(state))
	# The half this milestone exists for: a war that can only record what went
	# wrong is a war that can only get worse.
	assert_true(_condition(SAVED, 0, 3).holds(state), "no more than three")
	assert_false(_condition(SAVED, 0, 2).holds(state))
	assert_true(_condition(SAVED, 2, 4).holds(state), "and between the two")


func test_a_condition_outside_a_campaign_reads_every_fact_as_zero() -> void:
	assert_false(_condition(HELD).holds(null))
	assert_true(_condition(HELD, 0, 0).holds(null), "nothing held is a fact of its own")


func test_a_band_nothing_can_hold_is_refused() -> void:
	assert_ne(_condition(HELD, 3, 2).definition_error(), "")
	assert_ne(_condition(&"").definition_error(), "")
	assert_eq(_condition(HELD, 1, 3).definition_error(), "")


# --- writing it ----------------------------------------------------------------


func test_a_beat_writes_the_war_when_the_mission_is_finished() -> void:
	var campaign := _campaign()
	campaign.missions[0].events.append(_beat(&"the_town_holds", [_writes(HELD)]))
	_play(campaign, campaign.missions[0], Fixture.state(ROW))
	var progress := CampaignProfile.load_progress(PROBE)
	assert_eq(progress.flag(HELD), 1, "and it is on disk, not only in memory")


## The two ways an attempt ends without finishing the mission. Both leave the war
## as it was, which is what makes the beat's own fact safe to write again on the
## next attempt.
func test_nothing_is_written_until_the_mission_is_finished() -> void:
	var campaign := _campaign()
	var mission := campaign.missions[0]
	mission.events.append(_beat(&"the_town_holds", [_writes(HELD)]))

	var lost := Fixture.state(ROW)
	CampaignSession.begin(campaign, mission, CampaignState.begin(campaign))
	CampaignSession.open_board(lost)
	_fire(lost, mission.events[0])
	lost.eliminate(1)
	assert_true(CampaignSession.decide(lost))
	assert_eq(CampaignSession.outcome.status, MissionRuntime.Status.FAILURE)
	CampaignSession.record(lost)
	assert_eq(CampaignProfile.load_progress(PROBE).flag(HELD), 0, "a mission lost is not the war")

	# Walking away from the battle: the session is emptied without a verdict, the
	# way `MenuCampaignFlow.resume` empties it for a player who left.
	var abandoned := Fixture.state(ROW)
	CampaignSession.begin(campaign, mission, CampaignState.begin(campaign))
	CampaignSession.open_board(abandoned)
	_fire(abandoned, mission.events[0])
	var progress := CampaignSession.progress
	CampaignSession.clear()
	assert_eq(progress.flag(HELD), 0, "and neither is one walked away from")


## The two ways a mission is played twice, and a fact that counts up is where
## either would show: the failed attempt banks nothing, and the war is recorded
## the first time the mission is actually finished.
func test_a_mission_played_twice_counts_a_fact_once() -> void:
	var campaign := _campaign()
	var mission := campaign.missions[0]
	mission.events.append(_beat(&"a_town_saved", [_writes(SAVED, 1, true)]))

	var lost := Fixture.state(ROW)
	CampaignSession.begin(campaign, mission, CampaignState.begin(campaign))
	CampaignSession.open_board(lost)
	_fire(lost, mission.events[0])
	lost.eliminate(1)
	assert_true(CampaignSession.decide(lost))
	CampaignSession.record(lost)

	_play(campaign, mission, Fixture.state(ROW))
	assert_eq(CampaignProfile.load_progress(PROBE).flag(SAVED), 1, "the run that stood, once")
	_play(campaign, mission, Fixture.state(ROW))
	assert_eq(
		CampaignProfile.load_progress(PROBE).flag(SAVED),
		1,
		"and a replay is for stars: the war already happened and later missions read it"
	)


## The debrief reports what was **committed**, never what was staged. One fact
## assigned and one counted up, because a replay writes neither and the screen has
## to be as quiet about the counter as about the assignment.
func test_a_replay_reports_nothing_because_it_recorded_nothing() -> void:
	var campaign := _campaign()
	var mission := campaign.missions[0]
	mission.events.append(_beat(&"the_town_holds", [_writes(HELD)]))
	mission.events.append(_beat(&"a_town_saved", [_writes(SAVED, 1, true)]))

	_play(campaign, mission, Fixture.state(ROW))
	assert_eq(CampaignSession.recorded_notes().size(), 2, "the run that wrote the war says so")
	var written := CampaignProfile.load_progress(PROBE)
	assert_eq(written.flag(HELD), 1)
	assert_eq(written.flag(SAVED), 1)

	_play(campaign, mission, Fixture.state(ROW))
	assert_eq(
		CampaignSession.recorded_notes(),
		[] as Array[String],
		"and the replay of it says nothing, the war its beats wrote having already happened"
	)
	var after := CampaignProfile.load_progress(PROBE)
	assert_eq(after.flag(HELD), 1, "which is exactly what the ledger did")
	assert_eq(after.flag(SAVED), 1)


func test_a_mission_that_was_lost_reports_nothing_either() -> void:
	var campaign := _campaign()
	var mission := campaign.missions[0]
	mission.events.append(_beat(&"the_town_holds", [_writes(HELD)]))
	var lost := Fixture.state(ROW)
	CampaignSession.begin(campaign, mission, CampaignState.begin(campaign))
	CampaignSession.open_board(lost)
	_fire(lost, mission.events[0])
	lost.eliminate(1)
	assert_true(CampaignSession.decide(lost))
	CampaignSession.record(lost)
	assert_eq(CampaignSession.recorded_notes(), [] as Array[String])


func test_two_beats_may_count_the_same_fact_up() -> void:
	var campaign := _campaign()
	var mission := campaign.missions[0]
	mission.events.append(_beat(&"first_town", [_writes(SAVED, 1, true)]))
	mission.events.append(_beat(&"second_town", [_writes(SAVED, 1, true)]))
	_play(campaign, mission, Fixture.state(ROW))
	assert_eq(CampaignProfile.load_progress(PROBE).flag(SAVED), 2)


func test_a_fact_staged_before_a_save_survives_the_resume() -> void:
	var campaign := _campaign()
	var mission := campaign.missions[0]
	mission.events.append(_beat(&"the_town_holds", [_writes(HELD)]))
	var state := Fixture.state(ROW)
	CampaignSession.begin(campaign, mission, CampaignState.begin(campaign))
	CampaignSession.open_board(state)
	_fire(state, mission.events[0])
	assert_true(CampaignSession.save_battle(SaveCodec.encode(state, [2] as Array[int])))

	var resumed := CampaignProfile.load_in_progress(PROBE)
	CampaignSession.clear()
	CampaignSession.begin(campaign, mission, CampaignProfile.load_progress(PROBE), resumed.tally)
	CampaignSession.open_board(state)
	assert_true(CampaignSession.decide(state))
	CampaignSession.record(state)
	assert_eq(
		CampaignProfile.load_progress(PROBE).flag(HELD),
		1,
		"a mission finished after a reload wrote what it had already staged"
	)


# --- reading it ----------------------------------------------------------------


func test_a_line_with_no_condition_is_said_exactly_as_it_always_was() -> void:
	var lines: Array[MissionLine] = [
		MissionLine.of(&"", "The road is open."), MissionLine.of(&"", "For now.")
	]
	assert_eq(MissionLine.spoken(lines, null), lines)
	assert_eq(MissionLine.spoken(lines, CampaignState.begin(_campaign())), lines)


func test_a_variant_line_is_said_only_while_the_war_reads_that_way() -> void:
	var ledger := CampaignState.begin(_campaign())
	var common := MissionLine.of(&"", "The column moves at dawn.")
	var after_greenwater := MissionLine.of(&"", "Greenwater's wardens ride with us.")
	after_greenwater.requires = _condition(HELD)
	var without := MissionLine.of(&"", "We ride alone.")
	without.unless = _condition(HELD)
	var lines: Array[MissionLine] = [common, after_greenwater, without]

	assert_eq(MissionLine.spoken(lines, ledger), [common, without] as Array[MissionLine])
	ledger.flags[HELD] = 1
	assert_eq(MissionLine.spoken(lines, ledger), [common, after_greenwater] as Array[MissionLine])


## Each line stands on its own condition — there are no alternative groups — so
## an author reads the list top to bottom and two conditions that both hold are
## two lines that are both said.
func test_every_line_that_holds_is_said() -> void:
	var ledger := CampaignState.begin(_campaign())
	ledger.flags[SAVED] = 2
	var one := MissionLine.of(&"", "Two towns still stand.")
	one.requires = _condition(SAVED, 1)
	var two := MissionLine.of(&"", "It could have been more.")
	two.requires = _condition(SAVED, 0, 3)
	var lines: Array[MissionLine] = [one, two]
	assert_eq(MissionLine.spoken(lines, ledger), lines)


## The hub's strip is the war in the words the beats that wrote it used, so a fact
## the ledger does not hold has no line — and an empty event slot is skipped the
## way every other walk over a mission's script skips one, because the hub opens
## on the play path where nothing has asked `story_error` about it.
func test_the_war_so_far_is_read_off_the_facts_the_ledger_holds() -> void:
	var campaign := _campaign()
	campaign.missions[0].events.append(_beat(&"held", [_writes(HELD)] as Array[MissionEffect]))
	campaign.missions[0].events.append(null)
	var ledger := CampaignState.begin(campaign)
	assert_eq(campaign.ledger_notes(ledger), [] as Array[String])
	ledger.flags[HELD] = 1
	assert_eq(campaign.ledger_notes(ledger), ["Greenwater held."] as Array[String])


## A recording re-issues a beat and has to speak the same words, so a beat the
## war decides is a beat with a `Flag` trigger rather than a gated line.
func test_a_scripted_beat_may_not_gate_its_own_words() -> void:
	var campaign := _campaign()
	var mission := campaign.missions[0]
	var line := MissionLine.of(&"", "The wardens remember.")
	line.requires = _condition(HELD)
	var event := _beat(&"the_wardens_turn", [_writes(HELD)])
	event.lines = [line]
	mission.events.append(event)
	assert_string_contains(mission.story_error(Fixture.commander_db()), "Flag trigger")
	line.requires = null
	assert_eq(mission.story_error(Fixture.commander_db()), "")


# --- the milestone's gate ------------------------------------------------------


## The two-mission fixture campaign: the first writes a fact, and the second
## reads it in both the places D5 allows — the words it opens with, and the board
## it opens on. Nothing about the second mission is tuned; what changes is which
## authored content is used.
func test_the_second_mission_opens_differently_because_of_the_first() -> void:
	var campaign := _campaign()
	var first := campaign.missions[0]
	first.events.append(_beat(&"the_town_holds", [_writes(HELD)]))

	var second := campaign.missions[1]
	var common := MissionLine.of(&"", "Kestrel Pass, before first light.")
	var thanks := MissionLine.of(&"", "The Greenwater wardens hold our flank.")
	thanks.requires = _condition(HELD)
	second.briefing = [common, thanks]
	var withdrawn: Array[MissionEffect] = [_garrison_withdrawn()]
	second.events.append(_beat(&"the_garrison_leaves", withdrawn, _condition(HELD)))

	var before := Fixture.state(ROW)
	CampaignSession.begin(campaign, second, CampaignState.begin(campaign))
	CampaignSession.open_board(before)
	assert_eq(
		MissionLine.spoken(second.briefing, CampaignSession.progress),
		[common] as Array[MissionLine],
		"the war has not happened yet"
	)
	assert_true(CampaignSession.due_events(before).is_empty(), "so the board opens as authored")

	_play(campaign, first, Fixture.state(ROW))
	var ledger := CampaignProfile.load_progress(PROBE)
	assert_eq(ledger.flag(HELD), 1)

	var after := Fixture.state(ROW)
	CampaignSession.begin(campaign, second, ledger)
	CampaignSession.open_board(after)
	assert_eq(
		MissionLine.spoken(second.briefing, CampaignSession.progress),
		[common, thanks] as Array[MissionLine],
		"the briefing reads differently after mission one"
	)
	assert_eq(CampaignSession.due_events(after), [second.events[0]], "and so does the board")
	_fire(after, second.events[0])
	assert_eq(after.units.size(), before.units.size() - 1, "the garrison is not there this time")


## The defenders a flag takes off the opening board — the cheap answer to
## "conditional starting units", which is an ordinary opening event and needed no
## mechanism of its own.
func _garrison_withdrawn() -> RemoveUnitsEffect:
	var effect := RemoveUnitsEffect.new()
	effect.tags = [&"garrison"]
	return effect


## Why a flag can never break a replay, and why D5's boundary is checkable rather
## than only stated: writing one leaves the board exactly where it was, so the
## digest a recording is verified against cannot move for it.
func test_writing_a_fact_moves_no_board() -> void:
	var state := Fixture.state(ROW)
	var before := ReplayCodec.checkpoint(state)
	var event := _beat(&"the_town_holds", [_writes(HELD)])
	var command := MissionEventCommand.new(event, 1)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(ReplayCodec.checkpoint(state), before)
	assert_eq(command.written.size(), 1, "and the fact reached the campaign layer")
