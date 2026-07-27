extends Node
## Carries one MatchRequest from whoever chose the match into the battle scene,
## and nothing else.
##
## It used to be the match setup itself — six mutable fields with three writers
## and no reset, which `BattleSetup.build` read, merged with the command line and
## a save, and then wrote back to (architecture finding A3). That is what made a
## latched `load_save` possible: a resume that found no save file on disk left
## the flag set for the rest of the process, and the next battle boot silently
## tried to resume again.
##
## Now it holds one typed request and hands it over exactly once. `take()`
## clearing is the whole design: a request cannot outlive the scene transition it
## was staged for, so there is no stale field left for the next boot to read.

var _request: MatchRequest = null


## Stages the match the next battle scene will play. Called by the main menu on
## start and by BattleExit on rematch — the two moments something decides which
## match comes next.
func stage(request: MatchRequest) -> void:
	_request = request


## The staged request, consumed. Null when nothing staged one, which is the
## normal case for a run that boots `battle.tscn` directly: a `make smoke`
## scenario, a capture, or a watched Balance Lab row. Those play the defaults
## plus whatever their own flags say.
func take() -> MatchRequest:
	var request := _request
	_request = null
	return request
