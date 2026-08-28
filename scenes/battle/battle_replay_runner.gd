class_name BattleReplayRunner
extends RefCounted
## Plays a recorded match back: take the next recorded command, animate it, check
## the board is the one the recording describes, repeat.
##
## `BattleAiRunner`'s sibling, with the planner swapped for a cursor into a file.
## Everything else is deliberately the same — the same `Battle.execute_command`,
## the same `conclude_command`, the same `TurnBeat` pacing, the same
## `Battle.pause_gate` between commands — so a replay animates exactly as the
## match did, cut-ins, banners, ambush cues and eliminations included. That is the
## whole reason playback lives in the battle scene rather than in a viewer of its
## own (plan D4).
##
## Nothing here decides anything. It does not plan, it does not re-validate, and
## it never touches the sim: a command the recording names is rebuilt against the
## live board and handed to the one executor, which is the same route a player's
## click takes.

var _battle: Battle
var _replay: ReplayPlayer


func _init(battle: Battle, replay: ReplayPlayer) -> void:
	_battle = battle
	_replay = replay


## Plays until the turn changes, the recording runs out, or the board stops
## matching it. Re-entered per turn by `Battle._begin_turn`, exactly as the AI
## runner is.
func run() -> void:
	await _battle.pause_gate()
	await TurnBeat.opening(_battle.get_tree())
	while true:
		if _battle.game.winner != 0:
			_battle.enter_victory()
			return
		var command := _replay.next_command(_battle.game)
		if command == null:
			await _finish("Recording ends here")
			return
		var receipt := await _battle.execute_command(command, true)
		if receipt.rejected():
			# The recording says this was legal and this build says it is not, which is
			# the same divergence the checkpoint catches one command later — caught here
			# first because a refused command never reaches the board to be digested.
			# Said out loud for the same reason the drift is: a replay that quietly
			# stopped short would look exactly like one that ended.
			push_error(
				"replay: command %d refused — %s" % [_replay.played(), receipt.validation_error]
			)
			await _finish("Replay stopped — %s" % receipt.validation_error)
			return
		await _battle.conclude_command(receipt)
		var drift := _replay.drift(_battle.game)
		if drift != "":
			push_error("replay: %s" % drift)
			await _finish("Replay stopped — the board no longer matches")
			return
		if receipt.winner != 0 or receipt.turn_changed:
			return  # conclude_command has already opened the next turn, which re-enters
		await TurnBeat.between_commands(_battle.get_tree())
		await _battle.pause_gate()


## Says why the replay stopped and lands on the lockup. A recording that ran to a
## decision shows that decision; one that stops early shows a draw on the day it
## reached, which is what a watched match hitting the day cap already shows.
func _finish(reason: String) -> void:
	if _battle.game.winner == 0:
		await _battle.present_banner(reason)
	_battle.enter_victory()
