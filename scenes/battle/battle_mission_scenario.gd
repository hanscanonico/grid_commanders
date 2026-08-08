class_name BattleMissionScenario
extends RefCounted
## The two captures that play a campaign mission: the in-battle objective card
## (campaign-depth CD2) and a scripted beat landing on the board (CD3). Both are
## down for every skirmish, which is what keeps the rest of the sweep
## byte-stable and why these scenarios are the only way either is reachable.
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
const EVENT_MODE := "mission_event"
## The Collection's opening mission, because CD2 re-authored it onto `HoldCell`:
## the card then carries a new verb, its running readout, and the deadline that
## ends it, rather than a lone "take the depot". CD3 hung its exemplar beat on
## the same mission, so the two frames stack rather than spreading.
const CAMPAIGN := &"the_collection"
const MISSION := &"tc01_the_ledger_opens"
## The customs depot the mission is about, and what Ferrow does the moment it
## changes hands.
const DEPOT := Vector2i(6, 4)
const EVENT := &"ferrow_collects"

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


## Stages this scenario's launch, if this boot is one of its two. Called from
## `Battle._ready` before it asks MatchConfig for a request; inert for every
## other run, capture or not.
static func stage() -> void:
	if not BattleScenarioDriver.requested():
		return
	if BattleScenarioDriver.boot_demo() not in [MODE, EVENT_MODE]:
		return
	var campaign := CampaignDB.load_default().by_id(CAMPAIGN)
	var mission := campaign.mission(MISSION) if campaign != null else null
	if mission == null:
		push_error("capture: no mission '%s' to pose the objective panel on" % MISSION)
		return
	MatchConfig.stage(CampaignSession.begin(campaign, mission, CampaignState.begin(campaign)))


func run(mode: String) -> String:
	if mode == EVENT_MODE:
		return await _run_event()
	return await _run_panel()


func _run_panel() -> String:
	var panel := _battle.view.mission_panel
	# The card measures and places itself a frame after its rows were added, like
	# the teaching strip and the seat strip.
	await _battle.get_tree().process_frame
	var error := panel.layout_error()
	if error != "":
		return error
	return _in_band("objective panel", panel)


## The depot changes hands and Ferrow's raider arrives — the mission's own beat,
## posed by giving the player the ground its trigger waits for rather than by
## calling the trigger anything. Firing goes through `BattleCampaign`, so what is
## photographed is the shipped seam and not a scenario's imitation of it.
func _run_event() -> String:
	var mission := CampaignSession.mission
	_battle.game.set_owner(DEPOT, mission.player_team)
	await BattleCampaign.fire_due(_battle)
	if not CampaignSession.tally.has_fired(EVENT):
		return "the mission's '%s' beat did not fire on a board that was due it" % EVENT
	if _battle.game.unit_at(Vector2i(11, 4)) == null:
		return "the '%s' beat landed no unit on the road" % EVENT
	var card := _battle.animator.mission_speech
	await _battle.get_tree().process_frame
	var error := card.layout_error()
	if error != "":
		return error
	return _in_band("mission speech card", card)


## The board band the two docked bars leave over, which is what every floating
## surface is checked against.
func _in_band(what: String, control: Control) -> String:
	var frame := _battle.get_viewport().get_visible_rect().size
	var band := Rect2(Vector2(0, UiTheme.HUD_TOP_H), Vector2(frame.x, frame.y - UiTheme.HUD_BARS_H))
	if not band.encloses(control.get_global_rect()):
		return "the %s %s does not fit the board band %s" % [what, control.get_global_rect(), band]
	return ""
