class_name BattleMobileScenario
extends RefCounted
## The touch dock, driven (mobile plan MB3). It runs only under `--mobile`, which
## MobileProfile resolves once per process, so this mode can never share the
## sweep's one boot with a desktop scenario — `make smoke MODES=mobile_back` runs
## it on its own and tools/smoke_scenarios.sh adds the flag.
##
## What it proves is the dead ends the dock exists for, and the destructive one is
## the headline: an aimed Command Power is opened and then backed out of, and the
## meter is still full and the board still full of units afterwards. Then the three
## other targeting states, the zoom and next-unit chips, and a computer turn paused
## and resumed from the bar. Every flow returns an error string rather than
## reporting one, the way its sibling scenarios do — the driver's `_fail` owns the
## push_error and the exit-code flag together.

const MODES: Array[String] = ["mobile_back"]

## Radek Morn's blast, aimed at Red's own corner — the cell the keyboard's
## `power_targeting` mode aims at, so the two stage one board.
const AIM := Vector2i(3, 3)

## How long a step waits for the board to settle before it says it never did. A
## scenario that parked until the sweep's own deadline would report a timeout with
## no name on it.
const WAIT_FRAMES := 900

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


func run(mode: String) -> String:
	if mode != "mobile_back":
		return "unknown mobile scenario: %s" % mode
	if _dock() == null:
		return "no dock on a --mobile build"
	if MobileDock.chrome_h() != UiTheme.HUD_BARS_H + UiTheme.HUD_DOCK_H:
		return "the dock's height never reached the board's viewport"
	var flaw := await _back_out_of_a_selection()
	flaw = flaw if flaw != "" else await _back_out_of_a_preview()
	flaw = flaw if flaw != "" else await _back_out_of_targeting()
	flaw = flaw if flaw != "" else await _back_out_of_a_drop()
	flaw = flaw if flaw != "" else await _back_out_of_an_aimed_power()
	flaw = flaw if flaw != "" else await _walk_the_board()
	flaw = flaw if flaw != "" else await _pause_and_resume_a_computer_turn()
	return flaw


## Rest: the leading chip opens the map menu, and the two parked-turn chips are
## dead — Resume dispatches `confirm`, which here would select a unit.
func _back_out_of_a_selection() -> String:
	if _word() != ControlHints.DOCK_MENU:
		return "the resting chip reads %s" % _word()
	if not _chip(&"confirm").disabled or not _chip(&"replay_step").disabled:
		return "a resting board offered Resume or Step"
	_battle.confirm_at(Vector2i(8, 8))  # the red tank
	var flaw := await _reach(Battle.State.UNIT_SELECTED)
	if flaw != "":
		return flaw
	if _word() != ControlHints.DOCK_BACK:
		return "a unit in hand reads %s" % _word()
	return await _press_back(Battle.State.IDLE)


func _back_out_of_a_preview() -> String:
	_battle.confirm_at(Vector2i(9, 8))  # a unit this side may only inspect
	var flaw := await _reach(Battle.State.PREVIEW)
	if flaw != "":
		return flaw
	return await _press_back(Battle.State.IDLE)


## Targeting backs out to the unit's own menu, which the dock is dead under — that
## menu owns the input — so the menu's Cancel row is what leaves it, and the unit
## left in hand is then put down with the dock again.
func _back_out_of_targeting() -> String:
	var flaw := await _open_unit_menu(Vector2i(8, 8), Vector2i(8, 8))
	if flaw != "":
		return flaw
	_battle.action_menu.choose(&"fire")
	flaw = await _reach(Battle.State.TARGETING)
	if flaw != "":
		return flaw
	if _word() != ControlHints.DOCK_BACK:
		return "targeting reads %s" % _word()
	flaw = await _press_back(Battle.State.MENU)
	if flaw != "":
		return flaw
	if not _chip(&"cancel").disabled:
		return "the dock stayed live under an open menu"
	_battle.action_menu.choose(&"cancel")
	flaw = await _reach(Battle.State.UNIT_SELECTED)
	if flaw != "":
		return flaw
	return await _press_back(Battle.State.IDLE)


func _back_out_of_a_drop() -> String:
	var flaw := await _open_unit_menu(Vector2i(4, 3), Vector2i(3, 3))  # infantry onto the APC
	if flaw != "":
		return flaw
	_battle.action_menu.choose(&"load")
	flaw = await _reach(Battle.State.IDLE)
	if flaw != "":
		return flaw
	flaw = await _open_unit_menu(Vector2i(3, 3), Vector2i(3, 5))  # drive the APC south
	if flaw != "":
		return flaw
	_battle.action_menu.choose(&"drop_0")
	flaw = await _reach(Battle.State.DROP_TARGETING)
	if flaw != "":
		return flaw
	flaw = await _press_back(Battle.State.MENU)
	if flaw != "":
		return flaw
	_battle.action_menu.choose(&"wait")
	return await _reach(Battle.State.IDLE)


