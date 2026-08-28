class_name BattleMobileScenario
extends BattleScenario
## The touch dock, driven (mobile plan MB3). It runs only under `--mobile`, which
## MobileProfile resolves once per process, so this mode can never share the
## sweep's one boot with a desktop scenario — `make smoke MODES=mobile_back` runs
## it on its own and tools/smoke_scenarios.sh adds the flag.
##
## What it proves is the dead ends the dock exists for, and the destructive one is
## the headline: an aimed Command Power is opened and then backed out of, and the
## meter is still full and the board still full of units afterwards. Then the three
## other targeting states, the zoom and next-unit chips, the two board gestures,
## and a computer turn paused and resumed from the bar. Every flow returns an error
## string rather than
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

## The middle of the board band, which is where a finger that means the board lands
## — the two bars and the dock swallow anything aimed at them.
const _BAND := Vector2(320, 160)

## Where each pushed finger last was, so a slide can state its own relative travel
## the way the engine states a real one's.
var _finger_at: Dictionary[int, Vector2] = {}


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
	flaw = flaw if flaw != "" else await _scroll_the_build_menu()
	flaw = flaw if flaw != "" else await _walk_the_board()
	flaw = flaw if flaw != "" else await _pinch_the_ladder()
	flaw = flaw if flaw != "" else await _pan_the_board()
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


## The build menu is the tallest in the game and the dock takes another row of
## chrome off the band, so on a touch build its last rows — Cancel among them, the
## only way out of it — are a scroll away. The menu has to fit the band it was
## given, and a finger has to be able to reach the rest of it and still pick with
## a tap.
func _scroll_the_build_menu() -> String:
	_battle.confirm_at(Vector2i(3, 2))  # the red base
	var flaw := await _reach(Battle.State.MENU)
	if flaw != "":
		return flaw
	var menu := _battle.action_menu
	# A container places its rows a frame after the menu opens, so a finger aimed
	# before that lands on whichever row was still standing at the origin.
	for _frame in 2:
		await _battle.get_tree().process_frame
	var band := MobileDock.board_band(_battle.get_viewport().get_visible_rect().size)
	if not band.encloses(menu.get_global_rect()):
		return "the build menu %s hangs out of the band %s" % [menu.get_global_rect(), band]
	var last := menu.rows.get_child(menu.rows.get_child_count() - 1) as Button
	if last.visible:
		return "the build menu fits whole, so this is measuring no scroll at all"
	flaw = await _wobble_on_a_row(menu)
	flaw = flaw if flaw != "" else await _drag_to_the_last_row(menu, last)
	flaw = flaw if flaw != "" else await _walk_the_menu(menu)
	flaw = flaw if flaw != "" else await _arm_the_last_row(menu, last)
	if flaw != "":
		return flaw
	# Cancel is the row a scroll exists to reach, and a tap is what takes it. One
	# point for both halves of the tap: a release read off a rect the last frame
	# moved would land outside the area the press armed, which is a cancelled tap.
	var take := last.get_global_rect().get_center()
	await _menu_finger(true, take)
	await _menu_finger(false, take)
	return await _reach(Battle.State.IDLE)


## A finger that wanders past the tap slop and comes back is scrolling, not
## picking: press and release land on the one row, which is the gesture that fires
## it unless the row's own hit area heard the list move under it. The window must
## not have walked either — a wobble is nobody asking for a row.
##
## On the armed row, which is the first the board can afford: a row this side has
## no funds for answers nothing whatever the finger does, so wobbling on one would
## photograph as a pass with the cancellation deleted.
func _wobble_on_a_row(menu: ActionMenu) -> String:
	var armed := _armed_row(menu)
	if armed == null:
		return "the build menu armed no row to wobble on"
	var at := armed.get_global_rect().get_center()
	var wander := Vector2(0, TouchGestures.TAP_SLOP_PX + 8.0)
	var opened_on := _first_visible(menu)
	var standing := _battle.game.units.size()
	await _menu_finger(true, at)
	await _menu_slide(at + wander)
	await _menu_slide(at)
	await _menu_finger(false, at)
	if _first_visible(menu) != opened_on:
		return "a wobble the width of the tap slop walked the window"
	if _battle.game.units.size() != standing:
		return "the wobble bought the row under the finger"
	return await _reach_menu("the wobble picked the row under the finger")


