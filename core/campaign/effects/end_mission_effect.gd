class_name EndMissionEffect
extends MissionEffect
## Ends the mission where it stands — the relief column arrives and the retreat
## is over, the ruse is discovered and the raid is blown.
##
## It decides nothing. `MissionRuntime` owns precedence (campaign-depth D3), and
## this is a **fact that runtime reads**: the command collects it, the campaign
## layer hands it to `evaluate`, and it takes its place in the shipped order —
## with the failures if it is one, with the successes if it is not, losing still
## outranking winning throughout. So a scripted victory on the turn the deadline
## expires is still a mission lost.
##
## It changes no board either, which is why `apply` does nothing: a mission ends
## in the campaign layer, and a `Command` is handed a board and nothing else.

## False ends it in defeat. Stated as the good case because a mission's authored
## endings are mostly its wins.
@export var success: bool = true
## The line the debrief prints, in the same voice an objective's `text` is
## written in — it is what the player is told the mission ended on.
@export_multiline var reason: String = ""


func mission_end() -> EndMissionEffect:
	return self


func definition_error(_map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if reason == "":
		return "mission ending says nothing about why"
	return ""
