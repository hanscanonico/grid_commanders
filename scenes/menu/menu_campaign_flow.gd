class_name MenuCampaignFlow
extends RefCounted
## The menu's campaign navigation: pick a war, pick a mission inside it, deploy.
##
## `BattleExit`'s shape — a collaborator holding one coherent slice of a screen
## that was getting wide — and split off `MainMenu` for that reason rather than
## for tidiness: the menu is a *setup* page, and which mission of which campaign
## a player is in is a different question from which board and how much fog.
##
## It owns the two panels and the walk between them, and nothing else. Staging is
## still one `MatchRequest` through `MatchConfig`, exactly as the skirmish and
## replay routes stage theirs, so a mission boots through the shipped path.

## The campaign whose hub is open, so a deploy knows which war its mission is
## from. Held here rather than asked of `CampaignSession`, which is not told
## anything until the launch itself.
var _campaign: CampaignDefinition
var _picker: CampaignPickerPanel
var _hub: CampaignHubPanel
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
	# Back out of a hub to the campaign list, not to the menu: the player chose a
	# war and then chose not to fight this mission, which is one step back.
	_hub.cancelled.connect(open)


## The campaign list, over a hidden menu.
func open() -> void:
	_menu_root.hide()
	_picker.begin(CampaignDB.load_default().all())


## Reopens the hub of the campaign a finished mission belonged to, on the
## progress that mission just wrote — so coming back from a battle lands where
## the next mission is rather than on the menu. The session is cleared as it is
## read, so a later Quit-to-menu cannot reopen a campaign nobody is in.
func resume() -> bool:
	var campaign := CampaignSession.campaign
	CampaignSession.clear()
	if campaign == null:
		return false
	_show_hub(campaign)
	return true


func chrome_picker() -> Dictionary[String, Control]:
	return _picker.chrome()


func chrome_hub() -> Dictionary[String, Control]:
	return _hub.chrome()


## Dev captures only: poses the hub — and optionally its first briefing — on a
## *fresh* profile, so the picture does not depend on how far the machine that
## took it happens to have played.
func pose_hub(open_briefing: bool) -> void:
	var posed := CampaignDB.load_default().all()
	if posed.is_empty():
		return
	_campaign = posed[0]
	_menu_root.hide()
	_hub.begin(posed[0], CampaignState.begin(posed[0]))
	if open_briefing:
		_hub.debug_open_first()


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


func _show_hub(campaign: CampaignDefinition) -> void:
	var progress := CampaignProfile.load_progress(campaign.id)
	if progress == null:
		progress = CampaignState.begin(campaign)
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
	var progress := CampaignProfile.load_progress(_campaign.id)
	if progress == null:
		progress = CampaignState.begin(_campaign)
	MatchConfig.stage(CampaignSession.begin(_campaign, mission, progress))
	_launch.call()


func _close() -> void:
	_menu_root.show()
	_on_closed.call()
