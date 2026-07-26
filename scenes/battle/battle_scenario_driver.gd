class_name BattleScenarioDriver
extends RefCounted
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
const SELECT_ARG := "--select="
const DEMO_ARG := "--demo="

## Demos fix the seed so a capture of the same scenario is the same frame.
const DEMO_SEED := 2026
## Where on the cut-in's clock the `cutin` capture is posed: late in the
## defender's impact, so the plates are up, the HP has ticked, and the damage
## callout is at full. Any moment would be byte-stable — the cut-in is a pure
## function of its clock — but this is the one that shows the most.
const CUT_IN_POSE := 0.95
## And where `cutin_ko` is posed: the blast at its brightest, a third of the way
## into the death beat, with the K.O. tag already up.
const KO_POSE := 1.15
## Cut-in modes are `cutin[_ko][:<attacker>:<defender>]`, so they are recognised
## by prefix and parsed rather than matched name-for-name.
const CUT_IN_MODE := "cutin"
const KO_SUFFIX := "_ko"
## The capture cut-in's poses. `capture_cutin` freezes a completing capture late
## in its banner — the property already flipped, the meter at zero, the specks
## out; `capture_cutin_partial` freezes an occupying one over its OCCUPYING tag.
const CAPTURE_CUT_IN_MODE := "capture_cutin"
const CAPTURE_CUT_IN_POSE := 1.75
const CAPTURE_PARTIAL_POSE := 1.65
const PARTIAL_SUFFIX := "_partial"
## `cutin_iron_commander` and `capture_cutin_iron_commander` stage their cut-in in
## a *commander* match rather than the commander-less default. That is the whole
## point of them: a commander-less side deliberately draws in the row its slot
## number names (SideIdentity plan D4), so every other cut-in capture is blind to
## a surface that reads a team int where an atlas row belongs.
const FACTION_SUFFIX := "_iron_commander"
## The pairing those variants stage, in slot order: Iron on side one, Verdant on
## side two. Neither faction's atlas row (3 and 4) equals its team int, so
## *both* halves of the frame are a live comparison — a side whose row happened
## to match its slot could not tell the two apart.
const FACTION_CO_IDS: Array[StringName] = [&"viktor_draeg", &"nia_rowan"]
## The ground `cutin_iron_commander` is fought over: the south-east base and HQ,
## adjacent, both team-tinted, and re-owned one side each. The frontline cells the
## other cut-in modes use are plains, where an untinted tile makes the owner row
## moot — so the third surface COM-10 named, the ground strip under each half, was
## the one no scenario put a faction row through. Owning the pair apart puts a
## *different* faction row under each half, so a swapped one is as loud as a
## wrong one.
const FACTION_ATTACKER_CELL := Vector2i(16, 11)  # base
const FACTION_DEFENDER_CELL := Vector2i(17, 11)  # HQ
## And the side `capture_cutin_iron_commander` takes its property *from*, so the
## flip crosses between two faction rows rather than out of neutral row 0.
const FACTION_CAPTURE_FROM := 2
## `cutin_skip` walks a skip across the whole cut-in — see _spam_skip. One entry
## per beat boundary and a couple past the end, which is where a double-finish
## would show up.
const SKIP_SUFFIX := "_skip"
const SKIP_FRAMES: Array[int] = [0, 1, 2, 4, 8, 16, 32, 64, 128, 240]
## Every variant each cut-in family implements, as the suffix left once its
## prefix is taken off. Not decoration: each suffix below is read off the name
## with `ends_with`/`begins_with`, and an unrecognised one answers false to all
## of them rather than erroring — so `cutin_iron_commandr` quietly poses the
## commander-less frame under the acceptance mode's name, and
## `capture_cutin_partail` poses a completing capture where an occupying one was
## asked for. That is the one failure the row checks cannot catch, because the
## frame they check *is* correct; it is simply not the frame that was asked for.
##
## Combat takes at most one suffix, since all three are `ends_with` and only the
## last would be honoured — `cutin_ko_skip` would drop its `_ko` in silence.
## Capture reads `_partial` off the front, so it composes with one of the other
## two and must lead.
const CUT_IN_SUFFIXES: Array[String] = ["", KO_SUFFIX, SKIP_SUFFIX, FACTION_SUFFIX]
const CAPTURE_CUT_IN_SUFFIXES: Array[String] = [
	"",
	PARTIAL_SUFFIX,
	SKIP_SUFFIX,
	FACTION_SUFFIX,
	PARTIAL_SUFFIX + SKIP_SUFFIX,
	PARTIAL_SUFFIX + FACTION_SUFFIX,
]

