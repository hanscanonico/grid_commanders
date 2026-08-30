class_name BattleScenarioDriver
extends BattleScenario
## Dev-only: parses the capture command line and drives Battle through scripted
## flows for automated screenshots (`make screenshot`, `make smoke`).
##
## Depends on Battle; nothing on the gameplay path depends on this. Scenarios
## drive the same entry points player input reaches — `confirm_at`,
## `set_cursor_cell`, and the real ActionMenu — rather than calling commands
## directly, so a scenario that stops working means the flow it exercises
## broke, not that the driver drifted from the game.
##
## Battle holds the driver in a member for the duration: `run` awaits, and a
## RefCounted nobody references is freed mid-scenario.

## `Godot --path . -- --screenshot=/abs/path.png [--select=x,y | --demo=MODE]`
## boots the scene, optionally drives a demo, saves one frame, and quits.
## --select previews a unit's movement; see `_run_demo` for the demo modes.
## The capture flag itself belongs to ScreenshotUtil — every scene that
## photographs itself reads it from the one place it is spelled.
const SELECT_ARG := "--select"
const DEMO_ARG := "--demo"
## What `--select` reads as when it names no cell.
const NO_CELL := Vector2i(-1, -1)

## Demos fix the seed so a capture of the same scenario is the same frame.
const DEMO_SEED := 2026
## The two units `stage_rout` plays the last shot of the match between, as the
## default board parks them: Blue's south-east survivor and the Red tank in range
## of it without moving.
const ROUT_LAST_ENEMY_CELL := Vector2i(9, 8)
const ROUT_ATTACKER_CELL := Vector2i(8, 8)
## The first-match teaching strip (COM-12). `mission_strip` poses it on a fresh
## install's very first frame — the objective, the SELECT step, and the four
## still to come — and `mission_strip_retired` walks a real selection and a real
## move through the flow so the strip is caught two steps in, which is the half a
## still frame cannot prove: that a step retires when the player performs it.
const MISSION_STRIP_MODE := "mission_strip"
const MISSION_STRIP_RETIRED := MISSION_STRIP_MODE + "_retired"

## COM-57's fogged overlay check. Blue's infantry comes up two tiles from Red's
## tank at (8,8): inside its sight and so previewable, on free plains — (9,8) is
## the frontline Blue tank's — with a reach that runs off into ground Red has no
## eyes on.
const PREVIEW_FOG_FROM := Vector2i(15, 10)
const PREVIEW_FOG_TO := Vector2i(10, 8)

## One general per faction, so the commander sheet's scroll probe poses the 2x2 a
## four-army board deals — the layout whose cards clip to their portrait band.
const FOUR_ARMY_PROBE_COMMANDERS: Array[StringName] = [
	&"rhea_sol", &"viktor_draeg", &"mara_voss", &"cass_orlov"
]

var _shot_path := ""
var _select_cell := NO_CELL
var _demo := ""


func _init(battle: Battle) -> void:
	super._init(battle)
	_shot_path = ScreenshotUtil.requested()
	var args := CmdArgs.user()
	_select_cell = _selected_cell(args)
	_demo = CmdArgs.value(args, DEMO_ARG)
	# A smoke batch (--demos=, COM-117) supersedes both — see BattleCaptureBatch.
	if BattleCaptureBatch.adopt(battle):
		_demo = BattleCaptureBatch.demo()
		_shot_path = BattleCaptureBatch.shot_path()


## The cell `--select` names, or NO_CELL when it names none.
static func _selected_cell(args: PackedStringArray) -> Vector2i:
	var parts := CmdArgs.value(args, SELECT_ARG).split(",")
	if parts.size() != 2:
		return NO_CELL
	return Vector2i(int(parts[0]), int(parts[1]))


## True when the command line asked for any scripted flow at all — a screenshot,
## a demo, a selection preview, or a whole smoke batch. Static because Battle
## asks it *instead of* building a driver, so an ordinary match never pays for
## one; a batch is a capture whatever else it carries.
static func requested() -> bool:
	if ScreenshotUtil.requested() != "" or BattleCaptureBatch.requested() != "":
		return true
	var args := CmdArgs.user()
	return CmdArgs.value(args, DEMO_ARG) != "" or _selected_cell(args).x >= 0


