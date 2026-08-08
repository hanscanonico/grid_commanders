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


func board_error(state: GameState, _team: int) -> String:
	if not state.teams.has(team):
		return "funds are granted to army %d, which is not at this table" % team
	return ""


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if not map.teams().has(team):
		return "funds are granted to army %d, which this board does not seat" % team
	if amount == 0:
		return "funds grant moves nothing"
	return ""
