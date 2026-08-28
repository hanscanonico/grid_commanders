class_name BattlePowerScenario
extends BattleScenario
## The Command Power capture flows, split out so BattleScenarioDriver stays under
## its linted size cap. Every flow — `run` included — returns an error string
## rather than reporting one: the driver's `_fail` owns the push_error and the
## exit-code flag together, and the two are not separable.
##
## powermenu fires a power from the HUD over an open action menu and
## capture_power fires the same button one beat later, while the capture cut-in
## is playing (COM-50). The commander-identity captures (plan G3, COM-18) are the
## rest: power_charging/ready/active/ai/mirror cover every state the bottom bar's
## commander block takes, power_ready_contrast is the named legibility gate,
## power_mapmenu opens the keyboard route the ready meter advertises and checks
## the menu stays inside the board band, power_banner fires a power so its
## activation card holds, and power_targeting stops the aimed power mid-aim.

## Where `power_targeting` aims Hammerfall: the middle of Red's own opening
## corner, so the square holds his HQ, his base, a neutral city and four of his
## units at once. Aimed at his own army on purpose — the power takes whatever is
## standing in it, and a frame full of the *player's* pieces says that where one
## full of the opponent's would only look like an attack.
const HAMMERFALL_AIM := Vector2i(3, 3)

## `capture_power` walks COM-50's race — a Command Power fired from the HUD while
## the capture cut-in is playing. The city the default board's `capture` demo takes
## and the infantry that takes it, named here because the race checks the sim
## afterwards as well as driving it.
const CAPTURE_POWER_MODE := "capture_power"
const CAPTURE_CELL := Vector2i(3, 4)
const CAPTURER_CELL := Vector2i(4, 3)
## The tier that race is run at: the shortest one that still plays a cut-in, since
## the window it is looking for only exists while one does. Captures pin Instant,
## which has no beats to race (GameSpeed.CAPTURE_ID), and the scenario puts that
## back before it returns.
const RACE_SPEED_ID := &"quick"
## How long the race waits for the cut-in it staged before calling the staging
## wrong. Every other wait here is unbounded because what it waits on is this
## scene's own flow; this one waits on a gate whose inputs live outside the
## scenario, so a miss has to be said out loud rather than run out the sweep's
## timeout with no reason attached.
const CUT_IN_START_FRAMES := 600

## The modes this class drives, asked of it by BattleScenarioDriver rather than
## listed there a second time.
const MODES: Array[String] = [
	"powermenu",
	CAPTURE_POWER_MODE,
	"power_charging",
	"power_ready",
	"power_ready_contrast",
	"power_active",
	"power_ai",
	"power_mirror",
	"power_mapmenu",
	"power_banner",
	"power_targeting",
]


func run(mode: String) -> String:
	match mode:
		"powermenu":
			return await _run_power_menu_demo()
		CAPTURE_POWER_MODE:
			return await _stage_capture_power_race()
		"power_charging":
			return await _stage_charging_power()
		"power_ready", "power_ready_contrast":
			return await _stage_ready_power()
		"power_active":
			return await _stage_active_power()  # power running -> meter ACTIVE, no banner
		"power_ai":
			return await _stage_ai_power()
		"power_mirror":
			return await _stage_mirror_power()
		"power_mapmenu":
			return await _stage_power_map_menu()  # the keyboard route, unobscured
		"power_banner":
			return await _stage_power_banner()  # fire it -> the activation card holds
		"power_targeting":
			return await _stage_power_targeting()  # the aimed power, mid-aim
	return "unknown power scenario: %s" % mode


## Fires a Command Power from the HUD button with a unit's action menu already
## open — the one route that reaches the power in State.MENU, since the map menu
## closes itself on the way. The power abandons the move the menu belonged to, so
## the menu has to go with it: a row chosen afterwards used to run against a
## selection that was already cleared and take the scene down with it.
func _run_power_menu_demo() -> String:
	_set_red_commander(&"alina_ward", true)
	_battle.confirm_at(Vector2i(8, 8))  # select the red tank
	_battle.confirm_at(Vector2i(8, 8))  # stay put -> its action menu
	await _until_state(Battle.State.MENU)
	_battle.view.fire_pressed.emit()
	await _until_state(Battle.State.IDLE)
	# Waited out rather than asserted, in the same spirit as _until_state: a menu
	# that never closes hangs the scenario and the smoke run reports the timeout.
	while _battle.action_menu.visible:
		await _battle.get_tree().process_frame
	_battle.action_menu.choose(&"wait")  # the click a player can no longer make
	return ""


