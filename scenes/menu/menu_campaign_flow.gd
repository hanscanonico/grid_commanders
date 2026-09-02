class_name MenuCampaignFlow
extends RefCounted
## The menu's campaign navigation: pick a war, pick a mission inside it, deploy.
##
## `BattleExit`'s shape — a collaborator holding one coherent slice of a screen
## that was getting wide — and split off `MainMenu` for that reason rather than
## for tidiness: the menu is a *setup* page, and which mission of which campaign
## a player is in is a different question from which board and how much fog.
##
## It owns the campaign's pages and the walk between them, and nothing else.
## Staging is still one `MatchRequest` through `MatchConfig`, exactly as the
## skirmish and replay routes stage theirs, so a mission boots the shipped path.

## Developer route: opens every authored mission of whichever war the hub is on,
## so one behind a route gate can be played without a profile that earned it.
## Nothing a flagged run does is written — `CampaignProfile.save_progress` refuses
## a state carrying it — so it is an inspection rather than a shortcut, and a
## mid-mission save is refused at that same door.
const UNLOCK_ARG := "--unlock-missions"

## How far `_pose_hub_deep` walks a war, and what each mission cost it. Thirteen is
## the first count whose open mission the list has to *scroll* to reach — twelve
## rows fit the page, so a shorter walk photographs a list that never moved and
## would read the same with `follow_focus` off.
const POSED_CLEARED_MISSIONS := 13
const POSED_STARS := 2
const POSED_DAY := 5

## The campaign whose hub is open, so a deploy knows which war its mission is
## from. Held here rather than asked of `CampaignSession`, which is not told
## anything until the launch itself.
var _campaign: CampaignDefinition
var _picker: CampaignPickerPanel
var _hub: CampaignHubPanel
var _debrief: CampaignDebriefPanel
var _interlude: CampaignInterludePanel
## The page a finished mission earned, shown once the debrief is done with and
## then dropped. Held here because the session that named the mission is cleared
## as the debrief opens.
var _pending: CampaignInterlude
## The war the pending page is read against — the same `CampaignState` the debrief
## spoke to rather than the profile re-read off disk, so the two pages of one beat
## cannot disagree about how the block went when a progress write fails.
var _pending_ledger: CampaignState
## The mission the open debrief is about, for a Retry from it. Set as the debrief
## opens and dropped as it closes either way, so nothing after it can deploy a
## mission nobody is looking at.
var _debrief_mission: StringName
## The menu stack the panels are shown over, hidden while either is up.
var _menu_root: Control
## Where a Back from the campaign list lands.
var _on_closed: Callable
var _launch: Callable


func _init(host: Node, menu_root: Control, on_closed: Callable, launch: Callable) -> void:
	_menu_root = menu_root
	_on_closed = on_closed
	_launch = launch
	_picker = CampaignPickerPanel.new()
	host.add_child(_picker)
	_picker.picked.connect(_open_hub)
	_picker.cancelled.connect(_close)
	_hub = CampaignHubPanel.new()
	host.add_child(_hub)
	_hub.deployed.connect(_deploy)
	_debrief = CampaignDebriefPanel.new()
	host.add_child(_debrief)
	_debrief.continued.connect(_after_debrief)
	_debrief.retried.connect(_retry)
	_interlude = CampaignInterludePanel.new()
	host.add_child(_interlude)
	_interlude.continued.connect(_after_interlude)
	# Back out of a hub to the campaign list, not to the menu: the player chose a
	# war and then chose not to fight this mission, which is one step back.
	_hub.cancelled.connect(open)


## The campaign list, over a hidden menu.
func open() -> void:
	_menu_root.hide()
	_picker.begin(CampaignDB.load_default().all())


