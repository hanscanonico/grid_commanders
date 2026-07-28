class_name BattleFeedbackScenario
extends RefCounted
## Driven feedback acceptance flows, split out so BattleScenarioDriver stays
## under its linted size cap. Every flow — `run` included — returns an error
## string rather than reporting one: the driver's `_fail` owns the push_error
## and the exit-code flag together, and the two are not separable.

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


func run(mode: String) -> String:
	match mode:
		"rejected_confirm":
			return await _run_rejected_confirms()
		"enemy_range_preview":
			return await _run_enemy_range_preview()
		"end_turn_ready_units":
			return await _run_end_turn_ready_units()
	return "unknown feedback scenario: %s" % mode


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

	# Back out the selection the way a player would before handing the turn over:
	# a human selection left live under the CPU-turn chip is a board the game
	# cannot reach, and this mode's frame is photographed exactly there.
	await _press(&"cancel")
	if _battle.state != Battle.State.IDLE:
		return "cancel did not clear the selection before the CPU turn"

	_battle.state = Battle.State.AI_TURN
	_battle.confirm_at(_battle.cursor_cell)
	return _expect_reason(feedback, "CPU turn.")


func _run_enemy_range_preview() -> String:
	_battle.set_cursor_cell(Vector2i(9, 8))
	_battle.confirm_at(Vector2i(9, 8))
	if _battle.state != Battle.State.PREVIEW:
		return "enemy confirm did not enter PREVIEW"
	if _battle.view.move_overlay.get_used_cells().is_empty():
		return "enemy preview painted no movement reach"
	await _press(&"show_range")
	if _battle.view.attack_overlay.get_used_cells().is_empty():
		return "R painted no enemy fire ring"
	return ""


func _run_end_turn_ready_units() -> String:
	# Hot-seat makes the no-ready path stop at the handoff instead of immediately
	# letting the AI race through the next side before the scenario can inspect it.
	_battle.ai_teams.clear()
	_battle.view.ai_teams = _battle.ai_teams
	var starting_team := _battle.game.current_team

	await _open_end_turn()
	var guard := _guard()
	if guard == null or not guard.visible:
		return "End Turn committed with ready units instead of opening its guard"
	var error := _expect_guard(guard, starting_team)
	if error != "":
		return error
	if not _press_button(guard, "Review units"):
		return "ready-unit guard has no Review units button"
	await _battle.get_tree().process_frame
	if guard.visible or _battle.game.current_team != starting_team:
		return "Review units did not return to the same turn"

	# Spent turns must keep the old zero-friction path. Marking these units acted
	# stages the state a player reaches by using each one; End Turn itself still
	# travels through the live menu and command pipeline.
	for unit in _ready_units(starting_team):
		unit.acted = true
	await _open_end_turn()
	error = await _wait_for_team_change(starting_team)
	if error != "":
		return error
	if guard.visible:
		return "End Turn showed the ready-unit guard with no ready units"

	if _battle.state == Battle.State.HANDOFF:
		_battle.leave_handoff()
	# A player may open the menu once the incoming banner has retired. The
	# capture skips that presentation wait, just as the driver hid day one's
	# banner before this flow began.
	_battle.hide_banner()
	await _battle.get_tree().process_frame
	var next_team := _battle.game.current_team
	await _open_end_turn()
	guard = _guard()
	if guard == null or not guard.visible:
		return "next side's ready units did not reopen the End Turn guard"
	return _expect_guard(guard, next_team)


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
	var ready := _ready_units(team)
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
	return ""


func _ready_units(team: int) -> Array[Unit]:
	var ready: Array[Unit] = []
	for unit in _battle.game.units:
		if unit.team == team and not unit.acted and unit.carrier == null:
			ready.append(unit)
	return ready


func _guard() -> Control:
	return _battle.get_node_or_null("UI/EndTurnGuard") as Control


func _control_text(root: Control) -> String:
	var parts := PackedStringArray()
	for node in root.find_children("*", "", true, false):
		if node is Label:
			parts.append((node as Label).text)
		elif node is Button:
			parts.append((node as Button).text)
	return "\n".join(parts)


func _press_button(root: Control, text: String) -> bool:
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == text:
			button.pressed.emit()
			return true
	return false


## Sends a key the player's own input path, so the flow under test is the one a
## keyboard reaches — not a handler called directly.
func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _battle.get_tree().process_frame


func _expect_reason(feedback: ActionFeedback, expected: String) -> String:
	if feedback.reason == expected:
		return ""
	return "rejected confirm showed '%s', expected '%s'" % [feedback.reason, expected]


func _until_state(wanted: Battle.State) -> void:
	while _battle.state != wanted:
		await _battle.get_tree().process_frame