var _battle: Battle
var _shot_path := ""
var _select_cell := Vector2i(-1, -1)
var _demo := ""
## Raised by any mid-scenario check that fails. `run` reads it before it writes
## anything: a capture saved after a failed check would take the exit code down
## with it — ScreenshotUtil quits zero — and that code is the entire signal the
## smoke sweep reads.
var _failed := false


func _init(battle: Battle) -> void:
	_battle = battle
	_shot_path = ScreenshotUtil.requested()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(SELECT_ARG):
			var parts := arg.get_slice("=", 1).split(",")
			if parts.size() == 2:
				_select_cell = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with(DEMO_ARG):
			_demo = arg.get_slice("=", 1)


## True when the command line asked for any scripted flow at all. Battle skips
## building a driver otherwise, so an ordinary match never pays for one.
func requested() -> bool:
	return _shot_path != "" or _select_cell.x >= 0 or _demo != ""


func run() -> void:
	if not requested():
		return
	# Demos and captures drive the board, so neither the handoff panel nor the
	# day-1 banner may sit on top of the frame.
	_battle.leave_handoff()
	_battle.hide_banner()
	if _demo != "":
		await _run_demo(_demo)
	elif _select_cell.x >= 0:
		_demo_select(_select_cell)
	if _failed or not _fog_hides_unseen():
		_battle.get_tree().quit(1)
		return
	if _shot_path != "":
		await _save_screenshot_and_quit(_shot_path)


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
		if sprite != null and sprite.visible and not _battle.view.can_see_unit(unit):
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
## mapmenu stops at the map menu (End Turn / Save); powermenu fires a Command
## Power from the HUD over an open action menu; ambush and vanish are the same
## staged board with Sable Wren's power down and up; victory routs Blue through
## a real attack so the victory screen comes up. The commander-identity captures
## (plan G3, COM-18): power_charging/ready/active/ai/mirror cover every state the
## bottom bar's commander block takes, power_ready_contrast is the named
## legibility gate, power_mapmenu opens the keyboard route the ready meter
## advertises and checks the menu stays inside the board band, power_banner fires
## a power so its activation card holds, commander_info opens the both-sides
## reference from the map menu, and commander_victory wins with a general so the
## victory lockup is fronted by a portrait.
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
	# than matched — see _stage_cut_in.
	if mode.begins_with(CAPTURE_CUT_IN_MODE):
		await _stage_capture_cut_in(mode)
		return
	if mode.begins_with(CUT_IN_MODE):
		await _stage_cut_in(mode)
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
			_battle.confirm_at(Vector2i(10, 5))  # empty road tile -> map menu
			await _until_state(Battle.State.MENU)
			_battle.action_menu.choose(&"end_turn")
			await tree.process_frame
		"load", "cargo", "drop", "transport":
			await _run_transport_demo(mode)
		"divemenu", "dive":
			await _run_dive_demo(mode)
		"supply":
			_battle.confirm_at(Vector2i(3, 3))  # select the red APC
			_battle.confirm_at(Vector2i(3, 3))  # stay put -> menu offers Supply
			await _until_state(Battle.State.MENU)
		"mapmenu":
			_battle.confirm_at(Vector2i(10, 5))  # empty road tile -> End Turn / Save
			await _until_state(Battle.State.MENU)
		"powermenu":
			await _run_power_menu_demo()
		"ambush", "vanish":
			_run_vanish_demo(mode)
		"power_charging":
			await _stage_charging_power()
		"power_ready", "power_ready_contrast":
			await _stage_ready_power()
		"power_active":
			await _stage_active_power()  # power running -> meter ACTIVE, no banner
		"power_ai":
			await _stage_ai_power()
		"power_mirror":
			await _stage_mirror_power()
		"power_mapmenu":
			await _stage_power_map_menu()  # the keyboard route to the power, unobscured
		"power_banner":
			await _stage_power_banner()  # fire it -> the activation card holds
		"commander_info":
			await _stage_commander_info()  # both-sides reference from the map menu
		"commander_victory":
			await _run_victory_demo(true)  # victory lockup fronted by the winner's face
		"victory":
			await _run_victory_demo()
		"aiturn":
			# hand the turn to the Blue AI and wait until it plays back to Red
			_battle.confirm_at(Vector2i(10, 5))
			await _until_state(Battle.State.MENU)
			_battle.action_menu.choose(&"end_turn")
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
		_battle.set_cursor_cell(Vector2i(3, 3))  # panel shows the APC's [+Infantry]
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


