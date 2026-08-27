class_name ForceStrengthTrigger
extends MissionTrigger
## A side is down to — or up to — this many units. The trigger a rout, a
## surrender or a second wave is written on.
##
## Counted across the whole **side** the named army stands with, like every other
## condition here: an alliance that is still fielding an army has not been broken
## because one of its members has. Cargo counts, because a passenger is aboard
## rather than gone; it is lost with the transport it rides.

enum Bound {
	## The side is at or below `count` — it has been worn down to this.
	AT_MOST,
	## The side is at or above `count` — it has built up to this.
	AT_LEAST,
}

## Any one army of the side being counted; the count is that whole side's.
@export var team: int = 2
@export var bound: Bound = Bound.AT_MOST
@export var count: int = 2


func is_met(
	state: GameState, _team: int, _progress: MissionProgress, _ledger: CampaignState = null
) -> bool:
	var strength := 0
	for unit in state.units:
		if state.allied(unit.team, team):
			strength += 1
	return strength <= count if bound == Bound.AT_MOST else strength >= count


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	var seat_error := MissionBoardCheck.unseated_team(map, team, "force-strength trigger names")
	if seat_error != "":
		return seat_error
	if count < 0:
		return "force-strength trigger counts to %d units" % count
	return ""