## The headline. In POWER_TARGETING every tap on the board fires the blast at the
## cell it landed on, so the meter and the board are read back after the abort:
## nothing spent, nobody removed.
func _back_out_of_an_aimed_power() -> String:
	var game := _battle.game
	game.set_commander(1, _battle.commander_db.by_id(&"radek_morn"))
	game.commander_state(1).charge = game.commander_of(1).power_cost
	_battle.view.restage_identity()
	var charge := game.commander_state(1).charge
	var standing := game.units.size()
	_battle.view.fire_pressed.emit()
	var flaw := await _reach(Battle.State.POWER_TARGETING)
	if flaw != "":
		return flaw
	if _word() != ControlHints.DOCK_BACK:
		return "an aimed power reads %s" % _word()
	_battle.set_cursor_cell(AIM)
	flaw = await _press_back(_battle.rest_state())
	if flaw != "":
		return flaw
	if game.commander_state(1).charge != charge:
		return "backing out of the aim spent %d charge" % (charge - game.commander_state(1).charge)
	if game.units.size() != standing:
		return "backing out of the aim removed %d units" % (standing - game.units.size())
	return ""


## The right thumb: both ends of the ladder, and the walk to the next ready unit.
func _walk_the_board() -> String:
	var opened_at := _battle.view.camera.zoom.x
	await _press(&"zoom_out")
	if _battle.view.camera.zoom.x >= opened_at:
		return "the dock's minus never stepped the ladder"
	await _press(&"zoom_in")
	if not is_equal_approx(_battle.view.camera.zoom.x, opened_at):
		return "the dock's plus did not step back to the opening rung"
	var wanted := ReadyUnits.after(_battle.game, _battle.cursor_cell)
	if wanted == null:
		return "no unit was ready for the dock's next-unit chip to walk to"
	await _press(&"next_unit")
	if _battle.cursor_cell != wanted.cell:
		return "the dock's next-unit chip left the cursor at %s" % _battle.cursor_cell
	return ""


## A watched turn is the state the bar matters most in: there is no other route to
## a menu at all. Back asks for the pause, which the runner honours at its next
## command boundary by opening the pause menu over the frozen board; Resume hands
## the turn back to a runner that picks it up where it stopped.
func _pause_and_resume_a_computer_turn() -> String:
	await BattleFeedbackScenario.new(_battle).end_turn_anyway()
	var flaw := await _reach(Battle.State.AI_TURN)
	if flaw != "":
		return flaw
	if _word() != ControlHints.DOCK_PAUSE:
		return "a computer turn reads %s" % _word()
	await _press(&"cancel")
	flaw = await _reach(Battle.State.MENU)
	if flaw != "":
		return "the dock's pause never reached the menu: %s" % flaw
	_battle.action_menu.choose(&"cancel")
	flaw = await _reach(Battle.State.PAUSED)
	if flaw != "":
		return flaw
	if _chip(&"confirm").disabled:
		return "a paused turn offered no Resume"
	if not _chip(&"replay_step").disabled:
		return "a paused computer turn offered Step, which only a replay has"
	await _press(&"confirm")
	if _battle.state == Battle.State.PAUSED:
		return "Resume left the turn parked"
	while _battle.game.winner == 0 and _battle.state == Battle.State.AI_TURN:
		await _battle.get_tree().process_frame
	# Back on the player's board, so the frame this mode leaves behind is the bar
	# with its chips live rather than greyed under the turn banner.
	return await _reach(Battle.State.IDLE)


## Select at `from` and finish the move on `to`, which is where the unit's own
## action menu opens — the two confirms a player makes.
func _open_unit_menu(from: Vector2i, to: Vector2i) -> String:
	_battle.confirm_at(from)
	_battle.confirm_at(to)
	return await _reach(Battle.State.MENU)


func _press_back(wanted: Battle.State) -> String:
	await _press(&"cancel")
	if _battle.state != wanted:
		return "Back left state %d, not %d" % [_battle.state, wanted]
	return ""


## A real press on the chip: the dispatched action is the keyboard's, so it lands
## through the same `_unhandled_input` a key would — which is why this waits for
## the engine to flush it rather than calling a Battle branch.
func _press(action: StringName) -> void:
	var chip := _chip(action)
	if chip != null and not chip.disabled:
		chip.pressed.emit()
	for _frame in 3:
		await _battle.get_tree().process_frame


func _chip(action: StringName) -> Button:
	return _dock().chip_for(action)


func _word() -> String:
	return _dock().back_word()


func _dock() -> MobileDock:
	return _battle.view.mobile_dock


## Waits for a state and says so when it never arrives, rather than parking the run
## until the sweep's own deadline kills it with no diagnosis.
func _reach(wanted: Battle.State) -> String:
	for _frame in WAIT_FRAMES:
		if _battle.state == wanted:
			return ""
		await _battle.get_tree().process_frame
	return "the board stopped at state %d, waiting for %d" % [_battle.state, wanted]