## The list follows the finger, so a drag up reaches the rows the band cut off —
## and lets go of none of them on the way. The highlight comes with the window,
## because an armed row nobody can see is a confirm nobody can predict; and the
## board must not have walked under the menu, which is the one place a drag could
## have reached `TouchGestures` instead.
func _drag_to_the_last_row(menu: ActionMenu, last: Button) -> String:
	var at := menu.get_global_rect().get_center()
	var to := at - Vector2(0, menu.get_global_rect().size.y * 0.4)
	var opened_on := _first_visible(menu)
	var stood_on := _battle.cursor_cell
	await _menu_finger(true, at)
	await _menu_slide(to)
	if _first_visible(menu) <= opened_on:
		return "dragging the list up never walked the window"
	if not last.visible:
		return "dragging the list up never reached its last row"
	if _battle.cursor_cell != stood_on:
		return "the drag panned the board under the menu, to %s" % _battle.cursor_cell
	var armed := _armed_row(menu)
	if armed == null or not armed.visible:
		return "the drag left the armed row off the window"
	await _menu_finger(false, to)
	return await _reach_menu("the drag picked a row off the list")


## A pad or a hardware key walks the highlight, and the window follows it the whole
## way down rather than only while the armed row happens to be inside it.
func _walk_the_menu(menu: ActionMenu) -> String:
	for _step in menu.rows.get_child_count():
		await _key(&"cursor_down")
		var armed := _armed_row(menu)
		if armed == null:
			return "the walked list armed no row at all"
		if not armed.visible:
			return "walking the list left the armed row [%s] off the window" % armed.text
	return ""


## Walks the highlight onto Cancel, which is what puts it in the window for the
## finger that takes it.
func _arm_the_last_row(menu: ActionMenu, last: Button) -> String:
	for _step in menu.rows.get_child_count():
		if _armed_row(menu) == last:
			for _frame in 2:
				await _battle.get_tree().process_frame  # the window settles before a finger aims
			return "" if last.visible else "the armed last row is off the window"
		await _key(&"cursor_down")
	return "walking the list never armed its last row"


func _reach_menu(complaint: String) -> String:
	var flaw := await _reach(Battle.State.MENU)
	return "" if flaw == "" else "%s: %s" % [complaint, flaw]


## Where the window opens, read the way a player reads it — off which rows are on
## screen — rather than off the index the menu keeps to itself.
func _first_visible(menu: ActionMenu) -> int:
	for i in menu.rows.get_child_count():
		if (menu.rows.get_child(i) as Control).visible:
			return i
	return -1


## The armed row of an open menu, read the way a player reads it — off the cursor
## the menu prints — rather than off the index it keeps to itself.
func _armed_row(menu: ActionMenu) -> Button:
	for row in menu.rows.get_children():
		var button := row as Button
		if button.text.begins_with("> "):
			return button
	return null