## The demo this boot runs, asked before any driver exists to hold it — which is
## why it is static and public: BattleMissionScenario stages its launch before
## Battle builds anything. A batch entry supersedes a lone `--demo=`, exactly as
## `_init` reads them.
static func boot_demo() -> String:
	if BattleCaptureBatch.requested() != "":
		return BattleCaptureBatch.demo()
	return CmdArgs.value(CmdArgs.user(), DEMO_ARG)


## Whether this run is one of the two that exist to photograph the first-match
## teaching strip. Every other capture pins the hints away, exactly as it pins
## the game speed: the strip's presence would otherwise depend on how much of the
## game the person running `make smoke` had already played (COM-12).
func wants_mission_strip() -> bool:
	return _demo.begins_with(MISSION_STRIP_MODE)


func run() -> void:
	# Demos and captures drive the board, so neither the handoff panel nor the
	# day-1 banner may sit on top, except the flow whose subject is that banner.
	_battle.leave_handoff()
	if _demo != "turn_banner_build_attempt":
		_battle.animator.hide_banner()
	if _demo != "":
		await _run_demo(_demo)
	elif _select_cell.x >= 0:
		_demo_select(_select_cell)
	if _failed or not _fog_hides_unseen():
		_battle.get_tree().quit(1)
		return
	if _shot_path != "":
		await BattleCaptureBatch.finish_capture(_battle, _shot_path)
		# A staged mission does not outlive its frame: the next scenario in the
		# batch — the menu's included, where a live session reopens a hub over the
		# picture — boots with no campaign in play.
		CampaignSession.clear()


## Every unit still on screen is one the viewing team is allowed to see.
##
## Checked here because a fog leak is silent: the frame renders either way, so a
## scenario that only proves it produced one would pass straight through the
## bug. Quitting non-zero is what turns that into a failed smoke run. With fog
## off there is nothing to hide and the whole check is skipped.
func _fog_hides_unseen() -> bool:
	if not _battle.game.fog_enabled:
		return true
	for unit in _battle.game.units:
		var sprite := _battle.view.sprite_for(unit)
		if sprite != null and sprite.visible and not _battle.perspective.can_see_unit(unit):
			_fail(
				(
					"fog leak: %s at %s is drawn but team %d cannot see it"
					% [unit.type.id, unit.cell, _battle.game.current_team]
				)
			)
			return false
	return true


