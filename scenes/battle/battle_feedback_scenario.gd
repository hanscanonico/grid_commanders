class_name BattleFeedbackScenario
extends BattleScenario
## Driven feedback acceptance flows, split out so BattleScenarioDriver stays
## under its linted size cap. Every flow — `run` included — returns an error
## string rather than reporting one: the driver's `_fail` owns the push_error
## and the exit-code flag together, and the two are not separable.

## The modes this class drives, asked of it by BattleScenarioDriver rather than
## listed there a second time.
const MODES: Array[String] = [
	"rejected_confirm",
	"enemy_range_preview",
	"end_turn_ready_units",
	"power_range_readout",
	"mapmenu",
]


func run(mode: String) -> String:
	match mode:
		"rejected_confirm":
			return await _run_rejected_confirms()
		"enemy_range_preview":
			return await _run_enemy_range_preview()
		"end_turn_ready_units":
			return await _run_end_turn_ready_units()
		"power_range_readout":
			return _run_power_range_readout()
		"mapmenu":
			return await _run_map_menu()
	return "unknown feedback scenario: %s" % mode


## The map menu, stopped where a capture photographs it — and what its value rows
## answer a confirm with. A row carrying a `cycle` steps where it stands and the
## menu stays up (COM-246): a confirm that stepped the setting and then closed
## over it left a player who pressed ENTER on "Speed: Normal" meaning to pick it
## one tier faster, with the row that says so gone — which is how a device ends up
## playing at Instant nobody chose.
##
## A whole lap of the ladder rather than one step, so the frame this mode is here
## to take is still the tier the capture pinned.
func _run_map_menu() -> String:
	_battle.confirm_at(Vector2i(10, 5))  # empty road tile -> End Turn / Save
	await _until_state(Battle.State.MENU)
	var opened_at := Settings.speed.id
	for _lap in GameSpeed.ordered().size():
		var next_tier := Settings.stepped_speed(Settings.speed.id, 1)
		_battle.action_menu.choose(Settings.SPEED_ROW)
		if not _battle.action_menu.visible or _battle.state != Battle.State.MENU:
			return "the Speed row closed the map menu over its own change"
		if Settings.speed.id != next_tier:
			return "a confirmed Speed row set %s, not %s" % [Settings.speed.id, next_tier]
	if Settings.speed.id != opened_at:
		return "a lap of the Speed ladder ended on %s, not %s" % [Settings.speed.id, opened_at]
	return ""


## Ends a turn through the live map-menu route and, when the COM-14 guard opens,
## chooses its explicit destructive action. Existing endturn/aiturn smoke modes
## use this so the new guard cannot quietly strand either flow.
func end_turn_anyway() -> void:
	await _open_end_turn()
	var guard := _guard()
	if guard != null and guard.visible:
		_press_button(guard, "End anyway")
		await _battle.get_tree().process_frame


func _run_rejected_confirms() -> String:
	var feedback := _battle.action_feedback

	var infantry := _battle.game.unit_at(Vector2i(4, 3))
	infantry.acted = true
	_battle.confirm_at(infantry.cell)
	var error := _expect_reason(feedback, "Already acted.")
	if error != "":
		return error
	_battle.confirm_at(Vector2i(10, 5))  # dismiss the range preview
	infantry.acted = false

	_battle.confirm_at(Vector2i(3, 2))  # build a unit through the live menu
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"infantry")
	await _until_state(Battle.State.IDLE)
	_battle.confirm_at(Vector2i(3, 2))
	error = _expect_reason(feedback, "Ready next day.")
	if error != "":
		return error
	_battle.confirm_at(Vector2i(10, 5))  # dismiss the range preview

	_battle.confirm_at(infantry.cell)
	_battle.confirm_at(Vector2i(2, 4))  # occupied by a friendly mech; no Load/Join
	error = _expect_reason(feedback, "Occupied.")
	if error != "":
		return error

	_battle.confirm_at(Vector2i(10, 5))  # nowhere near the mint reach
	error = _expect_reason(feedback, "Out of reach.")
	if error != "":
		return error
	await _press_action(&"fire_power")  # the Fire key with a unit in hand
	error = _expect_reason(feedback, BattlePower.MID_ACTION)
	if error != "":
		return error

	# Back out the selection the way a player would before handing the turn over:
	# a human selection left live under the CPU-turn chip is a board the game
	# cannot reach, and this mode's frame is photographed exactly there.
	await _press_action(&"cancel")
	if _battle.state != Battle.State.IDLE:
		return "cancel did not clear the selection before the CPU turn"

	error = await _run_no_target_confirm()
	if error != "":
		return error
	error = await _run_bad_unload_confirm()
	if error != "":
		return error
	error = await _run_power_key_refusals()
	if error != "":
		return error

	_battle.state = Battle.State.AI_TURN
	_battle.confirm_at(_battle.cursor_cell)
	return _expect_reason(feedback, "CPU turn.")


