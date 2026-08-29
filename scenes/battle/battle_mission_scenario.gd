class_name BattleMissionScenario
extends BattleScenario
## The four captures that play a campaign mission: the in-battle objective card
## (campaign-depth CD2), a scripted beat landing on the board, a scripted beat
## changing a unit's allegiance (CD3) and the pause menu opened over a mission,
## where the Briefing row lives. All four are down for every skirmish, which is
## what keeps the rest of the sweep byte-stable and why these scenarios are the
## only way any of them is reachable.
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
## driver is what raises a complaint made of a whole scenario.

const MODE := "objective_panel"
const EVENT_MODE := "mission_event"
const DEFECT_MODE := "mission_defection"
const MAP_MENU_MODE := "campaign_mapmenu"
const WIN_MODE := "campaign_win_stops_ai"
## What this class owns, read by `stage` and by the driver's dispatch, so neither
## can learn of a mission scenario the other has not.
const MODES: Array[String] = [MODE, EVENT_MODE, DEFECT_MODE, MAP_MENU_MODE, WIN_MODE]
## The ceiling on a wait for a turn or a state to arrive, so a flow that never
## gets there is named by the check rather than left to the sweep's own deadline.
const TURN_WAIT_FRAMES := 1800
## How long the finished board is then watched to see whether anything moves on
## it. Wall clock rather than frames: what is being watched for is a runner that
## keeps planning, and the lockup arms its own buttons on a real half-second timer.
const SETTLE_MS := 1500
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
## Open ground on that same board, where a confirm selects nothing and so opens
## the map menu — the `mapmenu` scenario's press, made on a mission.
const OPEN_GROUND := Vector2i(7, 1)
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


## Stages this scenario's launch, if this boot is one of its three. Called from
## `Battle._ready` before it asks MatchConfig for a request; inert for every
## other run, capture or not.
static func stage() -> void:
	if not BattleScenarioDriver.requested():
		return
	var demo := BattleScenarioDriver.boot_demo()
	if demo not in MODES:
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
	elif demo == WIN_MODE:
		# That scenario swaps this mission's objectives mid-turn, and the loader
		# caches the shipped resource for the whole process — the other campaign
		# scenarios in the same sweep stage the very same mission. A copy is what
		# keeps the swap inside this frame.
		mission = mission.duplicate() as MissionDefinition
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
	if mode == MAP_MENU_MODE:
		return await _run_map_menu()
	if mode == WIN_MODE:
		return await _run_win_stops_ai()
	return await _run_panel()


## The pause menu, opened over a mission rather than over a skirmish, which is
## the only board its Briefing and Objectives rows are offered on. The press is
## `mapmenu`'s — a confirm on ground holding nothing to select — and the rows are
## read back off the authority that builds them, because a menu missing a row, or
## carrying it somewhere else, photographs perfectly well.
func _run_map_menu() -> String:
	_battle.confirm_at(OPEN_GROUND)
	await _until_state(Battle.State.MENU)
	var ids: Array[StringName] = []
	for row in BattleMenus.map_actions(_battle.game):
		ids.append(row["id"])
	var at := ids.find(&"briefing")
	if at < 1 or ids[at - 1] != &"commanders":
		return "the map menu offers no Briefing row after Commanders: %s" % [ids]
	if ids.find(&"objectives") != at + 1:
		return "the map menu offers no Objectives row after Briefing: %s" % [ids]
	# The label is read off the menu that is actually up rather than off a second
	# call to the builder: what it prints is the card's own answer, and a menu told
	# the wrong way round would offer to raise a card that is already standing.
	var said := _menu_label(&"Objectives: ")
	if said != "Objectives: On":
		return "the open card's row reads '%s'" % said
	return BattleScenario.band_error(_battle, "map menu", _battle.action_menu)


## What the menu on screen says on the row starting with `prefix`, minus the
## two-character arm marker every row carries.
func _menu_label(prefix: String) -> String:
	for row in _battle.action_menu.rows.get_children():
		var text: String = (row as Button).text.substr(2)
		if text.begins_with(prefix):
			return text
	return ""


