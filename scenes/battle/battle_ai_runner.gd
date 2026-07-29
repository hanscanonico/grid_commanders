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
	# Battle awaits the day banner itself before handing the turn over, so this is
	# only the pacing padding that follows it, not a wait for the banner.
	var start_delay := Settings.speed.start_delay_seconds()
	await _battle.get_tree().create_timer(start_delay).timeout
	for i in MAX_COMMANDS_PER_TURN:
		if game.winner != 0:
			_leave()
			return
		# Asked per command, not cached for the turn: an EndTurnCommand hands play
		# to the other side mid-loop, and in watch mode that side has a planner of
		# its own.
		var command := _battle.planner_for(game.current_team).plan_next_command(game)
		var receipt := await _execute(command)
		if receipt == null:
			return
		if receipt.winner != 0 or receipt.turn_changed:
			return
		await _think()
	push_error("AI hit the per-turn command cap; forcing end of turn")
	await _execute(EndTurnCommand.new())


## The think-beat between two commands, so the turn reads as decisions rather
## than a slideshow. Paced off Settings, the same tier the animations it sits
## between run at — a computer turn and a player's move obey one setting.
##
## Instant drops the wait to a single frame rather than to nothing: the board
## still repaints once per command, so a forty-command turn is forty frames the
## eye can track as a fast flicker, the window keeps pumping events, and the
## per-turn safety cap above keeps meaning what it says.
func _think() -> void:
	var delay := Settings.speed.command_delay_seconds()
	if delay <= 0.0:
		await _battle.get_tree().process_frame
		return
	await _battle.get_tree().create_timer(delay).timeout


## Every bail-out from the loop lands here, so a planner bug can never leave the
## scene stuck in AI_TURN with all input blocked and no banner.
func _leave() -> void:
	if _battle.game.winner != 0:
		_battle.enter_victory()
	else:
		_battle.state = Battle.State.IDLE


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