## Fires a Command Power from the HUD button with a unit's action menu already
## open — the one route that reaches the power in State.MENU, since the map menu
## closes itself on the way. The power abandons the move the menu belonged to, so
## the menu has to go with it: a row chosen afterwards used to run against a
## selection that was already cleared and take the scene down with it.
func _run_power_menu_demo() -> void:
	var co := _battle.commander_db.by_id(&"alina_ward")
	_battle.game.set_commander(1, co)
	_battle.game.commander_state(1).charge = co.power_cost
	_battle.view.restage_identity()  # meter reads full, and the CO recolours its board
	_battle.confirm_at(Vector2i(8, 8))  # select the red tank
	_battle.confirm_at(Vector2i(8, 8))  # stay put -> its action menu
	await _until_state(Battle.State.MENU)
	_battle.view.hud_bottom.fire_button.pressed.emit()
	await _until_state(Battle.State.IDLE)
	# Waited out rather than asserted, in the same spirit as _until_state: a menu
	# that never closes hangs the scenario and the smoke run reports the timeout.
	while _battle.action_menu.visible:
		await _battle.get_tree().process_frame
	_battle.action_menu.choose(&"wait")  # the click a player can no longer make


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
	_battle.view.refresh_fog(game.current_team, false)
	_battle.view.restage_identity()  # Sable Wren's Verdant recolours Blue after the fog pass
	_battle.set_cursor_cell(Vector2i(5, 5))  # the panel names whatever is on the tile


## The battle cut-in, held still for the shutter. Any matchup, on any board:
##
##   --demo=cutin                    the two frontline tanks, defender survives
##   --demo=cutin_ko                 the same pair, defender routed
##   --demo=cutin:bomber:fighter     that matchup, staged wherever it fits
##   --demo=cutin_ko:artillery:mech  and the same with a kill
##   --demo=cutin_iron_commander     the same tanks, Iron v Verdant, and fought
##                                   over a property apiece so the ground under
##                                   each half carries a faction row too
##
## One suffix off CUT_IN_SUFFIXES, then an optional `:<attacker>:<defender>`;
## anything else fails the run rather than falling back to the plain variant.
##
## The exchange is resolved directly rather than driven through the targeting
## flow, because the flow deliberately suppresses the cut-in while capturing
## (BattleAnimator._cut_in_applies) — a mid-tween frame is exactly what makes two
## otherwise identical captures differ, which is the war this repo already fought
## with the camera shake. So the still is posed instead: a real result off the
## real resolver, frozen at one moment of the cut-in's own clock.
##
## Named matchups are what makes "all eighteen units stage correctly" checkable
## without eighteen hand-placed scenarios. The pair is stood on the first cells
## the board offers that both can legally occupy, so an air or naval matchup
## works on whatever map the capture was launched with.
func _stage_cut_in(spec: String) -> void:
	var parts := spec.split(":")
	if parts.size() != 1 and parts.size() != 3:
		_fail("cutin demo: a matchup reads ':<attacker>:<defender>' (%s)" % spec)
		return
	if not _known_variant(parts[0], CUT_IN_MODE, CUT_IN_SUFFIXES):
		return
	var lethal := parts[0].ends_with(KO_SUFFIX)
	var game := _battle.game
	var factions := parts[0].ends_with(FACTION_SUFFIX)
	if factions:
		_stage_faction_commanders()
	var attacker := game.unit_at(Vector2i(8, 8))  # red tank
	var defender := game.unit_at(Vector2i(9, 8))  # blue tank
	if parts.size() >= 3:
		var pair := _stand_pair(parts[1], parts[2])
		if pair.is_empty():
			return
		attacker = pair[0]
		defender = pair[1]
	if attacker == null or defender == null:
		_fail("cutin demo: no pair to stage (%s)" % spec)
		return
	if factions:
		_stage_owned_ground(attacker, defender)
	defender.hp = 10 if lethal else 74
	var result := CombatResolver.resolve(game, attacker, defender)
	_battle.view.sync_sprites()
	if parts[0].ends_with(SKIP_SUFFIX):
		await _spam_skip(result, attacker, defender)
	_battle.animator.cutscene.pose_at(
		result, attacker, defender, KO_POSE if lethal else CUT_IN_POSE
	)
	_check_cut_in_rows(attacker, defender)