## Drives real flows through the same handlers a player's input reaches:
## attack stops at the targeting preview and resolve fires, both with the
## frontline tanks; capture takes the city at (3,4) with the infantry at (4,3);
## build buys at the red base and buildmenu stops at its open shop list;
## endturn hands the turn to Blue; aiturn does the same and then waits out
## Blue's whole AI turn, back to Red's next turn;
## transport runs load -> drive -> drop, and load, cargo, and drop stop that
## same chain at the Load menu, the loaded APC's panel, and the drop-target
## picker; supply holds the APC next to its infantry so Supply is offered;
## mapmenu stops at the map menu (End Turn / Save); leave_confirm walks the route out
## of a running match, from the map menu's two exit rows to the confirmation the
## unsaved one opens; after_build_menu opens the tallest menu in the game and then
## the shortest, which is the order the shared panel's size has to survive;
## ambush and vanish are the same
## staged board with Sable Wren's power down and up; victory routs Blue through
## a real attack so the victory screen comes up. The Command Power family is
## BattlePowerScenario's; of the commander-identity captures (plan G3, COM-18)
## what is left here is commander_info, which opens the commander reference from
## the map menu, and commander_victory, which wins with a general so the victory
## lockup is fronted by a portrait.
##
## Modes that stop early return without falling through to the rest of the
## chain; `run` still takes the capture. A name that matches nothing here — the
## cut-in families are dispatched by prefix first, and never reach the match —
## fails the run instead, since a board no flow ever touched still photographs
## perfectly well and would otherwise be reported as a scenario that passed.
func _run_demo(mode: String) -> void:
	var tree := _battle.get_tree()
	await tree.process_frame
	_battle.game.rng.seed = DEMO_SEED  # deterministic demo
	# The cut-in modes carry a matchup in the name, so they are parsed rather
	# than matched — see BattleCutsceneScenario.
	if (
		mode.begins_with(BattleCutsceneScenario.CAPTURE_CUT_IN_MODE)
		or mode.begins_with(BattleCutsceneScenario.CUT_IN_MODE)
	):
		if await BattleCutsceneScenario.new(_battle).run(mode):
			_failed = true
		return
	# The campaign family is asked of its own class for the same reason: the modes
	# that play a mission are BattleMissionScenario's list, not a second copy here.
	if mode in BattleMissionScenario.MODES:
		_fail_if(await BattleMissionScenario.new(_battle).run(mode))
		return
	# And the touch dock's, which runs only under --mobile.
	if mode in BattleMobileScenario.MODES:
		_fail_if(await BattleMobileScenario.new(_battle).run(mode))
		return
	# And the driven feedback family, for the same reason.
	if mode in BattleFeedbackScenario.MODES:
		_fail_if(await BattleFeedbackScenario.new(_battle).run(mode))
		return
	# And the Command Power family. Asked after the feedback list, which holds a
	# `power_range_readout` of its own, so neither family has to know the other's
	# names to keep off them.
	if mode in BattlePowerScenario.MODES:
		_fail_if(await BattlePowerScenario.new(_battle).run(mode))
		return
	match mode:
		"attack", "resolve":
			_battle.confirm_at(Vector2i(8, 8))  # select the red tank
			_battle.confirm_at(Vector2i(8, 8))  # fire in place
			await _until_state(Battle.State.MENU)
			_battle.action_menu.choose(&"fire")
			await _until_state(Battle.State.TARGETING)
			if mode == "attack":
				return
			_battle.confirm_at(_battle.cursor_cell)  # fire at the blue tank
			await _until_state(Battle.State.IDLE)
		"capture":
			_battle.confirm_at(Vector2i(4, 3))  # select the red infantry
			_battle.confirm_at(Vector2i(3, 4))  # move onto the neutral city
			await _until_state(Battle.State.MENU)
			_battle.action_menu.choose(&"capture")
			await _until_state(Battle.State.IDLE)
			_battle.set_cursor_cell(Vector2i(3, 4))  # show capture progress
		"build", "buildmenu":
			_battle.set_cursor_cell(Vector2i(3, 2))  # red base
			_battle.confirm_at(Vector2i(3, 2))  # open the build menu (funds 2000)
			await _until_state(Battle.State.MENU)
			if mode == "buildmenu":
				return
			_battle.action_menu.choose(&"infantry")
			await _until_state(Battle.State.IDLE)
		"endturn":
			await BattleFeedbackScenario.new(_battle).end_turn_anyway()
		"load", "cargo", "drop", "transport":
			await _run_transport_demo(mode)
		"divemenu", "dive":
			await _run_dive_demo(mode)
		"supply":
			_battle.confirm_at(Vector2i(3, 3))  # select the red APC
			_battle.confirm_at(Vector2i(3, 3))  # stay put -> menu offers Supply
			await _until_state(Battle.State.MENU)
		"leave_confirm":
			await _stage_leave_routes()
		"after_build_menu":
			await _stage_menu_after_build_menu()
		"turn_banner_build_attempt", "outcome_mash_guard", "mixed_seat_handoff", "ai_pause", "auto_off":
			_fail_if(await BattleTransitionScenario.new(_battle).run(mode))
		"ambush", "vanish":
			_run_vanish_demo(mode)
		"field_overlays":
			_fail_if(await BattleOverlayScenario.new(_battle).run())
		"preview_fog":
			await _stage_preview_fog()
		MISSION_STRIP_MODE, MISSION_STRIP_RETIRED:
			await _stage_mission_strip(mode)
		"commander_info":
			await _stage_commander_info()  # both-sides reference from the map menu
		"commander_victory", "victory", "side_victory":
			_fail_if(await BattleVictoryScenario.new(_battle).run(mode))
		"aiturn":
			# hand the turn to the Blue AI and wait until it plays back to Red
			await BattleFeedbackScenario.new(_battle).end_turn_anyway()
			while (
				_battle.game.winner == 0
				and not (_battle.game.current_team == 1 and _battle.state == Battle.State.IDLE)
			):
				await tree.process_frame
		_:
			_fail("unknown demo mode: %s" % mode)


