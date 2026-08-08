class_name BattleMissionScenario
extends RefCounted
## The three captures that play a campaign mission: the in-battle objective card
## (campaign-depth CD2), a scripted beat landing on the board and a scripted beat
## changing a unit's allegiance (CD3). All three are down for every skirmish,
## which is what keeps the rest of the sweep byte-stable and why these scenarios
## are the only way any of them is reachable.
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
const DEFECT_MODE := "mission_defection"
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
## The Long Front's exemplar mission, for the defection frame: its board is the
## one that already names a unit of the army a beat would take it from — Morn's
## garrison in the ruins, which the mission's own `DestroyUnit` reads.
const DEFECT_CAMPAIGN := &"the_long_front"
const DEFECT_MISSION := &"lf08_after_hammerfall"
const GARRISON := &"ruin_garrison"
const DEFECT_EVENT := &"the_garrison_turns"
const GARRISON_ARMY := 2
## The fact the defection is gated on, which makes the frame CD4's live proof as
## well: the consequence ledger is what decides whether this board opens with the
## garrison on our side, and with the fact missing the beat does not fire and
## `_run_defection` says so.
const GARRISON_FLAG := &"wardens_wavered"

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


## Stages this scenario's launch, if this boot is one of its three. Called from
## `Battle._ready` before it asks MatchConfig for a request; inert for every
## other run, capture or not.
static func stage() -> void:
	if not BattleScenarioDriver.requested():
		return
	var demo := BattleScenarioDriver.boot_demo()
	if demo not in [MODE, EVENT_MODE, DEFECT_MODE]:
		return
	var defecting := demo == DEFECT_MODE
	var campaign_id := DEFECT_CAMPAIGN if defecting else CAMPAIGN
	var mission_id := DEFECT_MISSION if defecting else MISSION
	var campaign := CampaignDB.load_default().by_id(campaign_id)
	var mission := campaign.mission(mission_id) if campaign != null else null
	if mission == null:
		push_error("capture: no mission '%s' to pose a campaign frame on" % mission_id)
		return
	var progress := CampaignState.begin(campaign)
	if defecting:
		mission = _posed_defection(mission)
		progress.flags[GARRISON_FLAG] = 1
	MatchConfig.stage(CampaignSession.begin(campaign, mission, progress))


## The shipped mission carrying one beat of the scenario's own: no authored
## mission defects yet, and a repaint on a unit that changed army can only be
## photographed on a board where one does. It is a copy rather than the resource
## `CampaignDB` handed over, and it states the whole event list rather than
## appending to it, so nothing shipped is altered and the frame is the defection
## alone. Day one is the trigger because `Battle` fires its due beats on the board
## it opens on, which is a boundary no play has to reach — and the flag beside it
## is what makes this the same board a mission opens differently on because of an
## earlier one.
static func _posed_defection(shipped: MissionDefinition) -> MissionDefinition:
	var trigger := DayReachedTrigger.new()
	trigger.day = 1
	var condition := FlagCondition.new()
	condition.flag = GARRISON_FLAG
	var remembered := FlagTrigger.new()
	remembered.condition = condition
	var defection := DefectEffect.new()
	defection.from_team = GARRISON_ARMY
	defection.to_team = shipped.player_team
	defection.tags = [GARRISON]
	var beat := MissionEvent.new()
	beat.id = DEFECT_EVENT
	beat.triggers = [trigger, remembered]
	beat.effects = [defection]
	var posed := shipped.duplicate() as MissionDefinition
	posed.events = [beat]
	return posed


func run(mode: String) -> String:
	if mode == EVENT_MODE:
		return await _run_event()
	if mode == DEFECT_MODE:
		return _run_defection()
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
	var board_error := _board_error()
	if board_error != "":
		return board_error
	var card := _battle.animator.mission_speech
	await _battle.get_tree().process_frame
	var error := card.layout_error()
	if error != "":
		return error
	return _in_band("mission speech card", card)


## Morn's garrison changes sides, and the frame is what it is wearing afterwards.
## The beat has already fired by the time this runs — `Battle` fires the board it
## opens on — so the pose needs no play to reach it and cannot depend on what the
## computer decided to do. `_board_error` is the check the picture cannot make:
## a unit that answers to the player while still drawn in the army it left
## photographs perfectly well.
func _run_defection() -> String:
	if not CampaignSession.tally.has_fired(DEFECT_EVENT):
		return "the '%s' beat did not fire on the board it opens on" % DEFECT_EVENT
	var defector := MissionObjective.tagged_unit(_battle.game, GARRISON)
	if defector == null:
		return "the board no longer stands the unit called '%s'" % GARRISON
	var ours := CampaignSession.mission.player_team
	if defector.team != ours:
		return "'%s' is still army %d's rather than %d's" % [GARRISON, defector.team, ours]
	return _board_error()


## Whether every unit the sim holds is drawn, and drawn in its own side's
## colours. Read back off the live sprites rather than photographed, because both
## are things a scripted beat breaks without the frame looking wrong: a landed
## column nothing draws is an empty square the player is then attacked from, and
## a defector still wearing the army it left is a unit that answers to somebody
## else. `SideIdentity` owns which colours those are, so the check asks it.
func _board_error() -> String:
	var identity := _battle.view.identity
	for unit in _battle.game.units:
		var sprite := _battle.view.sprite_for(unit)
		if sprite == null:
			return "the board draws nothing for the %s at %s" % [unit.type.id, unit.cell]
		if sprite.atlas_row != identity.atlas_row(unit.team):
			return (
				"the %s at %s is drawn in row %d rather than army %d's"
				% [unit.type.id, unit.cell, sprite.atlas_row, unit.team]
			)
	return ""


## The board band the two docked bars leave over, which is what every floating
## surface is checked against.
func _in_band(what: String, control: Control) -> String:
	var frame := _battle.get_viewport().get_visible_rect().size
	var band := Rect2(Vector2(0, UiTheme.HUD_TOP_H), Vector2(frame.x, frame.y - UiTheme.HUD_BARS_H))
	if not band.encloses(control.get_global_rect()):
		return "the %s %s does not fit the board band %s" % [what, control.get_global_rect(), band]
	return ""
