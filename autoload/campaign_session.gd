extends Node
## Which campaign and mission the player is in, carried across a scene change.
##
## Navigation intent only. It decides no rule and holds no board: the match
## itself is still a `MatchRequest` staged on `MatchConfig`, built by
## `BattleSetup` through the one shipped path, so a mission boots exactly as a
## menu launch does and nothing in `core/` learns a campaign exists.
##
## It is a second autoload rather than two more fields on `MatchConfig` because
## that one deliberately carries exactly one typed request and nothing else —
## a battle that is not part of a campaign must not have to know what a campaign
## is in order to launch.

## The campaign in play, or null outside one.
var campaign: CampaignDefinition
## The mission in play, or null outside one.
var mission: MissionDefinition
## The player's progress in `campaign`, or null outside one. It is also the
## consequence ledger a `Flag` trigger and a variant line read, which is why
## `due_events` hands it over.
var progress: CampaignState
## The verdict, once a mission has been decided. Read by the outcome screen.
var outcome: MissionRuntime.Outcome
## What the mission has tallied over the boards it has been played on — days a
## square has been held, units lost. Baselined by `open_board` and advanced by
## `decide`; this session is the only thing that ever writes it, which is
## campaign-depth D2's one writer.
var tally: MissionProgress
var _runtime: MissionRuntime
## Whether the ledger took what this mission staged, answered by the write itself.
## False until then, and false for a replay of a mission already cleared — which
## stages its facts exactly as the first run did and writes none of them.
var _committed := false
## The ending a scripted beat declared, or null. A fact `MissionRuntime` takes
## its own view of (campaign-depth D3) rather than a verdict, which is why it is
## handed to `evaluate` instead of short-circuiting it — a scripted victory on the
## turn a deadline expired is still a mission lost.
var _ending: EndMissionEffect


## Stage a mission and return the launch it is, for `MatchConfig.stage`.
##
## `resumed_tally` is the tally the saved board was being kept with, and null
## starts the mission clean — the tally follows the board, so a retry that
## inherited the last attempt's losses would fail a loss limit nobody had spent.
## The caller hands it over rather than this session fetching it, because the
## caller is already reading the profile to find out whether there is a board to
## pick up at all; asking again here would be a second opinion about that.
func begin(
	p_campaign: CampaignDefinition,
	p_mission: MissionDefinition,
	p_progress: CampaignState,
	resumed_tally: MissionProgress = null
) -> MatchRequest:
	campaign = p_campaign
	mission = p_mission
	progress = p_progress
	outcome = null
	tally = resumed_tally if resumed_tally != null else MissionProgress.new()
	_runtime = MissionRuntime.new(p_mission)
	_ending = null
	_committed = false
	if progress != null:
		progress.active_mission = p_mission.id
		progress.run = {}
	return p_mission.to_request()


## Is a campaign mission being played right now?
func active() -> bool:
	return mission != null


## Which war and which mission this battle is, for a recording's header. Both
## &"" outside a campaign, which is what leaves a skirmish's header unchanged.
func campaign_id() -> StringName:
	return campaign.id if campaign != null else &""


func mission_id() -> StringName:
	return mission.id if mission != null else &""


## The scripted beats due on the board as it now stands, in the order the mission
## lists them. Empty for every skirmish, and empty once the mission has been
## decided — a beat landing after the verdict changes a board nobody is playing.
##
## Empty on a board the *match* has been decided on for the same reason, and that
## one comes first: `decide` runs after this at the same boundary, so the shot
## that ends the fight leaves this boundary's beats due on a board
## `MissionEventCommand.validate` refuses by design. Offering them would be asking
## for a refusal, which reads as an authoring fault and is not one.
##
## The board is read **once per boundary**. Asking again after each beat would let
## a repeating event fire itself forever inside one command, so a beat another
## beat unlocks lands at the next boundary instead.
func due_events(game: GameState) -> Array[MissionEvent]:
	var due: Array[MissionEvent] = []
	if mission == null or outcome != null or game.winner != 0:
		return due
	for event: MissionEvent in mission.events:
		if event != null and event.is_due(game, mission.player_team, tally, progress):
			due.append(event)
	return due


