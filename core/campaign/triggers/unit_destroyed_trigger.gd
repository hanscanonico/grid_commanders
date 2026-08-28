class_name UnitDestroyedTrigger
extends MissionTrigger
## A named unit is off the board — the siege gun is silenced, the courier is
## caught, the marshal falls.
##
## The board is the whole answer: a unit that is gone is gone, whoever took it
## and however. The name is `Unit.tag` and it is resolved through
## `MissionObjective.tagged_unit`, the one place a name is resolved, so an event
## and the objective beside it cannot disagree about who a tag means.

@export var tag: StringName = &""


func is_met(
	state: GameState, _team: int, _progress: MissionProgress, _ledger: CampaignState = null
) -> bool:
	return MissionObjective.tagged_unit(state, tag) == null


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	return MissionBoardCheck.named_unit(map, tag, "unit-destroyed trigger names")
