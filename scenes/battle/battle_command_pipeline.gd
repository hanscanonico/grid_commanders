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
	var acting_funds_before := int(game.funds.get(receipt.team_before, 0))

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

	# The board a fired power is about to change, and the square an aimed one
	# names. Both are read before apply for the reason the combatants above are:
	# afterwards the units the power removed are already off the board.
	var power_before: PowerEffects.Snapshot
	var blast: Array[Vector2i] = []
	if command is PowerCommand:
		power_before = PowerEffects.snapshot(game)
		blast = _blast_cells(game, command as PowerCommand)

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
	var bounty_delta := 0
	if command is AttackCommand:
		bounty_delta = int(game.funds.get(receipt.team_before, 0)) - acting_funds_before

	if mover != null:
		EventBus.unit_moved.emit(mover)

	var watched_move := not animate_path
	if animate_path and mover != null:
		watched_move = await _walk_move(mover, _walked_path(mover, planned_path))
	receipt.watched = watched_move or watched_build

	if command is AttackCommand:
		await _present_attack(
			command as AttackCommand, attack_target, watched_move, animate_path, bounty_delta
		)
	elif command is CaptureCommand:
		await _present_capture(command as CaptureCommand, watched_move, animate_path)
	elif command is JoinCommand:
		await _present_join(command as JoinCommand, join_target, watched_move)
	elif command is PowerCommand:
		await _present_power(command as PowerCommand, power_before, blast)
	elif command is BuildCommand:
		_present_build(command as BuildCommand)
	elif command is MissionEventCommand:
		await _present_mission_event(command as MissionEventCommand)
	elif command is DropCommand:
		await _present_move(command, mover, watched_move)
		if drop_passenger != null:
			_battle.view.refresh_sprite(drop_passenger)
		_present_blocked_drop(command as DropCommand, watched_move)
	elif mover != null:
		await _present_move(command, mover, watched_move)

	# Combat, powers, joins, supply, transport changes, and turn-start upkeep can
	# all touch more sprites than the acting unit names. One final reconciliation
	# covers every family, including cargo removed with a transport.
	_battle.view.sync_sprites(_parting_fade(command))
	_battle.refresh_fog()
	if game.eliminated.size() > standing_before:
		receipt.fallen = _fallen_since(game, standing_before)
	# A scripted beat can hand any square to anybody, which is the same repaint an
	# army falling needs and for the same reason: neither is the one cell the
	# capture path recolours.
	if not receipt.fallen.is_empty() or command is MissionEventCommand:
		_repaint_properties(game)
	_battle.refresh_panel()
	_battle.refresh_hud()
	# Last, so the banner stands over a board already back in step, and after the
	# fog pass, whose eyes are the incoming team's rather than the outgoing one's.
	if command is EndTurnCommand:
		await _announce_starved(command as EndTurnCommand)
	return receipt


## A turn-start starvation is the one death this reconciliation is the *first* to
## show: nothing animated the plane going down, so the sprites it frees get the
## parting fade every other death already played for itself.
func _parting_fade(command: Command) -> float:
	if command is EndTurnCommand and not (command as EndTurnCommand).starved.is_empty():
		return Settings.speed.death_fade_seconds()
	return 0.0


## Says out loud what the turn's opening took for an empty tank — losing a bomber
## is too expensive to read as a sprite that was simply never there. The same
## blocking beat an army leaving the match gets, suppressed while capturing for
## the same reason, and only over losses this viewer could have watched.
func _announce_starved(command: EndTurnCommand) -> void:
	if _battle.animator.capturing:
		return
	var seen: Array[Unit] = []
	for unit in command.starved:
		if _battle.perspective.can_see_cell(unit.cell):
			seen.append(unit)
	if seen.is_empty():
		return
	var what := seen[0].type.display_name if seen.size() == 1 else "%d units" % seen.size()
	await _battle.animator.show_banner("%s lost - out of fuel" % what)


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
	command: AttackCommand, target: Unit, watched: bool, animate_path: bool, bounty_delta: int
) -> void:
	if command.ambushed:
		await _settle_move(command, command.unit, watched)
		return
	if animate_path and (watched or _battle.perspective.can_see_cell(command.target_cell)):
		_battle.set_cursor_cell(command.target_cell)
	await _battle.animator.animate_combat(command.result, command.unit, target)
	if bounty_delta != 0 and (watched or _battle.perspective.can_see_cell(command.target_cell)):
		var sign := "+" if bounty_delta > 0 else "-"
		_battle.action_feedback.show_reason(
			"Bounty %s%d" % [sign, absi(bounty_delta)],
			_battle.view.board_camera.screen_pos_for_cell(command.target_cell)
		)


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


func _present_power(
	command: PowerCommand, before: PowerEffects.Snapshot, blast: Array[Vector2i]
) -> void:
	Sfx.play(&"fanfare")
	await _battle.animator.show_power_banner(command.commander, command.team)
	await _battle.animator.show_power_effects(_visible_marks(before, blast), blast)


## The square an aimed power names, asked of the doctrine that owns the footprint
## (plan D3) — the same call the aim preview and the strike itself make, so the
## marks cannot paint a shape the power did not take. Empty for every power that
## fires at the board rather than at a cell.
func _blast_cells(game: GameState, command: PowerCommand) -> Array[Vector2i]:
	var team := game.current_team
	return game.commander_of(team).power_blast_cells(game, team, command.target)


## What the power did, minus what the viewer has no business knowing: a mark over
## a unit they cannot see would report a fogged army's health, and a mark on
## unscouted ground would report an aim into the dark. The same gate every other
## on-board caption obeys.
func _visible_marks(
	before: PowerEffects.Snapshot, blast: Array[Vector2i]
) -> Array[PowerEffects.Mark]:
	var shown: Array[PowerEffects.Mark] = []
	for mark in PowerEffects.marks(before, _battle.game, blast):
		var seen := (
			_battle.perspective.can_see_unit(mark.unit)
			if mark.unit != null
			else _battle.perspective.can_see_cell(mark.cell)
		)
		if seen:
			shown.append(mark)
	return shown


## What a scripted beat says as it lands. Here rather than in the campaign layer
## because it is the *command's* presentation, exactly as the activation card is
## a fired power's — which is also what lets a replay speak the same words, the
## recording re-issuing the beat through this same seam.
func _present_mission_event(command: MissionEventCommand) -> void:
	await _battle.animator.speak_lines(command.event.lines, _battle.commander_db)


func _present_build(command: BuildCommand) -> void:
	_battle.action_feedback.mark_built(command.built_unit)
	_battle.view.spawn_sprite_for(command.built_unit)
	_battle.animator.animate_build(_battle.view.sprite_for(command.built_unit))
	EventBus.unit_built.emit(command.built_unit)


## The transport arrived and the passenger stayed aboard, because the drop cell
## turned out occupied. That is not the ambush cue `_settle_move` plays — nothing
## was cut short — so it gets the ordinary rejected-action reason instead, under
## the same visibility gate every other on-board caption obeys.
func _present_blocked_drop(command: DropCommand, watched: bool) -> void:
	if not command.drop_blocked:
		return
	if not (watched or _battle.perspective.can_see_cell(command.drop_cell)):
		return
	_battle.action_feedback.show_reason(
		"Drop blocked", _battle.view.board_camera.screen_pos_for_cell(command.drop_cell)
	)


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
