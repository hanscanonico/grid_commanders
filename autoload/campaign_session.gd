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
## The player's progress in `campaign`, or null outside one.
var progress: CampaignState
## The verdict, once a mission has been decided. Read by the outcome screen.
var outcome: MissionRuntime.Outcome
## What the mission has tallied over the boards it has been played on — days a
## square has been held, units lost. Advanced by `decide` and nowhere else, which
## is campaign-depth D2's one writer.
var tally: MissionProgress
var _runtime: MissionRuntime


## Stage a mission and return the launch it is, for `MatchConfig.stage`.
##
## `resuming` says the saved board is being picked up rather than the mission
## restarted, and the tally follows the board: a retry that inherited the last
## attempt's losses would fail a loss limit nobody had spent.
func begin(
	p_campaign: CampaignDefinition,
	p_mission: MissionDefinition,
	p_progress: CampaignState,
	resuming := false
) -> MatchRequest:
	campaign = p_campaign
	mission = p_mission
	progress = p_progress
	outcome = null
	tally = CampaignProfile.load_tally(p_campaign.id) if resuming else MissionProgress.new()
	_runtime = MissionRuntime.new(p_mission)
	if progress != null:
		progress.active_mission = p_mission.id
	return p_mission.to_request()


## Is a campaign mission being played right now?
func active() -> bool:
	return mission != null


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
	var verdict := _runtime.evaluate(game, tally)
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
func record(day: int) -> void:
	if outcome == null or progress == null or campaign == null or mission == null:
		return
	if outcome.status == MissionRuntime.Status.SUCCESS:
		progress.complete(campaign, mission.id, outcome.stars, day)
	else:
		progress.active_mission = &""
	CampaignProfile.save_progress(progress)


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
## `MatchConfig.take()` clears.
func clear() -> void:
	campaign = null
	mission = null
	progress = null
	outcome = null
	tally = null
	_runtime = null