## load -> drive -> drop, with three modes stopping partway along the chain.
func _run_transport_demo(mode: String) -> void:
	_battle.confirm_at(Vector2i(4, 3))  # select the red infantry
	_battle.confirm_at(Vector2i(3, 3))  # onto the APC -> Load menu
	await _until_state(Battle.State.MENU)
	if mode == "load":
		return
	_battle.action_menu.choose(&"load")
	await _until_state(Battle.State.IDLE)
	if mode == "cargo":
		_battle.set_cursor_cell(Vector2i(3, 3))  # the bar shows the APC as CARRYING
		return
	_battle.confirm_at(Vector2i(3, 3))  # select the loaded APC
	_battle.confirm_at(Vector2i(3, 5))  # drive it south
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"drop_0")  # rows are per-passenger now (see BattleMenus)
	await _until_state(Battle.State.DROP_TARGETING)
	if mode == "drop":
		return
	_battle.confirm_at(_battle.cursor_cell)  # drop at the first offered cell
	await _until_state(Battle.State.IDLE)
	_battle.set_cursor_cell(Vector2i(3, 5))  # show the APC in the panel


## Select the submarine, offer it the Dive row, and take it under. Runs on
## the_straits rather than the default board, since the default has no water —
## tools/smoke_scenarios.sh passes the map for these two modes.
##
## `divemenu` stops with the menu open, which is what proves the row is offered at
## all; `dive` goes through with it and captures the boat drawn submerged, faint
## for its own side. Together they are the whole new interaction: a menu entry that
## exists only for one unit, and a command behind it that changes what the other
## side can see.
func _run_dive_demo(mode: String) -> void:
	var sub := Vector2i(11, 5)
	_battle.confirm_at(sub)  # select the red sub
	_battle.confirm_at(sub)  # stay put -> the action menu
	await _until_state(Battle.State.MENU)
	if mode == "divemenu":
		return
	_battle.action_menu.choose(&"dive")
	await _until_state(Battle.State.IDLE)
	_battle.set_cursor_cell(sub)  # panel shows the boat as Dived


## Sable Wren's Vanish (decision D4), seen from Red's side of the screen.
##
## Two Blue units stand in Woods with a Red unit right beside each — the one
## arrangement the plain Woods rule already reveals, since woods hide anything
## further than a tile away from a viewer no matter whose turn it is. `ambush`
## captures that board with the power down and `vanish` captures it with the
## power up, and the pair is the whole point: D4 reworked Vanish *because* its
## original wording ("revealed only from an adjacent tile") described what
## Vision does anyway, so only a frame where an adjacent enemy stops seeing them
## shows the rework doing something.
##
## Fog is turned on here rather than left to a `--fog` caller: with it off
## nothing is hidden from anyone and both modes capture the same picture, which
## would make the comparison silently vacuous.
##
## Blue's power is raised directly because PowerCommand only ever fires for the
## team whose turn it is, and the frame under test is Red's. What the capture
## proves is a presentation question — that the board honours `hides_unit` —
## and the sim-side rules (who is hidden, and for how long) are pinned in
## tests/unit/test_sable_wren.gd instead.
func _run_vanish_demo(mode: String) -> void:
	var game := _battle.game
	game.fog_enabled = true
	game.set_commander(2, _battle.commander_db.by_id(&"sable_wren"))
	# Blue moves into the treeline on Red's flank; the Red tank comes up from the
	# sandbox so the second wood has a viewer next to it as well.
	game.unit_at(Vector2i(15, 10)).cell = Vector2i(4, 5)  # blue infantry -> woods
	game.unit_at(Vector2i(17, 9)).cell = Vector2i(5, 5)  # blue mech -> woods
	game.unit_at(Vector2i(8, 8)).cell = Vector2i(5, 4)  # red tank -> beside them
	if mode == "vanish":
		game.commander_state(2).power_active = true
	_battle.view.sync_sprites()
	_battle.refresh_fog()
	_battle.view.restage_identity()  # Sable Wren's Verdant recolours Blue after the fog pass
	_battle.set_cursor_cell(Vector2i(5, 5))  # the panel names whatever is on the tile