## The same button, pressed one beat later: while the capture cut-in is playing
## (COM-50). The capture flow holds its cut-in on an await, and the HUD's Fire
## button is the one control that reaches a command from a held flow — the board is
## mouse-transparent under the cut-in and the keyboard is already refused. So a
## power fired mid-beat used to enter the command pipeline re-entrantly, while the
## capture was still replaying its own snapshot, and clear the selection the
## capture flow came back to.
##
## The only scenario that lets a cut-in really play: `capturing`, the pinned
## Instant tier and the battle-animations preference each gate it out
## (BattleAnimator._capture_cut_in_applies), and the window this walks exists only
## inside the beats they suppress. All three are staged and put back before it
## returns, so the frame `run` takes afterwards is `capture`'s frame — and the
## third is staged for the same reason the first two are pinned at all: whether
## this machine's player left the cut-ins switched on must not decide whether the
## scenario runs.
func _stage_capture_power_race() -> String:
	var tree := _battle.get_tree()
	var cutscene := _battle.animator.capture_cutscene
	var animations_were := Settings.battle_animations
	_set_red_commander(&"alina_ward", true)
	_battle.animator.capturing = false
	# Both pinned, so neither writes a preference file (Settings.pin, from
	# Battle._ready, latches it shut for every scenario run).
	Settings.set_speed(RACE_SPEED_ID)
	Settings.set_battle_animations(true)
	_battle.confirm_at(CAPTURER_CELL)  # select the red infantry
	_battle.confirm_at(CAPTURE_CELL)  # move onto the neutral city
	await _until_state(Battle.State.MENU)
	# Deliberately not awaited: choosing the row starts the capture, and the flow is
	# still inside its cut-in when the button below is pressed.
	_battle.action_menu.choose(&"capture")
	var waited := 0
	while not cutscene.is_processing():
		if waited >= CUT_IN_START_FRAMES:
			# Said out loud and abandoned rather than raced anyway: with no cut-in
			# there is no window, so every check below would report the staging's
			# failure as the fix's.
			_restore_race_gates(animations_were)
			return "the capture cut-in never started — the race had nothing to race"
		waited += 1
		await tree.process_frame
	var flaws := PackedStringArray()
	if _battle.state == Battle.State.MENU:
		flaws.append(
			"capture holds its cut-in in State.MENU — the HUD Fire button reaches a command"
		)
	_battle.view.fire_pressed.emit()
	await _until_state(Battle.State.IDLE)
	if _battle.game.commander_state(1).power_active:
		flaws.append("a Command Power fired during the capture cut-in")
	if not _battle.game.capture_progress.has(CAPTURE_CELL):
		flaws.append("the capture the power was fired over never registered")
	_restore_race_gates(animations_were)
	_battle.set_cursor_cell(CAPTURE_CELL)  # the `capture` frame, once the race is over
	return "\n".join(flaws)


## Puts the three gates the race lowered back where it found them. Both of the
## race's exits pass through here: one that returned with the speed still pinned
## to `quick` would take every scenario after it in the batch with it.
func _restore_race_gates(animations_were: bool) -> void:
	_battle.animator.capturing = true
	Settings.set_speed(GameSpeed.CAPTURE_ID)
	Settings.set_battle_animations(animations_were)


## Sets Red's commander and, optionally, fills its meter, then refreshes the HUD
## so the bars read the state under test. Node-free: it writes only sim state.
## `id` is the scenario's default and yields to a general the launch already seated,
## so `--co=` reaches the frames that need a power — banner, quote, meter — for any
## general. Neutral is no seating, so the sweep, which names none, stages as before.
func _set_red_commander(id: StringName, charged: bool) -> CommanderType:
	var seated := _battle.game.commander_of(1)
	var co := seated if seated.has_power() else _battle.commander_db.by_id(id)
	_battle.game.set_commander(1, co)
	if charged:
		_battle.game.commander_state(1).charge = co.power_cost
	_battle.view.restage_identity()  # reflects the staged CO's name and colour, not just the meter
	return co


## Parks the cursor on open ground and lets the HUD settle before the capture. The
## docked bars never cover a tile, so where it rests is only about what the bottom
## bar is describing, not about dodging chrome.
func _settle_hud() -> void:
	_battle.set_cursor_cell(Vector2i(10, 5))
	await _battle.get_tree().create_timer(0.2).timeout


## The partly filled meter the commander block carries for most of a match.
func _stage_charging_power() -> String:
	var co := _set_red_commander(&"viktor_draeg", false)
	_battle.game.commander_state(1).charge = int(co.power_cost / 2)
	_battle.view.refresh_hud()
	await _settle_hud()
	return ""