## The capture cut-in, held still for the shutter — the sibling of `_stage_cut_in`.
##
##   --demo=capture_cutin           a completing capture, late in its banner
##   --demo=capture_cutin_partial   an occupying capture over its OCCUPYING tag
##   --demo=capture_cutin_skip      walks a skip across the whole clock (a test)
##   --demo=capture_cutin_iron_commander  the same city, taken by Iron off Verdant
##
## One suffix off CAPTURE_CUT_IN_SUFFIXES, `_partial` leading where it composes;
## anything else fails the run rather than falling back to the plain variant.
##
## Like the combat still it is posed rather than driven through the menu, because
## the capture flow suppresses the cut-in while capturing for exactly the same
## byte-stability reason (BattleAnimator._capture_cut_in_applies). A real
## CaptureResult, frozen at one moment of the cut-in's own clock, on the default
## board's neutral city at (3,4) — the same property the `capture` demo takes.
func _stage_capture_cut_in(mode: String) -> void:
	if not _known_variant(mode, CAPTURE_CUT_IN_MODE, CAPTURE_CUT_IN_SUFFIXES):
		return
	var game := _battle.game
	var cell := Vector2i(3, 4)  # the neutral city
	var unit := game.unit_at(Vector2i(4, 3))  # the red infantry
	if unit == null:
		_fail("capture_cutin demo: no infantry at (4,3)")
		return
	var factions := mode.ends_with(FACTION_SUFFIX)
	if factions:
		_stage_faction_commanders()
	var partial := mode.begins_with(CAPTURE_CUT_IN_MODE + PARTIAL_SUFFIX)
	var result := CaptureCommand.CaptureResult.new()
	# Taken off the rival side rather than off neutral in the faction variant, so
	# the row the property *starts* in is a faction row too — row 0 either way is
	# how the owner path stayed unexercised. The sim's property is re-owned with
	# it, so the board behind the cut-in agrees about who is being taken from.
	result.owner_before = FACTION_CAPTURE_FROM if factions else MapData.NEUTRAL
	if factions:
		game.set_owner(cell, result.owner_before)
		_battle.view.repaint_property(cell)
	result.points_before = 20 if partial else 8
	result.points_after = 10 if partial else 0
	result.captured = not partial
	_battle.view.sync_sprites()
	if mode.ends_with(SKIP_SUFFIX):
		await _spam_capture_skip(result, unit, cell)
	_battle.animator.capture_cutscene.pose_at(
		result, unit, cell, CAPTURE_PARTIAL_POSE if partial else CAPTURE_CUT_IN_POSE
	)
	_check_capture_cut_in_rows(unit, cell)


## The capture cut-in's half of risk R2, made checkable exactly as `_spam_skip`
## makes combat's: the same capture is played and skipped again and again, one
## frame later each time, so the skip walks every beat — the wipe, the march, the
## three mashes, the flip and the banner. Each run must emit `finished` exactly
## once and land the punched-in camera back at its resting zoom.
func _spam_capture_skip(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i) -> void:
	var cutscene := _battle.animator.capture_cutscene
	var camera := _battle.camera
	var tree := _battle.get_tree()
	var resting := camera.zoom
	for delay in SKIP_FRAMES:
		var finishes := [0]
		var tally := func() -> void: finishes[0] += 1
		cutscene.finished.connect(tally)
		camera.zoom = resting * BattleAnimator.PUNCH_ZOOM
		cutscene.play(result, unit, cell, camera, resting)  # deliberately not awaited
		for frame in delay:
			await tree.process_frame
		for spam in 3:
			cutscene.skip()
			await tree.process_frame
		await tree.process_frame  # the exit lands on the frame after the skip
		cutscene.finished.disconnect(tally)
		if finishes[0] != 1:
			_fail(
				"capture cut-in skipped after %d frame(s) finished %d times" % [delay, finishes[0]]
			)
			return
		if not camera.zoom.is_equal_approx(resting):
			_fail(
				(
					"capture cut-in skipped after %d frame(s) left camera zoom at %s, not resting %s"
					% [delay, camera.zoom, resting]
				)
			)
			return
	camera.zoom = resting
	print(
		(
			"capture_cutin_skip: %d skips, each resolved exactly once and camera home"
			% SKIP_FRAMES.size()
		)
	)


