class_name DefeatTeamObjective
extends MissionObjective
## One named army must fall — "break Draeg's division", rather than win the
## battle.
##
## The **one** condition in the library that reads a bare team on purpose, where
## every other reads a side. A mission about one marshal is about that marshal's
## army: read side-wide it would keep running with the marshal already gone
## because an ally of theirs is still fighting, which is the opposite of what the
## briefing promised. It is `AllySurvives` the other way round, and asks the same
## modelled `GameState.is_eliminated` rather than an empty unit list — an army
## that has not built yet has not fallen.

@export var team: int = 2


func is_met(state: GameState, _player_team: int, _progress: MissionProgress) -> bool:
	return state.is_eliminated(team)


func definition_error(map: MapData, player_team: int) -> String:
	if team == player_team:
		return "defeat objective names the player's own army %d" % team
	if not map.teams().has(team):
		return "defeat objective names army %d, which this board does not seat" % team
	return ""
