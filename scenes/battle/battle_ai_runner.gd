class_name BattleAiRunner
extends RefCounted
## Plays a full computer turn: plan one command, animate it, repeat until the AI
## ends its turn or the per-turn safety cap trips.
##
## Split out of Battle the same way BattleView, BattleAnimator and
## BattleScenarioDriver were — it is the AI's side of the interaction flow, and
## like the scenario driver it drives Battle's own entry points (the same
## animations, the same turn hand-off, the same victory check) rather than
## reaching past them, so an AI turn resolves and animates exactly as a player's
## does. Battle holds one of these for the whole scene and calls `run()` when a
## computer team's turn opens.
##
## It is also where a computer turn can be paused: `Battle.pause_gate` is awaited
## between commands, so the player's Esc is honoured at a boundary where the board
## has settled rather than in the middle of one — see the two call sites. The keys
## that reach a turn nobody may play are `handle_input`'s, for the same reason.

## Safety net: a planner bug can never hang the match, only force a turn to end.
## Read from the harness rather than declared here, because the headless engine
## applies the identical cut (balance plan D7) — if the two drifted apart, a
## watched match could be trimmed where its headless row was let run, and the
## replay-fidelity check would fail for a reason that has nothing to do with the
## sim.
const MAX_COMMANDS_PER_TURN := BalanceMatchEngine.MAX_COMMANDS_PER_TURN

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


## Plays the whole AI turn. Fire-and-forget async, like the player flow it
## mirrors: it awaits its own animations and never blocks Battle's frame.
func run() -> void:
	var game := _battle.game
	# A pause asked for during the previous turn's last command is answered before
	# this one spends a frame on itself; see Battle.pause_gate.
	await _battle.pause_gate()
	if _left_auto(game):
		return
	await TurnBeat.opening(_battle.get_tree())
	for i in MAX_COMMANDS_PER_TURN:
		if _battle.match_over():
			_leave()
			return
		if _left_auto(game):
			return
		# Asked per command, not cached for the turn: an EndTurnCommand hands play
		# to the other side mid-loop, and in watch mode that side has a planner of
		# its own.
		var command := _battle.planner_for(game.current_team).plan_next_command(game)
		var receipt := await _execute(command)
		if receipt == null:
			return
		if _battle.match_over() or receipt.turn_changed:
			return
		await TurnBeat.between_commands(_battle.get_tree())
		# The one place a computer turn can be held: between two commands, with the
		# board settled and no banner or cut-in of its own on screen. A watched match
		# would otherwise have no way back to the menu at all, since every turn in it
		# is a computer's.
		await _battle.pause_gate()
	push_error("AI hit the per-turn command cap; forcing end of turn")
	await _execute(EndTurnCommand.new())


## What a key does while the computer plays. The zoom ladder answers first and
## keeps answering: it moves the camera and never a unit, so watching a turn from
## further out is not playing it (COM-267). Esc asks for the board back, and
## anything else refuses play but says so rather than going quiet.
func handle_input(event: InputEvent) -> void:
	if _battle.zoom.handle_input(event):
		return
	if event.is_action_pressed(&"cancel"):
		_battle.request_pause()
	elif TransitionInput.is_confirm(event):
		_battle.confirm_at(_battle.cursor_cell)


## True when the team on turn left `ai_teams` while this pause was held — the
## player took their own Auto-controlled seat back through the pause menu's
## Auto row. Checked at every `pause_gate()` return, board settled either way,
## so the runner never plans a command for a team that just got handed back;
## `state` is left at IDLE (`rest_state()`, `_paused` already cleared by
## whatever called `Battle.resume_turn()` to wake this coroutine).
func _left_auto(game: GameState) -> bool:
	if game.current_team in _battle.ai_teams:
		return false
	_battle.state = _battle.rest_state()
	return true


## Every bail-out from the loop lands here, so a planner bug can never leave the
## scene stuck in AI_TURN with all input blocked and no banner. The match is over
## on Battle's answer, not the board's: a campaign mission decided on its
## objectives has no sim winner to read.
func _leave() -> void:
	if _battle.match_over():
		_battle.enter_victory()
	else:
		_battle.state = _battle.rest_state()


## Routes a planned command through the shared live executor. A rejected plan is
## replaced with EndTurn through that same seam; validation is never re-derived
## here. The receipt is then handed back to Battle for turn/victory flow, while
## this runner keeps ownership of planning and pacing.
##
## `conclude_command` is awaited because it can hold a blocking beat of its own —
## the elimination banner — and the loop above issues the next command on a timer
## rather than off the scene's state. Left fire-and-forget, an elimination that
## ended neither the turn nor the match would let the AI's next EndTurn open a
## second banner over the first, and the two would resolve out of order.
func _execute(command: Command) -> BattleCommandReceipt:
	var receipt := await _battle.execute_command(command, true)
	if receipt.rejected():
		push_error("AI command rejected (%s); ending the AI turn" % receipt.validation_error)
		receipt = await _battle.execute_command(EndTurnCommand.new(), true)
		if receipt.rejected():
			_leave()
			return null
	await _battle.conclude_command(receipt)
	return receipt
