class_name ObjectiveMetTrigger
extends MissionTrigger
## A mission condition is satisfied — the bridge to the whole objective library,
## so the trigger vocabulary does not have to spell any of it a second time.
##
## It holds the objective rather than naming one, which is what makes it the
## bridge: author it as a reference to the very sub-resource the mission already
## lists — normally one of its **bonus** objectives — and the event and the star
## can never drift apart. A mission's own **primary** is near-useless here,
## because satisfying it ends the mission and an event keyed to it would never
## get to play; a bonus, a would-be failure, or a condition the mission lists
## nowhere at all are all reachable and all evaluate the same way, an objective
## being a pure read of the board (D2).
##
## **It reads a tally-backed objective one boundary stale, so never watch one.**
## `HoldCell` and `LossLimit` are counted by `MissionProgress`, and the tally is
## advanced inside `CampaignSession.decide` — which runs *after* this boundary's
## beats have already been offered and fired. A beat watching either of them
## therefore sees the count as of the previous command and comes due a boundary
## late at best, which on a mission that ends on the same board is never. Key such
## a beat to something the board itself answers.

@export var objective: MissionObjective


func is_met(
	state: GameState, team: int, progress: MissionProgress, _ledger: CampaignState = null
) -> bool:
	return objective != null and objective.is_met(state, team, progress)


func definition_error(map: MapData, team: int, unit_db: UnitDB) -> String:
	if objective == null:
		return "objective-met trigger watches nothing"
	var error := objective.definition_error(map, team, unit_db)
	if error != "":
		return "objective-met trigger watches an impossible condition: %s" % error
	return ""
