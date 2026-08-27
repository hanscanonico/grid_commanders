class_name AllySurvivesObjective
extends MissionObjective
## This army must still be in the match — "keep the marshal alive".
##
## The objective a mission needs when victory belongs to a *side* but the story
## belongs to one army inside it: `GameState.winners()` lists survivors only, so
## a side can win with an ally already fallen, and without this an escort
## premise has no way to say what it is about.
##
## Asks `GameState.is_eliminated`, the modelled state, and never infers a fallen
## army from an empty unit list — an army that has not built yet has not fallen.

@export var team: int = 2


func is_met(state: GameState, _player_team: int, _progress: MissionProgress) -> bool:
	return not state.is_eliminated(team)


func definition_error(map: MapData, _player_team: int, _unit_db: UnitDB) -> String:
	return MissionBoardCheck.unseated_team(map, team, "ally-survives objective names")
