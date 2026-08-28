class_name BattleTargeting
extends RefCounted
## Aiming and shooting: the Fire row's attack targets and a transport's drop
## squares, from the menu that offers them to the command that spends them.
##
## Split out of Battle the same way BattlePowerFlow, BattleExit, BattleAuto and
## BattleCampaign were: one idea, holding the scene rather than state of its own —
## except for the two target lists, which belong to nothing else. Battle keeps
## State.TARGETING and State.DROP_TARGETING and the input arms that reach them.
##
## The perspective is the one authority on what a viewer may shoot at and unload
## onto; nothing here re-derives either.

var _battle: Battle
## What the commit-and-settle wrapper and the unit menu are reached through.
## Handed over at construction rather than called as public methods, because
## Battle sits at its `max-public-methods` ceiling and neither seam is anybody
## else's to call.
var _run_command: Callable
var _reopen_menu: Callable

var _attack_targets: Array[Vector2i] = []
## Viewer-safe cargo choices for the open unit menu, and the one being targeted.
## Each typed option keeps its passenger and cells together.
var _drop_options: Array[BattlePerspective.DropOption] = []
var _drop_option: BattlePerspective.DropOption


func _init(battle: Battle, run_command: Callable, reopen_menu: Callable) -> void:
	_battle = battle
	_run_command = run_command
	_reopen_menu = reopen_menu


## Reads what a unit that has just arrived can shoot and unload, and answers with
## the menu rows the two lists unlock. One call rather than a fill and two
## questions: the Fire row and the Drop rows *are* what the lists are for, so
## nothing outside needs to see them.
func arm(unit: Unit, path: Array[Vector2i]) -> Array[Dictionary]:
	var dest: Vector2i = path[path.size() - 1]
	_attack_targets = _battle.perspective.attackable_cells(unit, dest, path.size() > 1)
	_drop_options = _battle.perspective.drop_options(unit, dest)
	return BattleMenus.unit_actions(
		_battle.game, unit, path, not _attack_targets.is_empty(), _drop_options
	)


## The Fire row: the cursor lands on the first target rather than where the move
## left it.
func enter_fire() -> void:
	_battle.state = Battle.State.TARGETING
	_battle.overlays.paint_attack(_attack_targets)
	_battle.set_cursor_cell(_attack_targets[0])


## A drop row names one typed option; its passenger and viewer-safe drop cells
## stay paired from menu construction through command creation.
func enter_drop(index: int) -> void:
	_battle.state = Battle.State.DROP_TARGETING
	_drop_option = _drop_options[index]
	_battle.overlays.paint_move(_drop_option.cells)
	_battle.set_cursor_cell(_drop_option.cells[0])


## Backing either aim out to the unit menu, which is reopened rather than
## remembered: the targets are recomputed from the board the unit is standing on.
func exit_to_menu() -> void:
	_battle.overlays.paint_attack([])
	_battle.overlays.paint_move([])
	_battle.view.update_damage_preview(null, _battle.cursor_cell)
	_drop_options = []
	_drop_option = null
	_reopen_menu.call()


## A confirm press in either aiming state. The UI only offers legal drops and
## legal attacks, so each commit's recovery is a bug guard that backs its own
## state out to the menu.
func confirm_at(cell: Vector2i) -> void:
	if _battle.state == Battle.State.TARGETING:
		if cell in _attack_targets:
			_fire_at(cell)
		else:
			_refuse("No target there.", cell)
		return
	if _drop_option != null and cell in _drop_option.cells:
		_drop_at(cell)
	else:
		_refuse("Cannot unload there.", cell)


## Whether a damage forecast applies at all is a flow question — only the
## targeting state, with a real target under the cursor, has one to show.
func refresh_forecast(cell: Vector2i) -> void:
	var target := _battle.game.unit_at(cell)
	if _battle.state != Battle.State.TARGETING or target == null or cell not in _attack_targets:
		_battle.view.update_damage_preview(null, cell)
		return
	var path := _battle.planned_path
	var dest: Vector2i = path[path.size() - 1]
	_battle.view.update_damage_preview(
		CombatResolver.forecast(_battle.game, _battle.selected, dest, target), cell
	)


## Both lists belong to the unit in hand, so putting the board back to rest drops
## them. The paint is clear_selection's, which clears more than this flow's.
func clear() -> void:
	_attack_targets = []
	_drop_options = []
	_drop_option = null


func _fire_at(target_cell: Vector2i) -> void:
	var command := AttackCommand.new(_battle.selected, _battle.planned_path, target_cell)
	_battle.overlays.paint_attack([])
	_battle.view.update_damage_preview(null, _battle.cursor_cell)
	_battle.overlays.trace_path([])
	_run_command.call(command, exit_to_menu)


func _drop_at(drop_cell: Vector2i) -> void:
	var command := DropCommand.new(
		_battle.selected, _battle.planned_path, drop_cell, _drop_option.passenger
	)
	_run_command.call(command, exit_to_menu)


func _refuse(reason: String, cell: Vector2i) -> void:
	_battle.action_feedback.show_reason(reason, _battle.view.board_camera.screen_pos_for_cell(cell))