## Coming back from a battle plays the debrief first — what the generals say
## about what just happened — and only then the hub. The session is read here
## and cleared once the debrief is done with it, because the words belong to the
## mission that was just played and nothing else knows which one that was.
func resume() -> bool:
	var campaign := CampaignSession.campaign
	var mission := CampaignSession.mission
	var outcome := CampaignSession.outcome
	if campaign == null:
		CampaignSession.clear()
		return false
	_campaign = campaign
	if mission == null or outcome == null:
		# Left the battle without finishing it: there is nothing to debrief, so
		# the hub is where a player who walked away belongs.
		CampaignSession.clear()
		_show_hub(campaign)
		return true
	_menu_root.hide()
	var progress := CampaignSession.progress
	# The ledger has already settled — `CampaignSession.record` runs on the victory
	# screen — so the debrief speaks against the war as it now stands, which is what
	# a variant victory line is written against, and reports what that write took.
	# Everything is read before the clear below, which takes the tally with it.
	var report := CampaignDebriefPanel.Report.new(mission, outcome)
	report.next_title = _next_title(campaign, progress, outcome)
	report.ledger = progress
	report.recorded = CampaignSession.recorded_notes()
	report.losses = CampaignSession.tally.losses() if CampaignSession.tally != null else 0
	report.previous = CampaignSession.previous_record()
	report.campaign = campaign
	_pending = _closing_interlude(campaign, mission, outcome)
	_pending_ledger = progress
	_debrief_mission = mission.id
	_debrief.begin(report, Settings.menu_animations)
	CampaignSession.clear()
	return true


## What the finished mission opened, for the debrief's one forward-looking line.
## Empty at the end of a campaign, and empty on a loss — nothing was unlocked.
## Asked of the route rather than of the list, so a mission the war closed is not
## announced as the one coming next.
func _next_title(
	campaign: CampaignDefinition, progress: CampaignState, outcome: MissionRuntime.Outcome
) -> String:
	if outcome.status != MissionRuntime.Status.SUCCESS or progress == null:
		return ""
	var entry := campaign.mission(progress.open_mission(campaign))
	return entry.title if entry != null else ""


## The page this mission earned, or null: a block is closed by its last mission,
## and only by winning it.
func _closing_interlude(
	campaign: CampaignDefinition, mission: MissionDefinition, outcome: MissionRuntime.Outcome
) -> CampaignInterlude:
	if outcome.status != MissionRuntime.Status.SUCCESS:
		return null
	var block := campaign.closes_block(mission.id)
	return campaign.interlude_after(block) if block >= 0 else null


## The debrief is done: the page between the blocks, if this mission closed one,
## and the hub after it.
func _after_debrief() -> void:
	_debrief_mission = &""
	if _campaign == null:
		return
	if _pending == null:
		_show_hub(_campaign)
		return
	_interlude.begin(_pending, _pending_ledger, Settings.menu_animations)
	_pending = null
	_pending_ledger = null


## Retry from the debrief of a lost mission: the same deploy the hub makes.
## `CampaignSession.record` already cleared the profile's active mission on the
## loss, so this starts the mission fresh rather than resuming the board it was
## lost on.
func _retry() -> void:
	var mission_id := _debrief_mission
	_debrief_mission = &""
	if mission_id == &"":
		push_error("MenuCampaignFlow: retried with no debrief open")
		return
	_deploy(mission_id)


func _after_interlude() -> void:
	if _campaign != null:
		_show_hub(_campaign)


func _chrome_picker() -> Dictionary[String, Control]:
	return _picker.chrome()


func _chrome_hub() -> Dictionary[String, Control]:
	return _hub.chrome()