func _run_panel() -> String:
	var panel := _battle.view.mission_panel
	# O lowers the card and raises it again, walked here rather than only
	# photographed: the card covers board, so a player has to be able to put it away,
	# and a lowered card that never came back is the failure that leaves a mission
	# unreadable. It ends up back where it started, which is what keeps the frame
	# this scenario exists to capture byte-stable.
	#
	# The key lowers it and the pause menu's row raises it, which is the one claim
	# worth driving: the two run the same toggle on the card's own state, so a row
	# that grew a second copy of it would leave the card down here.
	panel.toggle(_battle.game)
	if panel.visible:
		return "the objective panel stayed up after O lowered it"
	await BattleCampaign.run_row(_battle, &"objectives")
	if not panel.visible:
		return "the objective panel did not come back up from the pause menu's row"
	# The card measures and places itself a frame after its rows were added, like
	# the teaching strip and the seat strip.
	await _battle.get_tree().process_frame
	var error := panel.layout_error()
	if error != "":
		return error
	return BattleScenario.band_error(_battle, "objective panel", panel)


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
	return BattleScenario.band_error(_battle, "mission speech card", card)


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


## A mission decided in the middle of the computer's turn stops the match.
##
## The verdict never touches `game.winner` — a campaign is won on its objectives —
## so every "is this over?" that asked the board alone said no, the runner planned
## the next command under the raised end card, and the state it overwrote left the
## card's own buttons guarded shut. The match played on with a dead screen over it,
## which photographs perfectly well: this is a check first and a picture second.
##
## The mission is won mid-turn by giving it an objective the board already meets,
## swapped in once the computer is on turn — before that, the player's own end-turn
## would be the boundary that decided it and the runner would never start.
func _run_win_stops_ai() -> String:
	var mission := CampaignSession.mission
	var seat: int = mission.ai_teams[0]
	await BattleFeedbackScenario.new(_battle).end_turn_anyway()
	var error := await _wait_for_team(seat)
	if error != "":
		return error
	_win_on_the_board_as_it_stands(mission)
	error = await _wait_for_state(
		Battle.State.VICTORY, "the mission being won on the computer's turn"
	)
	if error != "":
		return error

	var day := _battle.game.day
	var until := Time.get_ticks_msec() + SETTLE_MS
	while Time.get_ticks_msec() < until:
		await _battle.get_tree().process_frame
	if _battle.state != Battle.State.VICTORY:
		return "the finished mission left state %s; the match is still being played" % _battle.state
	if _battle.game.day != day:
		return "the finished mission ran on to day %d from day %d" % [_battle.game.day, day]
	# The lockup arms its buttons half a second after it opens, and only while the
	# scene is still on it. A match that played on underneath leaves them shut for
	# good, which is the dead card the player met.
	if _battle.victory_screen.rematch_button.mouse_filter != Control.MOUSE_FILTER_STOP:
		return "the end card's action button never took the mouse back"
	return ""


## Replaces the mission's win condition with one this board already satisfies, so
## the computer's next command is the boundary the verdict is taken at. The
## session's runtime reads the same definition object — the copy `stage` made —
## so the swap is seen there and nowhere else.
func _win_on_the_board_as_it_stands(mission: MissionDefinition) -> void:
	var now := SurviveUntilDayObjective.new()
	now.text = "Hold the line"
	now.day = _battle.game.day
	var met: Array[MissionObjective] = [now]
	mission.objectives = met
	mission.bonus_objectives = []


## Bounded waits, so a flow that never arrives is named rather than left to the
## sweep's own deadline, which only knows the scenario.
func _wait_for_team(team: int) -> String:
	for frame in TURN_WAIT_FRAMES:
		if _battle.game.current_team == team:
			return ""
		await _battle.get_tree().process_frame
	return "team %d never came up to play" % team


func _wait_for_state(wanted: Battle.State, what: String) -> String:
	for frame in TURN_WAIT_FRAMES:
		if _battle.state == wanted:
			return ""
		await _battle.get_tree().process_frame
	return "%s left the scene in state %s, not %s" % [what, _battle.state, wanted]
