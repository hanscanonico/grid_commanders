class_name BattleMissionScenario
extends RefCounted
## The one capture that plays a campaign mission, so the in-battle objective card
## has a frame (campaign-depth CD2). The card is down for every skirmish, which
## is what keeps the rest of the sweep byte-stable and why this scenario is the
## only way it is reachable at all.
##
## It is two halves at two moments. `stage` runs before Battle has built
## anything, because a mission's board is not in the map catalogue and no
## `--map=` can name one: the launch is `CampaignSession.begin` into
## `MatchConfig.stage`, the two calls the campaign hub's Deploy makes, in that
## order and with nothing added — a mission boots through the shipped path or it
## does not boot (campaign D1). `run` then reads the card back off its live
## labels, because the sweep's own bar is a file size and a card whose rows
## collapsed to nothing photographs perfectly well.
##
## Its own class rather than more methods on BattleScenarioDriver, the way
## BattleOverlayScenario and BattleVictoryScenario are: that file is at its
## length ratchet. Returns an error string rather than reporting one, because the
## driver's `_fail` owns the push_error and the exit-code flag together.

const MODE := "objective_panel"
## The Collection's opening mission, because CD2 re-authored it onto `HoldCell`:
## the card then carries a new verb, its running readout, and the deadline that
## ends it, rather than a lone "take the depot".
const CAMPAIGN := &"the_collection"
const MISSION := &"tc01_the_ledger_opens"

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


## Stages this scenario's launch, if this boot is it. Called from `Battle._ready`
## before it asks MatchConfig for a request; inert for every other run, capture
## or not.
static func stage() -> void:
	if not BattleScenarioDriver.requested() or BattleScenarioDriver.boot_demo() != MODE:
		return
	var campaign := CampaignDB.load_default().by_id(CAMPAIGN)
	var mission := campaign.mission(MISSION) if campaign != null else null
	if mission == null:
		push_error("capture: no mission '%s' to pose the objective panel on" % MISSION)
		return
	MatchConfig.stage(CampaignSession.begin(campaign, mission, CampaignState.begin(campaign)))


func run() -> String:
	var panel := _battle.view.mission_panel
	# The card measures and places itself a frame after its rows were added, like
	# the teaching strip and the seat strip.
	await _battle.get_tree().process_frame
	var error := panel.layout_error()
	if error != "":
		return error
	# The board band the two docked bars leave over, which is what every floating
	# surface is checked against.
	var frame := _battle.get_viewport().get_visible_rect().size
	var band := Rect2(Vector2(0, UiTheme.HUD_TOP_H), Vector2(frame.x, frame.y - UiTheme.HUD_BARS_H))
	if not band.encloses(panel.get_global_rect()):
		return (
			"the objective panel %s does not fit the board band %s"
			% [panel.get_global_rect(), band]
		)
	return ""