## COM-57, and the sibling of `ambush`/`vanish` in every structural sense: a fogged
## board where the thing under test is what the overlay is allowed to *say*.
##
## Clicking an enemy you cannot command previews its reach, and R adds its fire ring.
## Both used to be filled straight off `MovementResolver`/`AttackRange`, which answer
## for the whole board with the *mover's* knowledge — so the preview was drawn over
## ground the viewer had never scouted, and worse, `reachable` walls that unit off at
## enemies it can see and plans it through the ones it cannot, so the outline alone
## reported which of the viewer's own pieces it had spotted. Both are now filled with
## the viewer's knowledge and then masked to the viewer's scouted ground.
##
## Checked rather than photographed, like `leave_confirm` and `power_mapmenu`: an
## overlay painted three cells too wide renders a perfectly good picture. The board is
## read back off the live TileMapLayers, so what is asserted is what is on screen.
func _stage_preview_fog() -> void:
	var game := _battle.game
	game.fog_enabled = true
	# Blue's infantry comes up two tiles from Red's tank, which is the whole staging:
	# close enough to be seen and so previewable, with a reach that runs off into
	# ground Red has no eyes on. The destination is checked rather than assumed: a
	# board edit that put something there would otherwise stack two units on one
	# cell, and `unit_at` would hand the preview whichever the map listed first.
	var enemy := game.unit_at(PREVIEW_FOG_FROM)
	if enemy == null:
		_fail("preview_fog: no blue infantry at %s" % PREVIEW_FOG_FROM)
		return
	if game.unit_at(PREVIEW_FOG_TO) != null:
		_fail(
			(
				"preview_fog: %s is already occupied, so the staging would stack two units"
				% PREVIEW_FOG_TO
			)
		)
		return
	enemy.cell = PREVIEW_FOG_TO
	_battle.view.sync_sprites()
	_battle.refresh_fog()
	if not _battle.perspective.can_see_unit(enemy):
		_fail("preview_fog: the enemy staged to be previewed is not visible to Red")
		return
	var whole := MovementResolver.reachable(game, enemy).cells().size()
	_battle.confirm_at(enemy.cell)  # a unit Red cannot command -> preview, not select
	await _until_state(Battle.State.PREVIEW)
	var shown := _check_overlay_scouted("move preview", _battle.overlays.move_layer)
	# Vacuous otherwise: an overlay narrowed down to nothing, or one that never had a
	# cell to lose, would pass the check above without proving anything. `whole` is
	# what the raw authority would have painted, so this is the withholding itself.
	if shown >= whole:
		_fail(
			(
				"preview_fog: the preview shows all %d cells the raw fill reaches, so nothing was withheld"
				% whole
			)
		)
		return
	_battle.toggle_range()
	_check_overlay_scouted("fire ring", _battle.overlays.attack_layer)
	_battle.set_cursor_cell(enemy.cell)


## Every cell painted on `layer` is ground the viewer has scouted. Returns how many
## there were, so a caller can also refuse an overlay that proves nothing by being
## empty. Reads the live layer rather than the array that was handed to it: what is
## on the board is the claim being made.
func _check_overlay_scouted(what: String, layer: TileMapLayer) -> int:
	var cells := layer.get_used_cells()
	if cells.is_empty():
		_fail("preview_fog: the %s painted nothing, so there is nothing to check" % what)
		return 0
	for cell in cells:
		if not _battle.perspective.can_see_cell(cell):
			_fail("preview_fog: the %s paints %s, which the viewer has not scouted" % [what, cell])
			return cells.size()
	return cells.size()


