class_name MissionEventCommand
extends Command
## Applies one scripted mission event to the board.
##
## Deliberately just another command (campaign-depth D1, which is the
## more-commanders plan's D2 applied verbatim): it validates and applies like
## Move or Attack, so a scripted beat lands in the same command log — the save,
## the replay and the AI's world pick it up with no special case. The campaign
## layer issues it at the one live broker and never writes the board itself.

var event: MissionEvent
## The mission's player team — the seat its effects are authored from.
var team: int

## Populated by apply(): what the effects said about the *mission* rather than
## the board. A command is handed a board and nothing else, so the effects whose
## payload is mission bookkeeping declare it here, and the campaign layer — the
## one writer of the tally, the verdict and the ledger — acts on it at the same
## boundary.
var revealed: Array[StringName] = []
var ending: EndMissionEffect
var written: Array[SetFlagEffect] = []


func _init(p_event: MissionEvent, p_team: int) -> void:
	event = p_event
	team = p_team


## An event belongs to the mission rather than to an army, so there is no "not
## this team's turn" here: a beat comes due at a command boundary whoever is
## playing, and reinforcements that could only land on their owner's turn are
## reinforcements a mission cannot script.
##
## What is refused is what no board could carry: a match already decided — the
## effects of one event can end it, and the next must not land units on a board
## nobody is playing — an event with nothing to apply, and whatever each effect
## says would corrupt the board it is looking at.
func validate(state: GameState) -> String:
	if state.winner != 0:
		return "the match is over"
	if event == null:
		return "no event to fire"
	if event.effects.is_empty():
		return "event '%s' does nothing" % event.id
	for effect: MissionEffect in event.effects:
		if effect == null:
			return "event '%s' holds an empty effect slot" % event.id
		var error := effect.board_error(state, team)
		if error != "":
			return "event '%s': %s" % [event.id, error]
	return ""


func apply(state: GameState) -> void:
	for effect: MissionEffect in event.effects:
		effect.apply(state, team)
		var objective := effect.revealed_objective()
		if objective != &"":
			revealed.append(objective)
		var declared := effect.mission_end()
		if declared != null:
			ending = declared
		var fact := effect.written_flag()
		if fact != null:
			written.append(fact)