## Aiming a shot and confirming on ground no target stands on. The two tanks in
## frontline contact are what makes Fire an offered row from a standing start.
func _run_no_target_confirm() -> String:
	_battle.confirm_at(Vector2i(8, 8))  # the red tank
	_battle.confirm_at(Vector2i(8, 8))  # stand still, and open its orders
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"fire")
	await _until_state(Battle.State.TARGETING)
	_battle.confirm_at(Vector2i(8, 6))
	var error := _expect_reason(_battle.action_feedback, "No target there.")
	if error != "":
		return error
	await _press_action(&"cancel")  # back to the orders
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"cancel")
	await _press_action(&"cancel")
	return await _expect_rest("aiming")


## Unloading onto ground the transport cannot reach. The infantry boards the APC
## beside it first, a drop row being the only way into DROP_TARGETING.
func _run_bad_unload_confirm() -> String:
	_battle.confirm_at(Vector2i(4, 3))  # the infantry
	_battle.confirm_at(Vector2i(3, 3))  # onto the APC: a Load destination
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"load")
	await _until_state(Battle.State.IDLE)

	_battle.confirm_at(Vector2i(3, 3))  # the loaded APC
	_battle.confirm_at(Vector2i(3, 3))
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"drop_0")
	await _until_state(Battle.State.DROP_TARGETING)
	_battle.confirm_at(Vector2i(10, 5))
	var error := _expect_reason(_battle.action_feedback, "Cannot unload there.")
	if error != "":
		return error
	await _press_action(&"cancel")  # back to the orders
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"cancel")
	await _press_action(&"cancel")
	return await _expect_rest("unloading")


## The Fire key on a meter that cannot fire. The bar hides its Fire button until
## the meter fills, so this key is the only route to either refusal.
func _run_power_key_refusals() -> String:
	await _press_action(&"fire_power")
	var error := _expect_reason(_battle.action_feedback, BattlePower.NO_POWER)
	if error != "":
		return error

	var sol := _battle.commander_db.by_id(&"rhea_sol")
	_battle.game.set_commander(1, sol)
	await _press_action(&"fire_power")
	error = _expect_reason(_battle.action_feedback, BattlePower.CHARGING % [0, sol.power_cost])
	# The board this mode photographs seats no commander; put it back.
	_battle.game.set_commander(1, null)
	return error


func _expect_rest(after: String) -> String:
	await _battle.get_tree().process_frame
	if _battle.state != Battle.State.IDLE:
		return "backing out of %s left the board in state %d" % [after, _battle.state]
	return ""


func _run_enemy_range_preview() -> String:
	_battle.set_cursor_cell(Vector2i(9, 8))
	_battle.confirm_at(Vector2i(9, 8))
	if _battle.state != Battle.State.PREVIEW:
		return "enemy confirm did not enter PREVIEW"
	if _battle.overlays.move_layer.get_used_cells().is_empty():
		return "enemy preview painted no movement reach"
	await _press_action(&"show_range")
	if _battle.overlays.attack_layer.get_used_cells().is_empty():
		return "R painted no enemy fire ring"
	return await _run_range_from_rest()


