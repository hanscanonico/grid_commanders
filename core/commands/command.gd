class_name Command
extends RefCounted
## Base class for all simulation actions (move, attack, capture, build, ...).
## Commands are validated against a GameState, then applied to mutate it.
## The AI issues the exact same commands as the player.

## Set by apply() on the move-family commands when a hidden enemy on the path
## sprang an ambush: the move was cut short of its destination and whatever it was
## bound to (an attack, a capture, a load, …) was dropped. The presentation layer
## reads it to play the trap cue; plain non-moving commands leave it false.
var ambushed: bool = false


## The refusal every command shares: nothing may be issued once the match has a
## winner. One statement of it, so the wording cannot drift between families.
static func decided_error(state: GameState) -> String:
	if state.winner != 0:
		return "the match is over"
	return ""


## The refusal every command an army issues shares. Decided first: a finished
## match is not the current team's fault to be told about.
static func turn_error(state: GameState, team: int) -> String:
	var decided := decided_error(state)
	if decided != "":
		return decided
	if team != state.current_team:
		return "not this team's turn"
	return ""


## Returns "" when the command is legal, otherwise a human-readable reason.
func validate(_state: GameState) -> String:
	return "not implemented"


## Mutates the state. Only call after validate() returned "".
func apply(_state: GameState) -> void:
	push_error("Command.apply not implemented")