## The route out of a running match (COM-16), walked the way a player walks it: the
## map menu, which now carries both exits, and then the second press the unsaved
## one asks for. Reached through the real row rather than by opening the
## confirmation directly — the finding was that no route existed, so the route is
## what the scenario walks — and it stops there, since going through would leave
## the battle scene with nothing left to photograph.
##
## Checked rather than eyeballed, like power_mapmenu: the board renders behind the
## opaque bars, so a menu two rows taller than it used to be, or a confirmation
## that armed its destructive row, photographs exactly as well as the right one.
func _stage_leave_routes() -> void:
	_battle.confirm_at(Vector2i(10, 5))  # empty road tile -> map menu
	await _until_state(Battle.State.MENU)
	_check_rows("map menu", BattleMenus.map_actions(_battle.game), [&"save_and_quit", &"quit"])
	_check_in_band("map menu", _battle.action_menu)
	var map_menu_h := _battle.action_menu.get_global_rect().size.y
	_battle.action_menu.choose(&"quit")
	var rows := BattleMenus.abandon_confirm_actions()
	_check_rows("abandon confirmation", rows, [&"cancel", &"abandon"])
	if not rows.is_empty() and rows[0].id != &"cancel":
		# ActionMenu arms its first enabled row: a confirmation that led with the
		# abandon would sit there with the match under the Enter just pressed.
		_fail("the abandon confirmation arms '%s', not the row that keeps the match" % rows[0].id)
	_check_in_band("abandon confirmation", _battle.action_menu)
	# Guards ActionMenu.reset_size(): without it the two-row confirmation stands
	# inside the seven-row map menu's leftover panel, and the enclosure test above
	# still passes. Two rows against seven, so the comparison needs no threshold.
	var confirm_h := _battle.action_menu.get_global_rect().size.y
	if confirm_h >= map_menu_h:
		_fail(
			(
				"the abandon confirmation stands %.0fpx tall, no shorter than the map menu's %.0fpx"
				% [confirm_h, map_menu_h]
			)
		)


## The ghost panel (COM-11): the unit, build and map menus are one shared
## ActionMenu, and a PanelContainer grows to fit its rows but never shrinks back on
## its own, so the eleven-row build menu used to leave its slab standing behind
## every short menu opened afterwards — over the board, every turn.
##
## Walked in that order — build menu, Cancel, then a unit's own Wait/Cancel —
## because the stale size belongs to the *sequence*: either menu opened on its own
## photographs perfectly well, which is why `buildmenu` never caught it. Measured
## rather than eyeballed for the same reason leave_confirm is; the leftover panel is
## translucent chrome over a board that renders either way.
func _stage_menu_after_build_menu() -> void:
	_battle.set_cursor_cell(Vector2i(3, 2))  # red base
	_battle.confirm_at(Vector2i(3, 2))  # the tallest and widest menu in the game
	await _until_state(Battle.State.MENU)
	var build_menu := _battle.action_menu.get_global_rect().size
	_battle.action_menu.choose(&"cancel")
	await _until_state(Battle.State.IDLE)
	_battle.confirm_at(Vector2i(4, 3))  # select the red infantry
	_battle.confirm_at(Vector2i(4, 3))  # stay put -> Wait / Cancel, the shortest menu
	await _until_state(Battle.State.MENU)
	_check_in_band("unit menu", _battle.action_menu)
	var shown := _battle.action_menu.rows.get_child_count()
	if shown != 2:
		_fail("the infantry's menu drew %d rows, not the two the comparison rests on" % shown)
		return
	# Both axes: the build menu is the widest menu as well as the tallest — every row
	# carries an icon and a price — so a panel that only shrank in height would still
	# hang off to the side of the two words under it.
	var unit_menu := _battle.action_menu.get_global_rect().size
	if unit_menu.x >= build_menu.x or unit_menu.y >= build_menu.y:
		var sizes := [unit_menu, build_menu]
		_fail("the two-row unit menu measures %s, no smaller than the build menu's %s" % sizes)