## The COM-18 legibility frames. power_ready and power_ready_contrast stage the
## same ready meter and differ only in the board it is read against — the smoke
## harness launches the second on the bright strait. The chip's cursor-fade frame
## retired with the chip: a docked bar is never on top of a tile to fade off one.
func _stage_ready_power() -> String:
	_set_red_commander(&"mara_voss", true)
	await _settle_hud()
	return ""


## Raises a power directly (no fire, no banner) so the capture is the meter's
## ACTIVE state alone. Firing is proved by `power_banner`; this isolates the HUD.
func _stage_active_power() -> String:
	# The roster's longest power name makes this the truncation regression frame.
	var co := _battle.commander_db.by_id(&"viktor_draeg")
	_battle.game.set_commander(1, co)
	_battle.game.commander_state(1).power_active = true
	_battle.view.restage_identity()
	await _settle_hud()
	return ""


## A full computer meter with no player FIRE control.
func _stage_ai_power() -> String:
	var co := _battle.commander_db.by_id(&"nia_rowan")
	_battle.game.set_commander(2, co)
	_battle.game.commander_state(2).charge = co.power_cost
	_battle.game.current_team = 2
	_battle.view.restage_identity()
	await _settle_hud()
	return ""


## Both slots pick Iron; side two's commander block must keep the Iron name while
## borrowing the same Aurora blue its board wears.
func _stage_mirror_power() -> String:
	var co := _battle.commander_db.by_id(&"viktor_draeg")
	_battle.game.set_commander(1, co)
	_battle.game.set_commander(2, co)
	_battle.game.commander_state(2).charge = co.power_cost
	_battle.game.current_team = 2
	_battle.ai_teams.clear()  # Battle owns the list; hand the emptied one over again
	_battle.view.set_ai_teams(_battle.ai_teams)
	_battle.view.restage_identity()
	await _settle_hud()
	return ""


## Charges Red, then fires the power through the real Fire button so the
## activation card comes up exactly as it does in play. It holds on screen while
## capturing (see BattleAnimator.show_power_banner), so the frame is the banner.
func _stage_power_banner() -> String:
	_set_red_commander(&"cass_orlov", true)
	_battle.view.fire_pressed.emit()
	await _until_state(Battle.State.IDLE)
	return ""


## The first aimed Command Power (MC4), stopped mid-aim: Radek Morn's meter
## filled, the HUD's Fire button pressed, and the aim walked onto Red's own corner
## — an HQ, a base, a city and four of his units under one square, which is what
## makes the frame say that Hammerfall takes whatever is standing there and leaves
## the buildings alone.
##
## Checked as well as photographed, like power_mapmenu: the preview is supposed to
## be the doctrine's own footprint and nothing else, so the painted cells are read
## back off the layer and compared with what the power would actually clear. A
## preview that has stopped agreeing with the strike photographs perfectly well.
func _stage_power_targeting() -> String:
	_set_red_commander(&"radek_morn", true)
	_battle.view.fire_pressed.emit()
	await _until_state(Battle.State.POWER_TARGETING)
	_battle.set_cursor_cell(HAMMERFALL_AIM)
	await _battle.get_tree().create_timer(0.2).timeout
	return _check_blast_preview()


func _check_blast_preview() -> String:
	var game := _battle.game
	var doomed := game.commander_of(1).power_blast_cells(game, 1, HAMMERFALL_AIM)
	var painted := _battle.overlays.attack_layer.get_used_cells()
	painted.sort()
	doomed.sort()
	if painted == doomed:
		return ""
	return "the blast preview paints %s, the strike takes %s" % [painted, doomed]


## The keyboard route the ready meter advertises alongside F: Enter on empty
## ground, then the map menu's first row, which is the Command Power. The frame
## alone proves nothing — the board renders behind the opaque bars, so a menu drawn
## under one photographs just as well as one clear of it. Hence the check.
func _stage_power_map_menu() -> String:
	_set_red_commander(&"mara_voss", true)
	_battle.confirm_at(Vector2i(10, 5))  # empty road tile -> map menu
	await _until_state(Battle.State.MENU)
	return _check_map_menu_readable()


## The power row the hint sends the player to has to be visible when they get
## there, and the whole menu has to stay inside the board band.
func _check_map_menu_readable() -> String:
	var rows := BattleMenus.map_actions(_battle.game)
	if rows.is_empty() or rows[0].id != &"power":
		return "map menu opened without the Command Power as its first row"
	return BattleScenarioDriver.band_error(_battle, "map menu", _battle.action_menu)