## Risk R2, made checkable: both call sites hold the whole interaction flow on
## `animate_combat`, so a cut-in that ever fails to finish freezes input for the
## rest of the session. Here the same exchange is played and skipped again and
## again, one frame later each time, which walks the skip across every beat the
## cut-in has — the wipe, the volley, the impact, the counter, the death and the
## hold. Each run has to emit `finished` exactly once and land the punched-in
## camera back at its resting zoom, since the cut-in now eases that off its own
## clock too (plan R2/R4).
##
## A run that never finishes hangs the scenario and the smoke sweep reports the
## timeout; one that finishes twice, or not at all, or leaves the camera zoomed,
## quits non-zero here.
func _spam_skip(result: CombatResolver.CombatResult, attacker: Unit, defender: Unit) -> void:
	var cutscene := _battle.animator.cutscene
	var camera := _battle.camera
	var tree := _battle.get_tree()
	var resting := camera.zoom
	for delay in SKIP_FRAMES:
		var finishes := [0]
		# Deliberately not CONNECT_ONE_SHOT: a one-shot connection drops itself
		# after the first emission, so the very failure this is looking for — an
		# exit that fires twice — would be the one it could not see.
		var tally := func() -> void: finishes[0] += 1
		cutscene.finished.connect(tally)
		# Hand it the punched-in camera the animator would, so the skip has a zoom
		# to land: the cut-in now owns easing it back to `resting` off its own
		# clock, and a skip must pin it there like every other value it drives.
		camera.zoom = resting * BattleAnimator.PUNCH_ZOOM
		cutscene.play(result, attacker, defender, camera, resting)  # deliberately not awaited
		for frame in delay:
			await tree.process_frame
		# Spammed, not pressed once: a second skip after the exit has run must be
		# a no-op rather than a second `finished`.
		for spam in 3:
			cutscene.skip()
			await tree.process_frame
		await tree.process_frame  # the exit lands on the frame after the skip
		cutscene.finished.disconnect(tally)
		if finishes[0] != 1:
			_fail("cut-in skipped after %d frame(s) finished %d times" % [delay, finishes[0]])
			return
		if not camera.zoom.is_equal_approx(resting):
			_fail(
				(
					"cut-in skipped after %d frame(s) left camera zoom at %s, not resting %s"
					% [delay, camera.zoom, resting]
				)
			)
			return
	camera.zoom = resting
	print("cutin_skip: %d skips, each resolved exactly once and camera home" % SKIP_FRAMES.size())


## Puts one unit of each named type onto the first pair of cells the board has
## that both can stand on, clearing whatever was there. Returns
## [attacker, defender], or empty when the ids or the board do not work out —
## which fails the run rather than passing quietly. A matchup that was asked for
## and never staged photographs a plain board, and the caller has nothing to pose
## and nothing to check; a naval pair belongs on a board with water on it, which
## is why tools/smoke_scenarios.sh hands those modes `--map=the_straits`.
##
## The two are stood the attacker's own minimum range apart, not simply side by
## side, so an indirect weapon is staged from a cell it could actually have
## fired from — which is also the only way to see the no-counter framing an
## indirect attack gets.
func _stand_pair(attacker_id: String, defender_id: String) -> Array[Unit]:
	var none: Array[Unit] = []
	var attacker_type := _battle.unit_db.by_id(StringName(attacker_id))
	var defender_type := _battle.unit_db.by_id(StringName(defender_id))
	if attacker_type == null or defender_type == null:
		_fail("cutin demo: unknown unit id in '%s vs %s'" % [attacker_id, defender_id])
		return none
	if not _battle.game.damage_chart.can_attack(attacker_type.id, defender_type.id):
		_fail("cutin demo: %s has no weapon that reaches %s" % [attacker_id, defender_id])
		return none
	var map := _battle.map
	var reach: int = maxi(attacker_type.min_range, 1)
	for y in map.height:
		for x in map.width:
			var here := Vector2i(x, y)
			if not map.terrain_at(here).is_passable(attacker_type.move_class):
				continue
			for dir in MovementResolver.DIRECTIONS:
				var there: Vector2i = here + dir * reach
				var terrain := map.terrain_at(there)
				if terrain == null or not terrain.is_passable(defender_type.move_class):
					continue
				var pair: Array[Unit] = [
					_stand(attacker_type, 1, here), _stand(defender_type, 2, there)
				]
				_battle.view.sync_sprites()
				return pair
	_fail("cutin demo: no cell pair on this board fits %s vs %s" % [attacker_id, defender_id])
	return none