## Dev captures only: opens whichever campaign page this run asked for and hands
## back the chrome to measure it against, or an empty Callable when it asked for
## none. One entry point because the pages pose identically and the menu should
## not carry a copy of that per page.
func pose(driver: MenuCaptureDriver) -> Callable:
	if driver.poses(MenuCaptureDriver.DEMO_CAMPAIGNS):
		_pose_picker()
		return _chrome_picker
	if driver.poses(MenuCaptureDriver.DEMO_CAMPAIGN_DEBRIEF):
		_pose_debrief(true)
		return _chrome_debrief
	if driver.poses(MenuCaptureDriver.DEMO_CAMPAIGN_DEFEAT):
		_pose_debrief(false)
		return _chrome_debrief
	if driver.poses_campaign_hub():
		_pose_hub(driver.poses(MenuCaptureDriver.DEMO_CAMPAIGN_BRIEF))
		return _chrome_hub
	if driver.poses(MenuCaptureDriver.DEMO_CAMPAIGN_DEEP):
		_pose_hub_deep()
		return _chrome_hub
	if driver.poses(MenuCaptureDriver.DEMO_CAMPAIGN_INTERLUDE):
		_pose_interlude()
		return _chrome_interlude
	return Callable()


## Dev captures only: the war list on a fresh profile for every campaign, the way
## `_pose_hub` poses its own — the rows carry how far each war has got, so an
## `open()` here would photograph how much of the game this machine has played.
func _pose_picker() -> void:
	_menu_root.hide()
	var campaigns := CampaignDB.load_default().all()
	var fresh: Dictionary[StringName, CampaignState] = {}
	for campaign in campaigns:
		fresh[campaign.id] = CampaignState.begin(campaign)
	_picker.begin(campaigns, fresh)


func _pose_debrief(won: bool) -> void:
	var posed := CampaignDB.load_default().all()
	if posed.is_empty():
		return
	var campaign: CampaignDefinition = posed[0]
	var mission: MissionDefinition = campaign.missions[0]
	# One earned and one missed, so the frame photographs the shape a real
	# mission's awards take. The posed day is past this mission's own par, so the
	# missed star and the scoreboard beside it tell the same story.
	var late_day := mission.par_day + 2
	var awards: Array[MissionRuntime.Award] = [
		MissionRuntime.Award.new("Mission complete", true),
		MissionRuntime.Award.new("Finish by day %d" % mission.par_day, false),
	]
	var outcome := MissionRuntime.Outcome.new(
		MissionRuntime.Status.SUCCESS if won else MissionRuntime.Status.FAILURE,
		"" if won else "The road stayed closed past day %d." % mission.par_day,
		1 if won else 0,
		awards if won else ([] as Array[MissionRuntime.Award]),
		late_day if won else 0
	)
	# The route is what names the mission this one opened, so the pose walks it: a
	# fresh profile with this mission cleared is the war the debrief is speaking to.
	# Cleared twice, the first time slower, so the won frame shows what a clear is
	# worth against the record it beat rather than only a first clear.
	var previous := CampaignState.MissionRecord.new(outcome.stars, late_day + 2)
	var progress := CampaignState.begin(campaign)
	progress.complete(campaign, mission.id, previous.stars, previous.best_day)
	progress.complete(campaign, mission.id, outcome.stars, late_day)
	var report := CampaignDebriefPanel.Report.new(mission, outcome)
	report.next_title = _next_title(campaign, progress, outcome)
	report.ledger = progress
	report.losses = 2
	report.previous = previous
	report.campaign = campaign
	_menu_root.hide()
	_debrief.begin(report, false)


func _chrome_debrief() -> Dictionary[String, Control]:
	return _debrief.chrome()


## Dev captures only: poses the first interlude the shipped content authors, on a
## profile that has played nothing — so the picture is the page every player sees
## rather than the one this machine's own war earned.
func _pose_interlude() -> void:
	for campaign: CampaignDefinition in CampaignDB.load_default().all():
		for page: CampaignInterlude in campaign.interludes:
			if page == null:
				continue
			_menu_root.hide()
			_interlude.begin(page, CampaignState.begin(campaign), false)
			return


func _chrome_interlude() -> Dictionary[String, Control]:
	return _interlude.chrome()


## Dev captures only: poses the hub — and optionally its first briefing — on a
## *fresh* profile, so the picture does not depend on how far the machine that
## took it happens to have played.
func _pose_hub(open_briefing: bool) -> void:
	var posed := CampaignDB.load_default().all()
	if posed.is_empty():
		return
	_campaign = posed[0]
	_menu_root.hide()
	_hub.set_moving(false)
	_hub.begin(posed[0], CampaignState.begin(posed[0]))
	if open_briefing:
		_hub.debug_open_first()


