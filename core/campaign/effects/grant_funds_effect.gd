class_name GrantFundsEffect
extends MissionEffect
## Moves funds into an army's purse — a subsidy arrives, a convoy gets through,
## a levy is taken.
##
## A negative amount is a levy and is floored at nothing: a purse has never been
## able to go below zero, which is the rule `ChargeLedger`'s kill bounty already
## steals under.

@export var team: int = 1
@export var amount: int = 1000


func apply(state: GameState, _team: int) -> void:
	state.funds[team] = maxi(0, state.funds[team] + amount)


func named_teams() -> Array[int]:
	var named: Array[int] = [team]
	return named


func board_error(state: GameState, _team: int) -> String:
	return MissionBoardCheck.absent_team(state, team, "funds are granted to")


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	var seat_error := MissionBoardCheck.unseated_team(map, team, "funds are granted to")
	if seat_error != "":
		return seat_error
	if amount == 0:
		return "funds grant moves nothing"
	return ""