## Clears a cell and stands a fresh unit on it.
func _stand(type: UnitType, team: int, cell: Vector2i) -> Unit:
	var game := _battle.game
	var sitting := game.unit_at(cell)
	if sitting != null:
		game.remove_unit(sitting)
	var unit := Unit.create(type, team, cell)
	game.units.append(unit)
	_battle.view.spawn_sprite_for(unit)
	return unit


## Sets Red's commander and, optionally, fills its meter, then refreshes the HUD
## so the bars read the state under test. Node-free like the rest of the driver:
## it only writes sim state the presentation then reflects.
func _set_red_commander(id: StringName, charged: bool) -> CommanderType:
	var co := _battle.commander_db.by_id(id)
	_battle.game.set_commander(1, co)
	if charged:
		_battle.game.commander_state(1).charge = co.power_cost
	_battle.view.restage_identity()  # reflects the staged CO's name and colour, not just the meter
	return co


## Gives both sides a general whose faction row differs from its slot number, then
## restages identity so the board's units, properties and HUD all wear those
## factions. What that buys the cut-in variants is a straight comparison inside one
## frame: whatever colour the board paints a side, the cut-in over it has to paint
## the same one, and no team-int-as-row shortcut can survive it.
func _stage_faction_commanders() -> void:
	for slot in FACTION_CO_IDS.size():
		var team: int = GameState.TEAMS[slot]
		_battle.game.set_commander(team, _battle.commander_db.by_id(FACTION_CO_IDS[slot]))
	_battle.view.restage_identity()


## Stands the pair on the two adjacent properties in the south-east and gives one
## to each side, so the ground strip under each half of the cut-in is a tinted
## tile with a *faction* owner. Called for the `_iron_commander` combat variant
## only: the frontline cells the other modes fight over are plains, where the
## owner row is never read at all.
func _stage_owned_ground(attacker: Unit, defender: Unit) -> void:
	var game := _battle.game
	var cells: Array[Vector2i] = [FACTION_ATTACKER_CELL, FACTION_DEFENDER_CELL]
	for cell in cells:
		var sitting := game.unit_at(cell)
		if sitting != null and sitting != attacker and sitting != defender:
			game.remove_unit(sitting)
	attacker.cell = FACTION_ATTACKER_CELL
	defender.cell = FACTION_DEFENDER_CELL
	game.set_owner(FACTION_ATTACKER_CELL, attacker.team)
	game.set_owner(FACTION_DEFENDER_CELL, defender.team)
	for cell in cells:
		_battle.view.repaint_property(cell)
	_battle.view.sync_sprites()


## Every atlas row the posed combat cut-in baked into its art is the one
## SideIdentity gives the side it belongs to — each army's, and each ground
## strip's owner's.
##
## Checked rather than eyeballed, in the spirit of `_fog_hides_unseen`: a half
## painted in the wrong faction's colours still renders a perfectly good frame, so
## a scenario that only proves one was written passes straight through COM-10.
## Run for every cut-in mode, not just the commander ones — on a commander-less
## board it is a live check that the no-CO fallback still lands where its slot
## names, which is the case the bug hid behind.
func _check_cut_in_rows(attacker: Unit, defender: Unit) -> void:
	var cutscene := _battle.animator.cutscene
	var atk := cutscene.attacker_side()
	var def := cutscene.defender_side()
	_check_row("cut-in attacker", atk.drawn_unit_row(), _army_row(attacker.team))
	_check_row("cut-in defender", def.drawn_unit_row(), _army_row(defender.team))
	_check_row("cut-in attacker ground", atk.drawn_ground_row(), _ground_row(attacker.cell))
	_check_row("cut-in defender ground", def.drawn_ground_row(), _ground_row(defender.cell))


## The same check over the capture cut-in: the marching squad wears the
## capturer's row, and the property flips from the row its owner on the board
## wears to that same capturer's.
func _check_capture_cut_in_rows(unit: Unit, cell: Vector2i) -> void:
	var stage := _battle.animator.capture_cutscene.stage()
	var capturer := _army_row(unit.team)
	_check_row("capture squad", stage.drawn_squad_row(), capturer)
	_check_row("capture property before", stage.row_before, _ground_row(cell))
	_check_row("capture property after", stage.row_after, capturer)


