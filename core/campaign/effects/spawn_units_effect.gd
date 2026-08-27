class_name SpawnUnitsEffect
extends MissionEffect
## Lands units on the board — the relief column, the second wave, the garrison
## that was always in the hills.
##
## A landing unit arrives exactly as a built one does: `Unit.create`, then
## exhausted, so a wave cannot arrive and act in the same instant however it was
## timed. Nothing is charged for it and nothing is banked to any meter — this is
## authored reinforcement, not production.
##
## **An occupied cell is skipped, not cleared and not deferred.** The board is
## authored so a landing zone is empty (`definition_error` refuses a cell one of
## the board's own units starts on), but a mission's units can be standing
## anywhere by the time the beat comes due. Clearing the square would make this
## the second thing in the game that removes a unit without a shot, which
## Hammerfall is deliberately the only one of; refusing the whole command would
## lose the beat outright on a trigger that has already passed. So the column
## lands as far as there is room for it.

@export var team: int = 2
@export var units: Array[MissionSpawn] = []


func apply(state: GameState, _team: int) -> void:
	for spawn: MissionSpawn in units:
		if state.unit_at(spawn.cell) != null:
			continue
		var unit := Unit.create(spawn.unit_type, team, spawn.cell)
		unit.tag = spawn.tag
		unit.hp = spawn.hp
		unit.acted = true
		state.units.append(unit)


func spawned_tags() -> Array[StringName]:
	var named: Array[StringName] = []
	for spawn: MissionSpawn in units:
		if spawn != null and spawn.tag != &"":
			named.append(spawn.tag)
	return named


func board_error(state: GameState, _team: int) -> String:
	var seat_error := MissionBoardCheck.absent_team(state, team, "spawn lands units for")
	if seat_error != "":
		return seat_error
	for spawn: MissionSpawn in units:
		if spawn == null or spawn.unit_type == null:
			return "spawn holds an empty unit slot"
		if not state.map.in_bounds(spawn.cell):
			return "spawn lands a unit off the board at %s" % spawn.cell
	return ""


func definition_error(map: MapData, _team: int, _unit_db: UnitDB) -> String:
	var seat_error := MissionBoardCheck.unseated_team(map, team, "spawn lands units for")
	if seat_error != "":
		return seat_error
	if units.is_empty():
		return "spawn lands nothing"
	var landing: Dictionary[Vector2i, bool] = {}
	var named: Dictionary[StringName, bool] = {}
	for spawn: MissionSpawn in units:
		var error := _placement_error(map, spawn)
		if error != "":
			return error
		if landing.has(spawn.cell):
			return "spawn lands two units on %s" % spawn.cell
		landing[spawn.cell] = true
		if spawn.tag != &"" and named.has(spawn.tag):
			return "spawn names two units '%s'" % spawn.tag
		named[spawn.tag] = true
	return ""


## Why one unit could not be landed where the map stands it, or "". Terrain is
## the map's answer and never moves during a match, which is why passability is
## settled here rather than again on the live board.
func _placement_error(map: MapData, spawn: MissionSpawn) -> String:
	if spawn == null or spawn.unit_type == null:
		return "spawn holds an empty unit slot"
	var what := spawn.unit_type.id
	var bounds_error := MissionBoardCheck.off_board(map, spawn.cell, "spawn lands %s at" % what)
	if bounds_error != "":
		return bounds_error
	var terrain := map.terrain_at(spawn.cell)
	if not terrain.is_passable(spawn.unit_type.move_class):
		return "spawn lands %s on %s, which it cannot stand on" % [what, terrain.id]
	for entry: Dictionary in map.starting_units:
		if entry["cell"] == spawn.cell:
			return "spawn lands %s at %s, where the board already stands one" % [what, spawn.cell]
	var tag_error := UnitTag.name_error(spawn.tag)
	if tag_error != "":
		return tag_error
	if spawn.tag != &"" and MissionObjective.board_names(map, spawn.tag):
		return "spawn names '%s', which a unit on this board already carries" % spawn.tag
	return ""
