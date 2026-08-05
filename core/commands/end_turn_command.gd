class_name EndTurnCommand
extends Command
## Hands the turn to the next team; the day advances when the rotation wraps
## back past the last seat. Start-of-turn effects run for the new team.


func validate(state: GameState) -> String:
	if state.winner != 0:
		return "the match is over"
	return ""


func apply(state: GameState) -> void:
	# An OWNER_TURN Command Power lasts exactly the turn it was fired on, so it
	# comes down as that turn ends. A ROUND power survives this and expires at its
	# owner's next turn start instead — the other call to the same rule, in
	# TurnRules.begin_turn.
	TurnRules.expire_power(state, state.current_team, CommanderType.Duration.OWNER_TURN)
	var next := state.next_team()
	# The day turns when the hand rolls back past the last seat, measured on the
	# board's full roster rather than on whoever is left. Asking whether the hand
	# reached the first *survivor* instead would turn the day early the round an
	# army falls: the seat after the fallen one is both the next hand and the new
	# lead, so the survivors would play the rest of that round on a fresh day.
	if state.teams.find(next) <= state.teams.find(state.current_team):
		state.day += 1
	state.current_team = next
	TurnRules.begin_turn(state)