## Every id in `wanted` is on the menu, read off the rows the menu was built from.
## A row that quietly stopped being offered fails the run rather than leaving a
## player with nowhere to go.
func _check_rows(what: String, rows: Array[Dictionary], wanted: Array[StringName]) -> void:
	var ids: Array = rows.map(func(row: Dictionary) -> StringName: return row.id)
	for id in wanted:
		if not ids.has(id):
			_fail("the %s offers %s, with no '%s' row" % [what, ids, id])


## The reporting wrapper over the shared ruler: this driver reports by flag
## rather than by return value, so it is where band_error's complaint is raised.
func _check_in_band(what: String, control: Control) -> void:
	_fail_if(band_error(_battle, what, control))


## The first-match teaching strip (COM-12), on a hint set Battle pinned empty for
## this run so it opens exactly as a fresh install's first frame does.
##
## `mission_strip` poses that opening. `mission_strip_retired` walks a whole first
## turn — select, move, build, end turn — through the same handlers a player's
## input reaches, and then checks that the four steps performed are retired and
## the strip has moved on to CAPTURE. That is the acceptance criterion a still
## frame cannot show, since a strip stuck on SELECT photographs just as well as
## one that advanced; and Capture is the step deliberately *not* performed, so it
## is the witness that a step nobody did stays up. Ending the turn also proves the
## rule with the most to get wrong — the turn has to pass off a *human* side, or
## the computer would retire the player's hint by playing its own turn.
func _stage_mission_strip(mode: String) -> void:
	var strip: MissionStrip = _battle.view.mission_strip
	var expected: StringName = &"select"
	if mode == MISSION_STRIP_RETIRED:
		expected = &"capture"
		await _walk_first_turn()
	await _settle_layout()  # the strip measures and centres itself a frame late
	if not strip.visible:
		_fail("the mission strip is down with %s still to teach" % expected)
		return
	if strip.current_step_id() != expected:
		_fail("the mission strip teaches '%s', not '%s'" % [strip.current_step_id(), expected])
	_check_in_band("mission strip", strip)


## Every step of the loop except the capture, in the order the strip teaches them.
## Cells are the tutorial board's, the only one the strip teaches on (COM-122).
func _walk_first_turn() -> void:
	_battle.confirm_at(Vector2i(4, 3))  # select the road infantry -> retires "select"
	_battle.confirm_at(Vector2i(4, 2))  # move it up the road toward the neutral city
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"wait")  # commit the move -> retires "move"
	await _until_state(Battle.State.IDLE)
	_battle.confirm_at(Vector2i(2, 1))  # the friendly base -> the build menu
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"infantry")  # -> retires "build"
	await _until_state(Battle.State.IDLE)
	# -> retires "end_turn"; the side still has unacted units, so this answers the
	# COM-14 guard the map menu now opens.
	await BattleFeedbackScenario.new(_battle).end_turn_anyway()
	# Wait the computer's whole turn out, back to day two: the frame is then a real
	# board rather than a half-planned one, and the AI's own moves are a live check
	# that nothing it does retires a step on the player's behalf.
	var tree := _battle.get_tree()
	while (
		_battle.game.winner == 0
		and not (_battle.game.current_team == 1 and _battle.state == Battle.State.IDLE)
	):
		await tree.process_frame


## Opens the both-sides commander reference through the real map menu, the one
## route a player reaches it by. Red and Blue get distinct commanders so the two
## cards differ in the capture.
##
## Then reads the open sheet back, since this mode is a check as well as a picture:
## a sheet whose card bodies collapsed to nothing still draws its faction headers
## and still writes a full-sized PNG, which is exactly how one shipped (COM-47
## review). CommanderInfoSheet.layout_error owns what "shown" means.
func _stage_commander_info() -> void:
	_battle.game.set_commander(1, _battle.commander_db.by_id(&"rhea_sol"))
	_battle.game.set_commander(2, _battle.commander_db.by_id(&"viktor_draeg"))
	_battle.view.restage_identity()  # the board behind the sheet wears both factions
	await _open_commander_sheet()
	var sheet := _battle.commander_info_sheet
	var flaw := sheet.layout_error(_battle.game.teams.size())
	if flaw != "":
		_fail(flaw)
	await _check_sheet_scrolls(sheet)
	# Closed and reopened through the same route, so the frame this scenario
	# photographs is the authored pair rather than the probe's four.
	await _press_key(KEY_ESCAPE)
	await _open_commander_sheet()