## Note what a fired beat did to the *mission* — that it happened, the hidden
## objectives it brought out, the facts it wrote and the ending it declared. The
## board half is the command's and is already applied; this is the tally's one
## writer again, and it is called at the boundary the beat fired on so the
## verdict taken next sees it.
##
## A fact waits in the tally until the mission is finished, which is what stops a
## retried mission writing the ledger twice; `CampaignState.complete` takes it.
func record_event(command: MissionEventCommand) -> void:
	if mission == null:
		return
	tally.record_fired(command.event.id)
	for objective_id: StringName in command.revealed:
		tally.reveal(objective_id)
	for fact: SetFlagEffect in command.written:
		tally.stage_flag(fact.flag, fact.value, fact.mode == SetFlagEffect.Mode.ADD)
	if command.ending != null:
		_ending = command.ending


## Stand the army the war remembers in this board's carry slots, on a board
## nothing has been applied to yet — so the veterans are part of the board the
## mission opens on, and the save, the recording and the tally all take it as it
## stands (campaign-depth D6).
##
## Silent outside a campaign and for every mission that carries nothing in, which
## is every mission but the few in an authored chain: the map's own army stands
## and the board opens exactly as it was authored.
func deploy_army(game: GameState) -> void:
	if mission == null or progress == null or not mission.carry_in:
		return
	CampaignRoster.deploy(game, mission.player_team, progress.roster, mission.carry_floor_hp)


## Take the board the mission opens on as the tally's baseline, before a command
## has been applied to it. Called once by the battle scene, as soon as the board
## exists; silent outside a campaign.
##
## `observe` advances the tally by diffing the board against the last one it saw,
## so the *first* board it is ever shown can only be a baseline. Left to `decide`
## that first board is the one command in, and whatever that command cost is
## free — on a fresh mission, and again on every resume, which is a loss limit a
## reload spends nothing against.
func open_board(game: GameState) -> void:
	if mission == null:
		return
	tally.observe(game, mission.player_team)


## Has the mission just ended, on a board a command has been applied to?
##
## The gate for every skirmish is the null runtime, so a match outside a
## campaign asks nothing and is unchanged. It is asked *before* the turn hands
## over so a mission settles on the board that ended it, and it outranks the
## receipt's own winner because `MissionRuntime`'s precedence already turns a
## tactical victory into success — consulting both would give one board two
## endings. Decided once: a mission already over stays over.
##
## The tally is advanced here and before the verdict, because a condition asking
## how long the ridge has been ours has to be answered about this board rather
## than the one before it.
func decide(game: GameState) -> bool:
	if _runtime == null or outcome != null:
		return false
	tally.observe(game, mission.player_team)
	var verdict := _runtime.evaluate(game, tally, _ending)
	if not verdict.is_over():
		return false
	outcome = verdict
	return true


## Write the finished mission to the campaign's profile.
##
## Reads the outcome this session already holds rather than being handed one:
## `MissionRuntime` decided it and `decide` recorded it, so a second opinion here
## is how a mission comes to be cleared on a board it was lost on. Silent outside
## a campaign, and silent before a verdict — the victory screen calls it on every
## match and only a mission has anything to write.
##
## The tally goes with the clear, because the facts this mission staged are the
## ledger's only on a mission that was actually finished: a defeat is retried,
## and the war remembers the attempt that stood.
##
## The army it fielded goes the same way and on the same answer — the war takes it
## on the first clear and never again (`CampaignState`'s replay rules), because the
## roster *is* the next mission's board and a casual replay must not re-deal one the
## player has already played past. Which is why the finished **board** is handed
## over rather than only its day: what survived is on it, and asking the board is
## the only way to know.
##
## The run's own facts are written last, against the record as it stood before
## this run — `complete` improves that record in place, so "a new best" has to
## be read before it is. They go on the profile object and never to disk:
## `CampaignSaveCodec.encode` names what it stores.
func record(game: GameState) -> void:
	if outcome == null or progress == null or campaign == null or mission == null:
		return
	var previous := _record_before()
	if outcome.status == MissionRuntime.Status.SUCCESS:
		_committed = progress.complete(campaign, mission.id, outcome.stars, game.day, tally)
		if _committed:
			var carried: Array[CarriedUnit] = []
			if mission.carry_out:
				carried = CampaignRoster.bank(game, mission.player_team)
			progress.roster = carried
	else:
		progress.active_mission = &""
	progress.run = _run_facts(game.day, previous)
	CampaignProfile.save_progress(progress)