## The atlas row a side's army is drawn in on the board — SideIdentity's answer,
## which is the one every surface owes.
func _army_row(team: int) -> int:
	return _battle.view.identity.atlas_row(team)


## And the row a cell's ground is drawn in: its owner's faction row on a property,
## the untinted row 0 on anything else. The same question `BattleView._paint_map`
## answers for the board, asked of the board here so the cut-in is compared
## against what the player sees under it rather than against itself.
func _ground_row(cell: Vector2i) -> int:
	if not _battle.map.terrain_at(cell).team_tinted:
		return SideIdentity.NEUTRAL_ROW
	return _army_row(_battle.game.owner_at(cell))


func _check_row(what: String, drawn: int, wanted: int) -> void:
	if drawn == wanted:
		return
	_fail("%s is drawn in atlas row %d, but the board wears row %d" % [what, drawn, wanted])


## True when a cut-in mode names a variant the family actually implements — the
## part left after its prefix is one of `known`. Fails the run otherwise, naming
## every mode the family does take, since the whole hazard is a name that reads
## like a variant and quietly stages a different one.
func _known_variant(name_part: String, prefix: String, known: Array[String]) -> bool:
	if known.has(name_part.substr(prefix.length())):
		return true
	var legal := PackedStringArray()
	for suffix in known:
		legal.append(prefix + suffix)
	_fail("%s demo: unknown variant '%s'; it takes %s" % [prefix, name_part, ", ".join(legal)])
	return false


## Reports a scenario failure and makes the run's exit code say so. Every
## reporting path in this driver goes through here, because the two halves are
## not separable: `run` refuses to write a capture once the flag is up, and a
## capture written anyway quits zero (ScreenshotUtil) — which is the whole signal
## the smoke sweep reads. A scenario that printed an error and still photographed
## a board it never staged is a scenario that passes while proving nothing.
func _fail(message: String) -> void:
	push_error(message)
	_failed = true


## Parks the cursor on open ground and lets the HUD settle before the capture. The
## docked bars never cover a tile, so where it rests is only about what the bottom
## bar is describing, not about dodging chrome.
func _settle_hud() -> void:
	_battle.set_cursor_cell(Vector2i(10, 5))
	await _battle.get_tree().create_timer(0.2).timeout


## The partly filled meter the commander block carries for most of a match.
func _stage_charging_power() -> void:
	var co := _set_red_commander(&"viktor_draeg", false)
	_battle.game.commander_state(1).charge = int(co.power_cost / 2)
	_battle.view.refresh_hud()
	await _settle_hud()


## The COM-18 legibility frames. power_ready and power_ready_contrast stage the
## same ready meter and differ only in the board it is read against — the smoke
## harness launches the second on the bright strait. The chip's cursor-fade frame
## retired with the chip: a docked bar is never on top of a tile to fade off one.
func _stage_ready_power() -> void:
	_set_red_commander(&"mara_voss", true)
	await _settle_hud()


## Raises a power directly (no fire, no banner) so the capture is the meter's
## ACTIVE state alone. Firing is proved by `power_banner`; this isolates the HUD.
func _stage_active_power() -> void:
	# The roster's longest power name makes this the truncation regression frame.
	var co := _battle.commander_db.by_id(&"viktor_draeg")
	_battle.game.set_commander(1, co)
	_battle.game.commander_state(1).power_active = true
	_battle.view.restage_identity()
	await _settle_hud()


## A full computer meter with no player FIRE control.
func _stage_ai_power() -> void:
	var co := _battle.commander_db.by_id(&"nia_rowan")
	_battle.game.set_commander(2, co)
	_battle.game.commander_state(2).charge = co.power_cost
	_battle.game.current_team = 2
	_battle.view.restage_identity()
	await _settle_hud()


## Both slots pick Iron; side two's commander block must keep the Iron name while
## borrowing the same Aurora blue its board wears.
func _stage_mirror_power() -> void:
	var co := _battle.commander_db.by_id(&"viktor_draeg")
	_battle.game.set_commander(1, co)
	_battle.game.set_commander(2, co)
	_battle.game.commander_state(2).charge = co.power_cost
	_battle.game.current_team = 2
	_battle.ai_teams.clear()  # Battle owns the list; hand the emptied one over again
	_battle.view.ai_teams = _battle.ai_teams
	_battle.view.restage_identity()
	await _settle_hud()