## Dev captures only: the same hub a war is deep into, which is the one frame its
## list is scrolled in. The progress is walked forward the way a player walks it —
## a fresh ledger, then one `complete` per mission — so the route, the unlocks and
## the counts are the ones a real profile would hold, and nothing is written to
## disk or read off this machine's own wars.
func _pose_hub_deep() -> void:
	var posed := CampaignDB.load_default().all()
	if posed.is_empty():
		return
	var campaign: CampaignDefinition = posed[0]
	var progress := CampaignState.begin(campaign)
	for _cleared in POSED_CLEARED_MISSIONS:
		var next := progress.open_mission(campaign)
		if next == &"":
			break
		progress.complete(campaign, next, POSED_STARS, POSED_DAY)
	_campaign = campaign
	_menu_root.hide()
	_hub.set_moving(false)
	_hub.begin(campaign, progress)


## Opens a campaign's hub on whatever the player has already done in it. A
## campaign with no profile begins one rather than refusing: a first opening and
## a fresh start are the same thing, and nothing is written until a mission is
## actually finished.
func _open_hub(campaign_id: StringName) -> void:
	var campaign := CampaignDB.load_default().by_id(campaign_id)
	if campaign == null:
		push_error("MenuCampaignFlow: no campaign '%s'" % campaign_id)
		_close()
		return
	_show_hub(campaign)


## Whether this run was launched with the developer override. Static and
## argument-taking for `SeatStrip.normalised_sides`' reason: the grammar is then
## checked without a menu.
static func unlocks_all(args: PackedStringArray) -> bool:
	return CmdArgs.flag(args, UNLOCK_ARG)


## The war as this run plays it: what the profile holds, a fresh start when it
## holds nothing, and the override applied. Both the hub and the deploy read it
## here rather than each loading its own, because a mission the list offered and
## a state that had forgotten why is exactly the row that opens onto a refusal.
func _progress_for(campaign: CampaignDefinition) -> CampaignState:
	var progress := CampaignProfile.load_progress(campaign.id)
	if progress == null:
		progress = CampaignState.begin(campaign)
	progress.unlock_all = unlocks_all(CmdArgs.user())
	return progress


func _show_hub(campaign: CampaignDefinition) -> void:
	var progress := _progress_for(campaign)
	_campaign = campaign
	_menu_root.hide()
	_hub.begin(campaign, progress)


## Deploying is the same launch every other route makes — one staged request —
## with the session told which mission it belongs to so the battle can ask
## whether it is over. `CampaignSession.begin` is the one place that pairing is
## made, so the mission and the match it launches cannot disagree.
func _deploy(mission_id: StringName) -> void:
	if _campaign == null:
		push_error("MenuCampaignFlow: deployed '%s' with no campaign open" % mission_id)
		return
	var mission := _campaign.mission(mission_id)
	if mission == null:
		push_error("MenuCampaignFlow: no mission '%s' in '%s'" % [mission_id, _campaign.id])
		return
	var progress := _progress_for(_campaign)
	# The mission the profile is midway through resumes its saved board rather
	# than restarting, and carries on with the tally that board was kept with. Any
	# other deploy starts fresh, snapshot or none — a snapshot belongs to exactly
	# the mission that wrote it.
	var in_progress: CampaignProfile.InProgress = null
	if progress.active_mission == mission.id:
		in_progress = CampaignProfile.load_in_progress(_campaign.id)
	var resumes := in_progress != null and not in_progress.battle.is_empty()
	var request := CampaignSession.begin(
		_campaign, mission, progress, in_progress.tally if resumes else null
	)
	if resumes:
		request.campaign_resume = _campaign.id
	MatchConfig.stage(request)
	_launch.call()


func _close() -> void:
	_menu_root.show()
	_on_closed.call()