## The same reading asked for with one key from rest, which is what R is for. Both
## units a confirm can only preview are walked — an enemy, and one of ours that has
## already acted — because those are the two the ring used to cost two presses; then
## the cursor walks back onto the enemy with a ring already up, where R must re-aim
## rather than put the infantry's down. The last ring is left standing: this mode's
## frame is the feature, and a board cleared back to rest photographs nothing.
func _run_range_from_rest() -> String:
	await _press_action(&"cancel")
	if _battle.state != Battle.State.IDLE:
		return "cancel did not dismiss the enemy preview"
	if not _battle.overlays.attack_layer.get_used_cells().is_empty():
		return "dismissing the preview left the fire ring on the board"
	var error := await _expect_ring_from_rest(Vector2i(9, 8), "the enemy")
	if error != "":
		return error
	var enemy_ring := _battle.overlays.attack_layer.get_used_cells()
	await _press_action(&"cancel")

	var infantry := _battle.game.unit_at(Vector2i(4, 3))
	infantry.acted = true
	error = await _expect_ring_from_rest(infantry.cell, "an already-acted unit of ours")
	infantry.acted = false
	if error != "":
		return error
	return await _expect_ring_follows_cursor(Vector2i(9, 8), enemy_ring)


func _expect_ring_from_rest(cell: Vector2i, whose: String) -> String:
	_battle.set_cursor_cell(cell)
	await _press_action(&"show_range")
	if _battle.overlays.attack_layer.get_used_cells().is_empty():
		return "R from rest painted no fire ring for %s" % whose
	return ""


func _expect_ring_follows_cursor(cell: Vector2i, expected: Array[Vector2i]) -> String:
	_battle.set_cursor_cell(cell)
	await _press_action(&"show_range")
	var painted := _battle.overlays.attack_layer.get_used_cells()
	if painted.is_empty():
		return "R put the last unit's ring down instead of re-aiming at the cursor's"
	if painted != expected:
		return "R re-aimed onto a ring that is not the cursor's unit's"
	return ""


## The other half of what the game tells a player about reach: the bar's printed
## ring, under a doctrine that moves it. Rhea Sol's Grid Saturation pushes her
## indirects one tile out, so a bar reading the unit type prints a range the fire
## ring and AttackCommand both play differently. Checked rather than photographed
## — a wrong pair of numbers renders exactly as well as the right one.
func _run_power_range_readout() -> String:
	var cell := Vector2i(4, 4)  # the red artillery on the default board
	var gun := _battle.game.unit_at(cell)
	if gun == null or not AttackRange.is_indirect(gun):
		return "no indirect unit at %s to read a range off" % cell
	_battle.set_cursor_cell(cell)
	var error := _expect_printed_range(gun, "with no power running")
	if error != "":
		return error

	var plain := AttackRange.maximum(_battle.game, gun)
	_battle.game.set_commander(1, _battle.commander_db.by_id(&"rhea_sol"))
	_battle.game.commander_state(1).power_active = true
	_battle.view.restage_identity()
	_battle.refresh_panel()
	if AttackRange.maximum(_battle.game, gun) <= plain:
		return "Grid Saturation left the gun's range at %d, so there is nothing to read" % plain
	error = _expect_printed_range(gun, "with Grid Saturation running")
	if error != "":
		return error

	var cover_error := _expect_no_cover()
	# The copter is flown in for that read-back alone; the frame this mode is
	# photographed on is the gun's.
	_battle.set_cursor_cell(cell)
	_battle.refresh_panel()
	return cover_error