## A copy of the mission's record before this run touches it, or null on a
## mission never cleared.
func _record_before() -> CampaignState.MissionRecord:
	var record: CampaignState.MissionRecord = progress.records.get(mission.id)
	if record == null:
		return null
	return CampaignState.MissionRecord.new(record.stars, record.best_day)


## What this run says about itself (`CampaignState.RUN_FACTS`), for the victory
## or defeat line that reads it. Written on a loss too, since the cause is what a
## defeat line asks after; the win-only facts then read zero. A first clear is
## `run:first` and not `run:best` — there was no record to beat.
func _run_facts(day: int, previous: CampaignState.MissionRecord) -> Dictionary[StringName, int]:
	var won := outcome.status == MissionRuntime.Status.SUCCESS
	var inside_par := won and mission.par_day > 0 and day <= mission.par_day
	var best := (
		won
		and previous != null
		and (outcome.stars > previous.stars or (previous.best_day > 0 and day < previous.best_day))
	)
	return {
		&"run:stars": outcome.stars,
		&"run:full": 1 if won and outcome.stars == max_stars() else 0,
		&"run:par": 1 if inside_par else 0,
		&"run:day": day,
		&"run:losses": tally.losses(),
		&"run:best": 1 if best else 0,
		&"run:first": 1 if _committed else 0,
		&"run:cause": int(outcome.cause),
		&"run:failure": outcome.failure_index,
	}


## What this mission wrote to the war, in the words its own beats put on it — the
## debrief's line about what changed.
##
## What was **committed**, never what was staged: empty until the ledger has
## actually taken the facts, so a replay of a mission already cleared reports
## nothing, its beats having changed a war that already happened. The debrief is
## the one screen that tells a player their choices mattered, and a false entry
## there is worse than no entry. Empty too for a beat that named no consequence.
func recorded_notes() -> Array[String]:
	var notes: Array[String] = []
	if mission == null or not _committed:
		return notes
	for event: MissionEvent in mission.events:
		if event == null or not tally.has_fired(event.id):
			continue
		for effect: MissionEffect in event.effects:
			var fact := effect.written_flag() if effect != null else null
			if fact != null and fact.note != "":
				notes.append(fact.note)
	return notes


## The most stars this mission could award, for the "★★☆" the debrief prints.
func max_stars() -> int:
	return _runtime.max_stars() if _runtime != null else 0


## Write the mission in progress into the campaign's profile, board included, so
## a mid-mission save stays the campaign's to resume. The envelope is
## `SaveCodec.encode`'s, handed in whole: this session holds no board and never
## reads inside one. False — and nothing written — outside a campaign.
func save_battle(battle: Dictionary) -> bool:
	if progress == null or mission == null:
		return false
	progress.active_mission = mission.id
	return CampaignProfile.save_progress(progress, battle, tally)


## Forget the campaign — leaving for the menu, or starting a skirmish. Resets
## every field this session owns, the verdict and the runtime included: a later
## skirmish must not inherit a mission nobody is playing, neither its objectives
## through `decide` nor its result on the victory screen — the same reason
## `MatchConfig.take()` clears. The run's facts go with it: the debrief has read
## them by now, and the profile the menu keeps must not carry a run nobody is in.
func clear() -> void:
	if progress != null:
		progress.run = {}
	campaign = null
	mission = null
	progress = null
	outcome = null
	tally = null
	_runtime = null
	_ending = null
	_committed = false
