class_name BattleCommandPipeline
extends RefCounted
## The live scene's single committed-command executor.
##
## It validates, captures presentation references, applies exactly once, replays
## the command's result snapshots, and brings the view back in step. Selection,
## input-state transitions, AI planning, pacing, saves, and headless matches stay
## with their existing owners.

var _battle: Battle
## The match's recording, or null when there is nothing to record. It lives here
## because this is where a command is applied, and a recorder must see exactly the
## commands that reached the board — no more (a refused plan returns above) and no
## fewer. It observes and nothing else: replay plan D2, the same rule the Balance
## Lab's telemetry holds to.
var _recorder: ReplayRecorder


func _init(battle: Battle, recorder: ReplayRecorder = null) -> void:
	_battle = battle
	_recorder = recorder


## Executes one command. Human movement is already previewed on the board;
## computer movement asks this seam to animate only the cells the sim actually
## walked, and only when the viewer may watch them.
func execute(command: Command, animate_path: bool = false) -> BattleCommandReceipt:
	var receipt := BattleCommandReceipt.new(command)
	var game := _battle.game
	receipt.team_before = game.current_team
	receipt.day_before = game.day
	receipt.validation_error = command.validate(game)
	if receipt.rejected():
		return receipt
	var standing_before := game.eliminated.size()

	# A command may remove any of these objects. Hold the exact instances the
	# animator must replay before the sim mutates its collections.
	var mover := _mover(command)
	var planned_path := _path(command)
	var attack_target: Unit
	var join_target: Unit
	var drop_passenger: Unit
	if command is AttackCommand:
		attack_target = game.unit_at((command as AttackCommand).target_cell)
	elif command is JoinCommand:
		join_target = game.unit_at(_destination(planned_path))
	elif command is DropCommand:
		var drop := command as DropCommand
		drop_passenger = drop.passenger
		if drop_passenger == null:
			drop_passenger = game.cargo_of(drop.unit)[0]

	var watched_build := false
	if animate_path and command is BuildCommand:
		var build := command as BuildCommand
		var build_cells: Array[Vector2i] = [build.cell]
		watched_build = _can_watch(null, build_cells)
		if watched_build:
			_battle.set_cursor_cell(build.cell)

	if _recorder != null:
		_recorder.before_apply(game, command)
	command.apply(game)
	if _recorder != null:
		_recorder.after_apply(game)
	receipt.applied = true
	receipt.ambushed = command.ambushed
	receipt.team_after = game.current_team
	receipt.day_after = game.day
	receipt.turn_changed = (
		receipt.team_after != receipt.team_before or receipt.day_after != receipt.day_before
	)
	receipt.winner = game.winner

	if mover != null:
		EventBus.unit_moved.emit(mover)

	var watched_move := not animate_path
	if animate_path and mover != null:
		watched_move = await _walk_move(mover, _walked_path(mover, planned_path))
	receipt.watched = watched_move or watched_build

	if command is AttackCommand:
		await _present_attack(command as AttackCommand, attack_target, watched_move, animate_path)
	elif command is CaptureCommand:
		await _present_capture(command as CaptureCommand, watched_move, animate_path)
	elif command is JoinCommand:
		await _present_join(command as JoinCommand, join_target, watched_move)
	elif command is PowerCommand:
		await _present_power(command as PowerCommand)
	elif command is BuildCommand:
		_present_build(command as BuildCommand)
	elif command is DropCommand:
		await _present_move(command, mover, watched_move)
		if drop_passenger != null:
			_battle.view.refresh_sprite(drop_passenger)
	elif mover != null:
		await _present_move(command, mover, watched_move)

	# Combat, powers, joins, supply, transport changes, and turn-start upkeep can
	# all touch more sprites than the acting unit names. One final reconciliation
	# covers every family, including cargo removed with a transport.
	_battle.view.sync_sprites()
	_battle.refresh_fog()
	if game.eliminated.size() > standing_before:
		_repaint_properties(game)
		receipt.fallen = _fallen_since(game, standing_before)
	_battle.refresh_panel()
	_battle.refresh_hud()
	return receipt


## The armies that fell during this command, in the order they fell. `eliminated`
## keys are in insertion order, so the tail past the count taken before the
## command is exactly what it felled — and a command can fell more than one, when
## the last survivor of a side goes down with the shot that decides the match.
static func _fallen_since(game: GameState, standing_before: int) -> Array[int]:
	var fallen: Array[int] = []
	var seen := 0
	for team: int in game.eliminated:
		seen += 1
		if seen > standing_before:
			fallen.append(team)
	return fallen