## The other thing the bar can promise and the formula then refuse: a copter on a
## mountain stands on four stars and fights with none. Read back against
## CombatResolver, the authority the damage formula itself asks.
func _expect_no_cover() -> String:
	var cell := Vector2i(3, 6)  # mountain on the default board
	var terrain := _battle.map.terrain_at(cell)
	if terrain.defense_stars <= 0:
		return "%s gives no cover to lose, so there is nothing to read" % cell
	var copter := Unit.create(_battle.unit_db.by_id(&"b_copter"), 1, cell)
	_battle.game.units.append(copter)
	_battle.view.sync_sprites()
	_battle.set_cursor_cell(cell)
	_battle.refresh_panel()
	var line := _battle.view.unit_order_line()
	var cover := CombatResolver.cover_stars(_battle.game, copter, cell)
	_battle.game.remove_unit(copter)
	_battle.view.sync_sprites()
	if cover != 0:
		return "the copter takes cover on %s, so the bar is right to stay quiet" % cell
	if "NO COVER" in line:
		return ""
	return "the bar reads '%s' for a copter on %d-star ground" % [line, terrain.defense_stars]


## The bar has to print the ring AttackRange answers with, doctrine included.
func _expect_printed_range(unit: Unit, when: String) -> String:
	var band := AttackRange.band(_battle.game, unit)
	var wanted := "RNG %d-%d" % [band.x, band.y]
	var line := _battle.view.unit_order_line()
	if wanted in line:
		return ""
	return "the bar reads '%s' %s; AttackRange says %s" % [line, when, wanted]


func _run_end_turn_ready_units() -> String:
	# Hot-seat makes the no-ready path stop at the handoff instead of immediately
	# letting the AI race through the next side before the scenario can inspect it.
	_battle.ai_teams.clear()
	_battle.view.set_ai_teams(_battle.ai_teams)
	var starting_team := _battle.game.current_team

	var error := await _run_bar_end_turn(starting_team)
	if error != "":
		return error
	error = await _run_key_end_turn(starting_team)
	if error != "":
		return error
	error = await _run_guard_safe_answers(starting_team)
	if error != "":
		return error
	error = await _run_spent_turn_bypass(starting_team)
	if error != "":
		return error
	return await _run_guard_commit()


## The bottom bar's End Turn button, clicked where it is hardest: from a preview,
## the second rest state it is live in. The click has to reach the same guard the
## map-menu row does, go dead while that guard is up, and take the preview's blue
## reach with it — nothing on the turn path clears that paint, so a preview left
## standing would be handed to the next side. Answered safely, so the turn this
## flow hands on to is still the one it started.
func _run_bar_end_turn(starting_team: int) -> String:
	var resting_at := _battle.cursor_cell
	_battle.set_cursor_cell(Vector2i(9, 8))  # the enemy tank on the default board
	_battle.confirm_at(Vector2i(9, 8))
	if _battle.state != Battle.State.PREVIEW:
		return "the enemy confirm the button is judged from did not open a preview"
	var button := _button(
		_battle.view.hud_bottom, ControlHints.chip_for(ControlHints.END_TURN_CHIP)
	)
	if button == null:
		return "the bottom bar offers no End Turn button"
	if button.disabled:
		return "the bar's End Turn button was dead on the player's own board"
	await _click(button)
	var guard := _guard()
	if guard == null or not guard.visible:
		return "the bar's End Turn button did not reach the ready-unit guard"
	if not button.disabled:
		return "the bar's End Turn button stayed live under its own guard"
	if not _battle.overlays.move_layer.get_used_cells().is_empty():
		return "the preview's reach outlived the turn the bar's button ended"
	var armed := await _await_armed(guard)  # the guard arms its safe action a frame late
	if armed != "":
		return armed
	await _press_key(KEY_ESCAPE)
	if guard.visible or _battle.game.current_team != starting_team:
		return "the guard the bar's button opened did not return to the same turn"
	_battle.set_cursor_cell(resting_at)
	return ""


