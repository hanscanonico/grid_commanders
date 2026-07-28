class_name BattleFeedbackScenario
extends RefCounted
## Driven COM-13 acceptance flows, split out so BattleScenarioDriver stays under
## its linted size cap. The individual flows return an error string rather than
## owning the harness's failure state.

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


func run(mode: String) -> bool:
	var error := (
		await _run_rejected_confirms()
		if mode == "rejected_confirm"
		else await _run_enemy_range_preview()
	)
	if error == "":
		return true
	push_error(error)
	return false


func _run_rejected_confirms() -> String:
	var feedback := _battle.get_node_or_null("UI/ActionFeedback") as ActionFeedback
	if feedback == null:
		return "rejected confirms have no ActionFeedback surface"

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
	var event := InputEventAction.new()
	event.action = &"show_range"
	event.pressed = true
	Input.parse_input_event(event)
	await _battle.get_tree().process_frame
	if _battle.view.attack_overlay.get_used_cells().is_empty():
		return "R painted no enemy fire ring"
	return ""


func _expect_reason(feedback: ActionFeedback, expected: String) -> String:
	if feedback.reason == expected:
		return ""
	return "rejected confirm showed '%s', expected '%s'" % [feedback.reason, expected]


func _until_state(wanted: Battle.State) -> void:
	while _battle.state != wanted:
		await _battle.get_tree().process_frame
