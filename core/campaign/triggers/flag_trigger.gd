class_name FlagTrigger
extends MissionTrigger
## The consequence ledger reads a certain way — the one condition in the
## vocabulary that reaches outside the board it is asked about, and so the one
## that lets a beat depend on how an earlier mission went.
##
## It reads the war as it stood when this mission began, because that is when the
## ledger last moved: a `SetFlag` fired inside a mission is staged and taken by
## `CampaignState.complete`. So a gated beat cannot fire differently depending on
## what has already happened this afternoon, and a board that opens on a flag
## opens the same way every time the mission is played.
##
## The band is `FlagCondition`'s, floor and ceiling both, because a war that can
## only record what went wrong is a war that can only get worse.

@export var condition: FlagCondition


func is_met(
	_state: GameState, _team: int, _progress: MissionProgress, ledger: CampaignState = null
) -> bool:
	return condition != null and condition.holds(ledger)


func read_condition() -> FlagCondition:
	return condition


func definition_error(_map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if condition == null:
		return "flag trigger reads nothing"
	return condition.definition_error()