## An army falling forfeits every property it held to neutral at once, which no
## single-cell repaint covers: `_present_capture` recolours the one cell that was
## captured, and the fog pass only repaints when fog is on. Without this the board
## keeps painting a dead army's cities in its colour — and the tile card, which
## reads the colour back off the tile, keeps naming it as the owner.
##
## After the fog refresh, so each cell is offered to the viewer's current vision:
## `repaint_property` withholds a cell the viewer cannot see, and the fog pass
## lands it the moment they scout it.
func _repaint_properties(game: GameState) -> void:
	for cell: Vector2i in game.property_owners:
		_battle.view.repaint_property(cell)


func _present_attack(
	command: AttackCommand, target: Unit, watched: bool, animate_path: bool
) -> void:
	if command.ambushed:
		await _settle_move(command, command.unit, watched)
		return
	if animate_path and (watched or _battle.perspective.can_see_cell(command.target_cell)):
		_battle.set_cursor_cell(command.target_cell)
	await _battle.animator.animate_combat(command.result, command.unit, target)


func _present_capture(command: CaptureCommand, watched: bool, animate_path: bool) -> void:
	var dest := _destination(command.path)
	if not animate_path:
		_battle.set_cursor_cell(dest)
	await _battle.animator.animate_capture(command.result, command.unit, dest)
	if command.result != null and command.result.captured:
		EventBus.property_captured.emit(dest, command.unit.team)
		_battle.view.repaint_property(dest)
	await _settle_move(command, command.unit, watched)


func _present_join(command: JoinCommand, target: Unit, watched: bool) -> void:
	if watched:
		await _battle.animator.animate_join(command, command.unit, target)
	else:
		_battle.view.refresh_sprite(command.unit)


func _present_power(command: PowerCommand) -> void:
	Sfx.play(&"fanfare")
	await _battle.animator.show_power_banner(command.commander, command.team)


func _present_build(command: BuildCommand) -> void:
	_battle.action_feedback.mark_built(command.built_unit)
	_battle.view.spawn_sprite_for(command.built_unit)
	EventBus.unit_built.emit(command.built_unit)


func _present_move(command: Command, unit: Unit, watched: bool) -> void:
	await _settle_move(command, unit, watched)


## A watched move gets the shared ambush cue; a fogged move is reconciled in
## silence so neither the banner nor a cursor pan reveals it.
func _settle_move(command: Command, unit: Unit, watched: bool) -> void:
	if watched:
		await _battle.animator.settle_move(command, unit)
	else:
		_battle.view.refresh_sprite(unit)


func _walk_move(unit: Unit, walked: Array[Vector2i]) -> bool:
	if not _can_watch(unit, walked):
		return false
	_battle.set_cursor_cell(walked[walked.size() - 1])
	await _battle.animator.animate_path(_battle.view.sprite_for(unit), walked)
	return true


func _can_watch(unit: Unit, cells: Array[Vector2i]) -> bool:
	if unit != null and _battle.perspective.can_see_unit(unit):
		return true
	for cell in cells:
		if _battle.perspective.can_see_cell(cell):
			return true
	return false


## Slice the plan at the cell where apply left the mover. A hidden blocker may
## have stopped it early, and presentation must never walk the cells it did not.
func _walked_path(unit: Unit, planned: Array[Vector2i]) -> Array[Vector2i]:
	var walked: Array[Vector2i] = []
	for cell in planned:
		walked.append(cell)
		if cell == unit.cell:
			break
	return walked


func _mover(command: Command) -> Unit:
	if command is AttackCommand:
		return (command as AttackCommand).unit
	if command is CaptureCommand:
		return (command as CaptureCommand).unit
	if command is DiveCommand:
		return (command as DiveCommand).unit
	if command is DropCommand:
		return (command as DropCommand).unit
	if command is JoinCommand:
		return (command as JoinCommand).unit
	if command is LoadCommand:
		return (command as LoadCommand).unit
	if command is MoveCommand:
		return (command as MoveCommand).unit
	if command is SupplyCommand:
		return (command as SupplyCommand).unit
	return null


func _path(command: Command) -> Array[Vector2i]:
	if command is AttackCommand:
		return (command as AttackCommand).path
	if command is CaptureCommand:
		return (command as CaptureCommand).path
	if command is DiveCommand:
		return (command as DiveCommand).path
	if command is DropCommand:
		return (command as DropCommand).path
	if command is JoinCommand:
		return (command as JoinCommand).path
	if command is LoadCommand:
		return (command as LoadCommand).path
	if command is MoveCommand:
		return (command as MoveCommand).path
	if command is SupplyCommand:
		return (command as SupplyCommand).path
	var empty: Array[Vector2i] = []
	return empty


func _destination(path: Array[Vector2i]) -> Vector2i:
	return path[path.size() - 1]
