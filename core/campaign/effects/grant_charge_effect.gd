class_name GrantChargeEffect
extends MissionEffect
## Banks Command Power charge for an army — the general is handed the moment.
##
## Through `GameState.add_charge`, which is the meter's one authority: it caps at
## what the power costs, it banks nothing for a commander who has no power, and
## it banks nothing while a power is already running. A scripted grant is held to
## every one of those, so a beat cannot hand a side a second power's worth.

@export var team: int = 1
@export var points: int = 1000


func apply(state: GameState, _team: int) -> void:
	state.add_charge(team, points)


func board_error(state: GameState, _team: int) -> String:
	if not state.teams.has(team):
		return "charge is banked for army %d, which is not at this table" % team
	return ""


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	if not map.teams().has(team):
		return "charge is banked for army %d, which this board does not seat" % team
	if points <= 0:
		return "charge grant banks %d points" % points
	return ""
