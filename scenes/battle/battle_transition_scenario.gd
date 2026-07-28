class_name BattleTransitionScenario
extends RefCounted
## Driven acceptance flows for the state-boundary input convention (COM-15).
## They use the same public Battle entry points and input events a player does,
## and return a diagnostic rather than owning the smoke run's exit code.

const BUILD_CELL := Vector2i(3, 2)
const LAST_ENEMY_CELL := Vector2i(9, 8)
const ATTACKER_CELL := Vector2i(8, 8)
const OUTCOME_GUARD_SECONDS := 0.55

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


func run(mode: String) -> String:
	match mode:
		"turn_banner_build_attempt":
			return await _run_turn_banner_build_attempt()
		"outcome_mash_guard":
			return await _run_outcome_mash_guard()
	return "unknown transition scenario: %s" % mode


## The opening banner must own the interaction state. The first attempted press
## retires that beat, then the next one may open production on an unobscured board.
func _run_turn_banner_build_attempt() -> String:
	if not _battle.animator.turn_banner.visible:
		return "turn banner retired before the build attempt could exercise it"
	_battle.confirm_at(BUILD_CELL)
	await _battle.get_tree().process_frame
	if _battle.action_menu.visible:
		return "build menu opened underneath the turn banner"
	if not _battle.animator.turn_banner.visible:
		return "build attempt hid the banner without travelling through its skip input"

	await _press_key(KEY_ENTER)
	if not await _wait_for_banner(false):
		return "a press during the turn banner was swallowed instead of skipping it"
	if _battle.state != Battle.State.IDLE:
		return "turn banner retired into state %s instead of IDLE" % _battle.state

	_battle.confirm_at(BUILD_CELL)
	await _until_state(Battle.State.MENU)
	if _battle.animator.turn_banner.visible:
		return "build menu opened before the skipped turn banner cleared"
	return ""


## Wins through the real attack flow, then sends the buffered confirm that used
## to land on an already-focused Rematch. It must neither focus nor activate
## anything during the guard; after the guard, one fresh press only highlights.
func _run_outcome_mash_guard() -> String:
	await _stage_victory()
	var focused := _battle.get_viewport().gui_get_focus_owner()
	if focused != null and _battle.victory_screen.is_ancestor_of(focused):
		return "outcome appeared with '%s' already focused" % focused.name
	if _battle.rematch_button.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return "outcome buttons accepted pointer input during the mash guard"

	var scene := _battle.get_tree().current_scene
	# A button's pressed signal is the last seam before rematch. Even if a
	# buffered click focused it first, the guarded callback must release it.
	_battle.rematch_button.grab_focus()
	_battle.rematch_button.pressed.emit()
	await _press_key(KEY_ENTER)
	await _battle.get_tree().process_frame
	if _battle.get_tree().current_scene != scene:
		return "buffered outcome press restarted or left the match"
	focused = _battle.get_viewport().gui_get_focus_owner()
	if focused != null and _battle.victory_screen.is_ancestor_of(focused):
		return "buffered outcome press focused '%s' during the guard" % focused.name

	await _battle.get_tree().create_timer(OUTCOME_GUARD_SECONDS).timeout
	if _battle.rematch_button.mouse_filter != Control.MOUSE_FILTER_STOP:
		return "outcome buttons stayed pointer-locked after the mash guard"
	await _press_key(KEY_ENTER)
	await _battle.get_tree().process_frame
	if _battle.get_tree().current_scene != scene:
		return "the first accepted outcome press activated an action"
	focused = _battle.get_viewport().gui_get_focus_owner()
	if focused == null or not _battle.victory_screen.is_ancestor_of(focused):
		return "the first accepted outcome press did not highlight an action"
	return ""


func _stage_victory() -> void:
	for unit in _battle.game.units.duplicate():
		if unit.team == 2 and unit.cell != LAST_ENEMY_CELL:
			_battle.game.remove_unit(unit)
	_battle.view.sync_sprites()
	var last_enemy := _battle.game.unit_at(LAST_ENEMY_CELL)
	last_enemy.hp = 1
	_battle.view.refresh_sprite(last_enemy)
	_battle.confirm_at(ATTACKER_CELL)
	_battle.confirm_at(ATTACKER_CELL)
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"fire")
	await _until_state(Battle.State.TARGETING)
	_battle.confirm_at(_battle.cursor_cell)
	await _until_state(Battle.State.VICTORY)


func _press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _battle.get_tree().process_frame


func _wait_for_banner(visible: bool) -> bool:
	for frame in 120:
		if _battle.animator.turn_banner.visible == visible:
			return true
		await _battle.get_tree().process_frame
	return false


func _until_state(wanted: Battle.State) -> void:
	while _battle.state != wanted:
		await _battle.get_tree().process_frame
