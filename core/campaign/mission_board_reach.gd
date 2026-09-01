class_name MissionBoardReach
extends RefCounted
## Whether every square a mission's objectives name is ground some unit the
## player can field could walk, drive, fly or sail to.
##
## The board's own checks stop at "the cell exists and is a property"; the maps
## lint in `tests/unit/test_maps.gd` never sees a campaign board. This is the
## check that proves a redrawn board — a mountain wall, a ring, a coast — is
## still walkable to its own objectives, asked by `tools/check_campaigns.gd` and
## `tests/unit/test_mission_board_reach.gd` alike.
##
## A pure ground question: a flood over terrain per movement class, units
## ignored, four-directional like everything else. It reads terrain only, so a
## target reachable only by transport — a lander to an island — reads as
## unreachable; when the coastal act lands, the check learns `TerrainType.services`
## and transports.


## "" when every visible objective's ground can be reached, else why it cannot.
## A `ReachCellObjective` passes on any one cell of its zone; every other
## objective that names ground needs each cell reached. A hidden objective is not
## asked — nothing is judged on it until a beat reveals it.
static func error(mission: MissionDefinition, map: MapData, unit_db: UnitDB) -> String:
	var reached := _reached(map, _sources(mission, map, unit_db))
	for list: Array[MissionObjective] in [mission.objectives, mission.bonus_objectives]:
		for objective: MissionObjective in list:
			if objective.hidden:
				continue
			var missing := _unreached(objective, reached)
			if missing.is_empty():
				continue
			return (
				"mission '%s': '%s' at %s cannot be reached by any unit the player can field"
				% [mission.id, objective.text, missing[0]]
			)
	return ""


## Where the player's army can start from, by movement class: every unit row the
## board deals the player, and every unit type a property the player owns builds.
static func _sources(
	mission: MissionDefinition, map: MapData, unit_db: UnitDB
) -> Dictionary[StringName, Array]:
	var sources: Dictionary[StringName, Array] = {}
	for entry: Dictionary in map.starting_units:
		if entry["team"] != mission.player_team:
			continue
		var unit_type := unit_db.by_symbol(entry["symbol"])
		if unit_type != null:
			_add_source(sources, unit_type.move_class, entry["cell"])
	for cell: Vector2i in map.property_cells():
		if map.owner_at(cell) != mission.player_team:
			continue
		for move_class: StringName in map.terrain_at(cell).builds:
			_add_source(sources, move_class, cell)
	return sources


static func _add_source(
	sources: Dictionary[StringName, Array], move_class: StringName, cell: Vector2i
) -> void:
	if not sources.has(move_class):
		var starts: Array[Vector2i] = []
		sources[move_class] = starts
	sources[move_class].append(cell)


## Every cell some source class can reach, the sources themselves included.
static func _reached(
	map: MapData, sources: Dictionary[StringName, Array]
) -> Dictionary[Vector2i, bool]:
	var reached: Dictionary[Vector2i, bool] = {}
	for move_class: StringName in sources:
		var seen: Dictionary[Vector2i, bool] = {}
		var queue: Array[Vector2i] = []
		for start: Vector2i in sources[move_class]:
			seen[start] = true
			queue.append(start)
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			reached[cell] = true
			for step: Vector2i in MovementResolver.DIRECTIONS:
				var next := cell + step
				if seen.has(next) or not map.in_bounds(next):
					continue
				if not map.terrain_at(next).is_passable(move_class):
					continue
				seen[next] = true
				queue.append(next)
	return reached


## The cells this objective names that nothing reaches — empty when it is
## satisfied. A zone is satisfied by one reached cell; anything else by all.
static func _unreached(
	objective: MissionObjective, reached: Dictionary[Vector2i, bool]
) -> Array[Vector2i]:
	var missing: Array[Vector2i] = []
	for cell: Vector2i in objective.marker_cells():
		if not reached.has(cell):
			missing.append(cell)
	if objective is ReachCellObjective and missing.size() < objective.marker_cells().size():
		return []
	return missing