## The one route a player reaches the sheet by: the map menu over open ground.
func _open_commander_sheet() -> void:
	_battle.confirm_at(Vector2i(10, 5))  # empty road tile -> map menu
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"commanders")
	await _until_state(Battle.State.INFO)
	await _settle_layout()  # the grid sizes its columns a frame after the sheet opens


## A real DOWN key through the open sheet, on the four-army roster whose cards
## clip to their portrait band — the case the key exists for, posed on the sheet
## rather than on a four-seat board, since what is proved here is the sheet's own
## input path. It has to be a key and not a named action: what breaks this is
## focus navigation eating ui_down before CommanderInfoSheet's _unhandled_input,
## which no frame would show.
func _check_sheet_scrolls(sheet: CommanderInfoSheet) -> void:
	var picks: Dictionary = {}
	for team in [1, 2, 3, 4]:
		picks[team] = _battle.commander_db.by_id(FOUR_ARMY_PROBE_COMMANDERS[team - 1])
	sheet.open(picks)
	await _settle_layout()
	# The 2x2 is where the footer row is likeliest to crowd the cards, so it is
	# measured here as well as on the pair this scenario photographs.
	var flaw := sheet.layout_error(picks.size())
	if flaw != "":
		_fail(flaw)
	var before := sheet.scroll_offset()
	await _press_key(KEY_DOWN)
	if sheet.scroll_offset() <= before:
		_fail("the commander sheet did not scroll on DOWN (offset stayed %d)" % before)


## Culls Blue to one nearly-dead unit and kills it through the ordinary
## select -> Fire flow, so every flow that needs a win reaches VICTORY the way a
## player does. Shared rather than copied: both call sites are pinned to where
## the default board parks these two units, and a second copy would let a board
## edit break one acceptance flow while the other kept passing.
static func stage_rout(battle: Battle) -> void:
	for unit in battle.game.units.duplicate():
		if unit.team == 2 and unit.cell != ROUT_LAST_ENEMY_CELL:
			battle.game.remove_unit(unit)
	# The sim was edited behind the scene's back, so the sprites need resyncing:
	# drop the ones whose units are gone, then redraw the survivor.
	battle.view.sync_sprites()
	var last_blue := battle.game.unit_at(ROUT_LAST_ENEMY_CELL)
	last_blue.hp = 1
	battle.view.refresh_sprite(last_blue)
	battle.confirm_at(ROUT_ATTACKER_CELL)  # select the red tank
	battle.confirm_at(ROUT_ATTACKER_CELL)  # fire in place
	await until_state_of(battle, Battle.State.MENU)
	battle.action_menu.choose(&"fire")
	await until_state_of(battle, Battle.State.TARGETING)
	battle.confirm_at(battle.cursor_cell)  # kill the last blue unit -> rout
	await until_state_of(battle, Battle.State.VICTORY)


## Parks on a unit and previews its movement out to the farthest cell it could
## actually stop on, which is the frame `--select` exists to capture.
func _demo_select(cell: Vector2i) -> void:
	if not _battle.map.in_bounds(cell):
		return
	_battle.set_cursor_cell(cell)
	_battle.confirm_at(cell)
	if _battle.state != Battle.State.UNIT_SELECTED:
		return
	var farthest := cell
	var best_cost := -1
	var move_range := _battle.move_range
	for candidate in move_range.cells():
		if move_range.can_stop_at(candidate) and move_range.costs[candidate] > best_cost:
			best_cost = move_range.costs[candidate]
			farthest = candidate
	_battle.set_cursor_cell(farthest)