## One key press and release, so DirectionalInput counts it as a single gesture.
func _key(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		await _dispatch(event)


## A finger on a menu row, which the board's own `_finger` cannot stand in for: a
## Button is picked by the mouse press the device emulates from the touch, and only
## `Input` synthesises that — a touch pushed straight at the viewport arms nothing,
## so a test that pushed one could never see a row picked or a press cancelled.
## Positions are the canvas ones every rect here is in; `Input` takes window ones.
func _menu_finger(down: bool, at: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.pressed = down
	touch.position = _on_screen(at)
	_finger_at[touch.index] = touch.position
	await _dispatch(touch)


func _menu_slide(to: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.position = _on_screen(to)
	drag.relative = drag.position - _finger_at.get(drag.index, drag.position)
	_finger_at[drag.index] = drag.position
	await _dispatch(drag)


## `Input` buffers what it is handed and merges motion into one event a frame, so
## a step that only awaited a frame raced the flush and read the board before its
## own gesture had landed — which is a scenario that passes four runs in five.
## Flushed here, and only then awaited.
func _dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	for _frame in 2:
		await _battle.get_tree().process_frame


func _on_screen(at: Vector2) -> Vector2:
	return _battle.get_viewport().get_final_transform() * at


## The right thumb: both ends of the ladder, and the walk to the next ready unit.
func _walk_the_board() -> String:
	var opened_at := _battle.view.camera.zoom.x
	await _press_chip(&"zoom_out")
	if _battle.view.camera.zoom.x >= opened_at:
		return "the dock's minus never stepped the ladder"
	await _press_chip(&"zoom_in")
	if not is_equal_approx(_battle.view.camera.zoom.x, opened_at):
		return "the dock's plus did not step back to the opening rung"
	var wanted := ReadyUnits.after(_battle.game, _battle.cursor_cell)
	if wanted == null:
		return "no unit was ready for the dock's next-unit chip to walk to"
	await _press_chip(&"next_unit")
	if _battle.cursor_cell != wanted.cell:
		return "the dock's next-unit chip left the cursor at %s" % _battle.cursor_cell
	return ""


## Two fingers, spread by exactly the ladder's own gain and pinched back again.
## What is read back is the rule rather than the feel: the board lands on a rung of
## `BattleZoom`'s ladder both times, and undoing the spread lands on the rung the
## hand opened on.
func _pinch_the_ladder() -> String:
	var opened_at := _battle.view.camera.zoom.x
	var span := 100.0
	_finger(0, true, _BAND + Vector2(-span / 2.0, 0))
	_finger(1, true, _BAND + Vector2(span / 2.0, 0))
	var gain := TouchGestures.gain_for(_rungs())
	await _slide(1, _BAND + Vector2(span * gain - span / 2.0, 0))
	if _battle.view.camera.zoom.x <= opened_at:
		return "spreading two fingers never zoomed in"
	var flaw := _on_a_rung()
	if flaw != "":
		return flaw
	await _slide(1, _BAND + Vector2(span / 2.0, 0))
	if not is_equal_approx(_battle.view.camera.zoom.x, opened_at):
		return "pinching back landed on %f, not the rung it opened on" % _battle.view.camera.zoom.x
	_finger(1, false, _BAND + Vector2(span / 2.0, 0))
	_finger(0, false, _BAND + Vector2(-span / 2.0, 0))
	return await _reach(Battle.State.IDLE)


## One finger, dragged two cells across a unit. The board walks with it, the camera
## comes to rest on whole world pixels, and the release confirms nothing — a drag
## that began on a unit must never become a move (mobile R1 in its second form).
## Then the same finger taps, which is what does select it.
func _pan_the_board() -> String:
	var stood_on := Vector2i(8, 8)  # the red tank
	_battle.set_cursor_cell(stood_on)
	var at: Vector2 = _battle.pointer.screen_of(stood_on)
	var cell_px := float(BattleView.TILE) * _battle.view.camera.zoom.x
	_finger(0, true, at)
	await _slide(0, at + Vector2(2.0 * cell_px, 0))
	if _battle.cursor_cell != stood_on - Vector2i(2, 0):
		return "a two-cell drag left the cursor at %s" % _battle.cursor_cell
	if _battle.view.camera.position != _battle.view.camera.position.floor():
		return "the pan left the camera at %s" % _battle.view.camera.position
	_finger(0, false, at + Vector2(2.0 * cell_px, 0))
	var flaw := await _reach(Battle.State.IDLE)
	if flaw != "":
		return "the drag selected something: %s" % flaw
	# The board walked under the finger, so the tank is somewhere else on the screen
	# now — which is the pan having worked.
	var moved_to: Vector2 = _battle.pointer.screen_of(stood_on)
	_finger(0, true, moved_to)
	_finger(0, false, moved_to)
	flaw = await _reach(Battle.State.UNIT_SELECTED)
	if flaw != "":
		return "a tap on the tank did not pick it up: %s" % flaw
	return await _press_back(Battle.State.IDLE)


## The rungs this board offers, asked of the ladder rather than rebuilt.
func _rungs() -> PackedFloat64Array:
	return BattleZoom.rungs_for(_battle.view.board_camera.min_zoom())


func _on_a_rung() -> String:
	for rung: float in _rungs():
		if is_equal_approx(rung, _battle.view.camera.zoom.x):
			return ""
	return "the pinch rested at %f, which is no rung of this board" % _battle.view.camera.zoom.x


## A finger landing or lifting. Pushed through the viewport the way a real one
## arrives, so the whole path — `_unhandled_input`, BoardPointer, TouchGestures —
## is what answers rather than any of them being called directly.
func _finger(index: int, down: bool, at: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.pressed = down
	touch.position = at
	_finger_at[index] = at
	_battle.get_tree().root.push_input(touch, true)


func _slide(index: int, to: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = to
	drag.relative = to - _finger_at.get(index, to)
	_finger_at[index] = to
	_battle.get_tree().root.push_input(drag, true)
	for _frame in 2:
		await _battle.get_tree().process_frame


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
	await _press_chip(&"cancel")
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
	await _press_chip(&"confirm")
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
	await _press_chip(&"cancel")
	if _battle.state != wanted:
		return "Back left state %d, not %d" % [_battle.state, wanted]
	return ""


## A real press on the chip, a different mechanism from the inherited
## `_press_action` and deliberately so: what a check here proves is that the
## dock's own button reaches the action, so the press is the button's and the
## wait is for the engine to flush what it dispatched.
func _press_chip(action: StringName) -> void:
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
