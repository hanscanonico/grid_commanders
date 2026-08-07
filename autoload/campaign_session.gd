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
var _runtime: MissionRuntime


## Stage a mission and return the launch it is, for `MatchConfig.stage`.
func begin(
	p_campaign: CampaignDefinition, p_mission: MissionDefinition, p_progress: CampaignState
) -> MatchRequest:
	campaign = p_campaign
	mission = p_mission
	progress = p_progress
	outcome = null
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
func decide(game: GameState) -> bool:
	if _runtime == null or outcome != null:
		return false
	var verdict := _runtime.evaluate(game)
	if not verdict.is_over():
		return false
	outcome = verdict
	return true


## Record a finished mission against the profile and step off it.
##
## Takes the outcome rather than deciding one: `MissionRuntime` owns that
## verdict, and a second opinion here is how a mission comes to be cleared on a
## board it was lost on.
func finish(outcome: MissionRuntime.Outcome, day: int) -> void:
	if progress != null and campaign != null and mission != null:
		if outcome.status == MissionRuntime.Status.SUCCESS:
			progress.complete(campaign, mission.id, outcome.stars, day)
		else:
			progress.active_mission = &""


## Forget the campaign — leaving for the menu, or starting a skirmish. Called on
## the way out so a later skirmish cannot inherit a mission nobody is playing,
## which is the same reason `MatchConfig.take()` clears.
func clear() -> void:
	campaign = null
	mission = null
	progress = null