## E, the key the button now prints. It has to reach the same guard the button
## does from rest, and be dead with a unit in hand — there the cursor is planning
## a move, and the board is not the player's to hand over mid-plan.
func _run_key_end_turn(starting_team: int) -> String:
	var ready := ReadyUnits.of(_battle.game, starting_team)
	if ready.is_empty():
		return "the key's turn opened with nobody ready to hold the board"
	_battle.set_cursor_cell(ready[0].cell)
	_battle.confirm_at(ready[0].cell)
	if _battle.state != Battle.State.UNIT_SELECTED:
		return "the friendly confirm the key is judged from did not take a unit in hand"
	await _press_key(KEY_E)
	if _guard().visible or _battle.state != Battle.State.UNIT_SELECTED:
		return "E ended the turn with a unit in hand"
	await _press_key(KEY_ESCAPE)  # put the unit back down; the board is at rest again
	if _battle.state != Battle.State.IDLE:
		return "cancelling the unit in hand did not return the board to rest"
	await _press_key(KEY_E)
	var guard := _guard()
	if guard == null or not guard.visible:
		return "E did not reach the ready-unit guard from rest"
	var armed := await _await_armed(guard)
	if armed != "":
		return armed
	await _press_key(KEY_ESCAPE)
	if guard.visible or _battle.game.current_team != starting_team:
		return "the guard E opened did not return to the same turn"
	return ""


## Both safe answers, keyboard then mouse: each has to close the guard on the
## turn it was opened from, with no command applied.
func _run_guard_safe_answers(starting_team: int) -> String:
	await _open_end_turn()
	var guard := _guard()
	if guard == null or not guard.visible:
		return "End Turn committed with ready units instead of opening its guard"
	var error := _expect_guard(guard, starting_team)
	if error != "":
		return error
	error = await _run_guard_keyboard(guard)
	if error != "":
		return error
	if guard.visible or _battle.game.current_team != starting_team:
		return "the keyboard's safe answer did not return to the same turn"

	await _open_end_turn()
	var review := _button(guard, "Review units")
	if review == null:
		return "ready-unit guard has no Review units button"
	await _click(review)
	if guard.visible or _battle.game.current_team != starting_team:
		return "Review units did not return to the same turn"
	return ""


## Spent turns must keep the old zero-friction path. Marking these units acted
## stages the state a player reaches by using each one; End Turn itself still
## travels through the live menu and command pipeline.
func _run_spent_turn_bypass(starting_team: int) -> String:
	for unit in ReadyUnits.of(_battle.game, starting_team):
		unit.acted = true
	await _open_end_turn()
	var error := await _wait_for_team_change(starting_team)
	if error != "":
		return error
	if _guard().visible:
		return "End Turn showed the ready-unit guard with no ready units"
	return ""


## The destructive answer, and the day-two guard the capture photographs: Enter
## on the stepped-to End anyway has to reach the same EndTurnCommand the mouse
## does, and the guard has to open again on the next side that owes actions.
func _run_guard_commit() -> String:
	if _battle.state == Battle.State.HANDOFF:
		_battle.leave_handoff()
	# A player may open the menu once the incoming banner has retired. The
	# capture skips that presentation wait, just as the driver hid day one's
	# banner before this flow began.
	_battle.animator.hide_banner()
	await _battle.get_tree().process_frame
	var next_team := _battle.game.current_team
	await _open_end_turn()
	var guard := _guard()
	if guard == null or not guard.visible:
		return "next side's ready units did not reopen the End Turn guard"
	var error := _expect_guard(guard, next_team)
	if error != "":
		return error

	# Enter on the stepped-to destructive choice is the keyboard's commit, and it
	# has to reach the same EndTurnCommand the mouse does.
	error = await _await_armed(guard)
	if error != "":
		return error
	await _press_key(KEY_RIGHT)
	await _press_key(KEY_ENTER)
	if await _wait_for_team_change(next_team) != "":
		return "keyboard End anyway did not commit the turn"
	if guard.visible:
		return "the guard stayed open after End anyway"

	# Day two, back on the first side: the guard opens once more, and that is the
	# frame this mode photographs.
	if _battle.state == Battle.State.HANDOFF:
		_battle.leave_handoff()
	_battle.animator.hide_banner()
	await _battle.get_tree().process_frame
	await _open_end_turn()
	if not guard.visible:
		return "the first side's day-two ready units did not reopen the guard"
	return _expect_guard(guard, _battle.game.current_team)