## Charges Red, then fires the power through the real Fire button so the
## activation card comes up exactly as it does in play. It holds on screen while
## capturing (see BattleAnimator.show_power_banner), so the frame is the banner.
func _stage_power_banner() -> void:
	_set_red_commander(&"cass_orlov", true)
	_battle.view.hud_bottom.fire_button.pressed.emit()
	await _until_state(Battle.State.IDLE)


## The keyboard route the ready meter advertises alongside F: Enter on empty
## ground, then the map menu's first row, which is the Command Power. The frame
## alone proves nothing — the board renders behind the opaque bars, so a menu drawn
## under one photographs just as well as one clear of it. Hence the check.
func _stage_power_map_menu() -> void:
	_set_red_commander(&"mara_voss", true)
	_battle.confirm_at(Vector2i(10, 5))  # empty road tile -> map menu
	await _until_state(Battle.State.MENU)
	# The menu sizes its rows and clamps itself a frame after it opens.
	await _battle.get_tree().process_frame
	await _battle.get_tree().process_frame
	_check_map_menu_readable()


## The power row the hint sends the player to has to be visible when they get
## there, and the whole menu has to stay inside the *board band* — the strip of the
## 640x360 frame the two docked bars leave over, which is what ActionMenu clamps
## against. Both are read off the live rects rather than recomputed.
func _check_map_menu_readable() -> void:
	var rows := BattleMenus.map_actions(_battle.game)
	if rows.is_empty() or rows[0].id != &"power":
		_fail("map menu opened without the Command Power as its first row")
		return
	var menu := _battle.action_menu.get_global_rect()
	var frame := _battle.get_viewport().get_visible_rect().size
	var band := Rect2(Vector2(0, UiTheme.HUD_TOP_H), Vector2(frame.x, frame.y - UiTheme.HUD_BARS_H))
	if not band.encloses(menu):
		_fail("the map menu %s does not fit the board band %s" % [menu, band])


## Opens the both-sides commander reference through the real map menu, the one
## route a player reaches it by. Red and Blue get distinct commanders so the two
## cards differ in the capture.
func _stage_commander_info() -> void:
	_battle.game.set_commander(1, _battle.commander_db.by_id(&"rhea_sol"))
	_battle.game.set_commander(2, _battle.commander_db.by_id(&"viktor_draeg"))
	_battle.view.restage_identity()  # the board behind the sheet wears both factions
	_battle.confirm_at(Vector2i(10, 5))  # empty road tile -> map menu
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"commanders")
	await _until_state(Battle.State.INFO)


## Leaves Blue one nearly-dead unit, then wins through the ordinary
## select -> Fire flow so the real victory handler runs. `with_commander` gives
## Red a general first, so the victory lockup is fronted by a portrait.
func _run_victory_demo(with_commander: bool = false) -> void:
	if with_commander:
		_battle.game.set_commander(1, _battle.commander_db.by_id(&"viktor_draeg"))
		_battle.view.restage_identity()  # so the win lockup reads the winner's faction, not First Army
	for unit in _battle.game.units.duplicate():
		if unit.team == 2 and unit.cell != Vector2i(9, 8):
			_battle.game.remove_unit(unit)
	# The sim was edited behind the scene's back, so the sprites need resyncing:
	# drop the ones whose units are gone, then redraw the survivor.
	_battle.view.sync_sprites()
	var last_blue := _battle.game.unit_at(Vector2i(9, 8))
	last_blue.hp = 1
	_battle.view.refresh_sprite(last_blue)
	_battle.confirm_at(Vector2i(8, 8))  # select the red tank
	_battle.confirm_at(Vector2i(8, 8))  # fire in place
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"fire")
	await _until_state(Battle.State.TARGETING)
	_battle.confirm_at(_battle.cursor_cell)  # kill the last blue unit -> rout
	await _until_state(Battle.State.VICTORY)


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


## Scenarios advance by waiting on the scene's own state machine rather than a
## fixed frame count, so they stay correct when animation timings change.
func _until_state(wanted: Battle.State) -> void:
	while _battle.state != wanted:
		await _battle.get_tree().process_frame


func _save_screenshot_and_quit(path: String) -> void:
	await ScreenshotUtil.capture_and_quit(_battle, path)