## The keyboard half of the guard: it opens with the safe action armed, the two
## actions step under left/right, and Escape answers Review — so a player who
## never reaches for the mouse can still back out of a turn they meant to keep.
func _run_guard_keyboard(guard: Control) -> String:
	var error := await _await_armed(guard)
	if error != "":
		return error
	await _press_key(KEY_RIGHT)
	if _focused_text(guard) != "End anyway":
		return "right did not step to End anyway (armed: '%s')" % _focused_text(guard)
	await _press_key(KEY_LEFT)
	if _focused_text(guard) != "Review units":
		return "left did not step back to Review units (armed: '%s')" % _focused_text(guard)
	await _press_key(KEY_ESCAPE)
	return ""


## The guard arms Review a frame late by design, so waiting for focus is also the
## check that the *safe* action is the one an immediate Enter would take.
func _await_armed(guard: Control) -> String:
	for frame in 30:
		var text := _focused_text(guard)
		if text == "Review units":
			return ""
		if text != "":
			return "the guard armed '%s' instead of Review units" % text
		await _battle.get_tree().process_frame
	return "the guard opened with no armed action"


func _focused_text(guard: Control) -> String:
	var focused := guard.get_viewport().gui_get_focus_owner() as Button
	if focused == null or not guard.is_ancestor_of(focused):
		return ""
	return focused.text


func _open_end_turn() -> void:
	_battle.confirm_at(Vector2i(10, 5))
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"end_turn")
	await _battle.get_tree().process_frame


func _wait_for_team_change(previous_team: int) -> String:
	for frame in 120:
		if _battle.game.current_team != previous_team:
			return ""
		await _battle.get_tree().process_frame
	return "spent turn did not commit after %d frames" % 120


func _expect_guard(guard: Control, team: int) -> String:
	var ready := ReadyUnits.of(_battle.game, team)
	var copy := _control_text(guard)
	var count_copy := "%d READY" % ready.size()
	if not copy.contains(count_copy):
		return "ready-unit guard copy has no '%s'" % count_copy
	for unit in ready:
		var line := "%s at (%d,%d)" % [unit.type.display_name, unit.cell.x, unit.cell.y]
		if not copy.contains(line):
			return "ready-unit guard does not name '%s'" % line
	for action in ["Review units", "End anyway"]:
		if not copy.contains(action):
			return "ready-unit guard has no '%s' action" % action
	var legend := ControlHints.legend_for(ControlHints.END_TURN_GUARD)
	if not _control_text(_battle.view.hud_top).contains(legend):
		return "the top bar does not print the guard's own legend '%s'" % legend
	return ""


func _guard() -> EndTurnGuard:
	return _battle.end_turn_guard


func _control_text(root: Control) -> String:
	var parts := PackedStringArray()
	for node in root.find_children("*", "", true, false):
		if node is Label:
			parts.append((node as Label).text)
		elif node is Button:
			parts.append((node as Button).text)
	return "\n".join(parts)


func _button(root: Control, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == text:
			return button
	return null


func _press_button(root: Control, text: String) -> bool:
	var button := _button(root, text)
	if button == null:
		return false
	button.pressed.emit()
	return true


## A real click at the button's own rect rather than its `pressed` signal: the
## guard veils the board with a pointer-swallowing rect, so "the actions are on
## top of it" is part of what mouse-operable means here. The event is injected in
## window coordinates, so the 640x360 rect goes through the stretch transform the
## viewport would otherwise undo underneath it.
func _click(button: Button) -> void:
	var viewport := _battle.get_viewport()
	var at := viewport.get_final_transform() * button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		await _battle.get_tree().process_frame


func _expect_reason(feedback: ActionFeedback, expected: String) -> String:
	if feedback.reason == expected:
		return ""
	return "rejected confirm showed '%s', expected '%s'" % [feedback.reason, expected]
