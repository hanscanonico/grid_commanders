class_name MapValidator
extends RefCounted
## Whether a board is playable, in the words an author reads.
##
## `MapData.parse` already refuses a board that is *malformed* — ragged rows,
## unknown symbols, an owner on open ground. What it accepts happily is a board
## that loads perfectly and cannot be played: a seat with no HQ, two landmasses
## with no way between them, a port dropped one cell inland. Those rules existed
## only as assertions inside tests/unit/test_maps.gd, which is the right place
## for the shipped roster and no place at all for a board somebody is painting
## right now. This is the same arithmetic said once, as sentences.
##
## Every complaint it returns is addressed to the author, not to a log: it names
## the cell and says what the board would do wrong, because "invalid map" is not
## an actionable failure message. An empty array means the board plays.
##
## `defects` is the full answer — the sentence and the cells it is about, so an
## editor can light the very buildings a complaint names — and `errors` is the
## same reading as words alone, for a caller with no board to point at.
##
## `tests/unit/test_maps.gd` keeps its own copies deliberately: those assertions
## name a failing board and the defect it prevents, one test each, and folding
## them into a single "MapValidator says no" would lose that. What
## `tests/unit/test_map_validator.gd` holds instead is parity — every shipped
## board passes here too, so the two can never drift into disagreeing about what
## playable means.
##
## Node-free like the rest of `core/`.

## The smallest and largest board an author may save, measured off the roster
## rather than picked: `maps/fixtures/analysis.txt` is 8x5 and `maps/bulwark.txt`
## is 49x32, so the bounds are exactly what already ships. Anything smaller than
## the floor cannot hold two seats' buildings at all, and anything past the
## ceiling has no zoom rung that frames it (see BattleZoom).
const MIN_SIZE := Vector2i(8, 5)
const MAX_SIZE := Vector2i(49, 32)


## Everything wrong with `map`, in reading order: its size, then its seats, then
## the board itself. Empty when it plays.
static func defects(map: MapData) -> Array[MapDefect]:
	var found: Array[MapDefect] = []
	_append(found, _size_defect(map))
	found.append_array(_seat_defects(map))
	_append(found, _property_count_defect(map))
	_append(found, _spare_hq_defect(map))
	_append(found, _hq_connection_defect(map))
	_append(found, _unit_on_property_defect(map))
	_append(found, _dock_defect(map))
	return found


## The same reading as words alone, for a caller with no board to point at.
static func errors(map: MapData) -> Array[String]:
	return _sentences(defects(map))


## The same reading of a draft that is not saved yet, taken through the text it
## would be saved as — `MapDocument.to_text` is the one seam between a draft and
## a board, so a draft is judged as the board it becomes rather than by a second
## copy of these rules. Text a parse refuses is one error and no more: nothing
## below can be asked of a board that does not exist.
static func draft_defects(doc: MapDocument, db: TerrainDB) -> Array[MapDefect]:
	var map := MapData.parse(doc.to_text(), db)
	if map == null:
		var refused: Array[MapDefect] = [
			MapDefect.at(
				"This board cannot be saved as a map file — see the log for what it refused."
			)
		]
		return refused
	return defects(map)


## The same reading as words alone.
static func draft_errors(doc: MapDocument, db: TerrainDB) -> Array[String]:
	return _sentences(draft_defects(doc, db))


static func _sentences(defects_found: Array[MapDefect]) -> Array[String]:
	var found: Array[String] = []
	for defect in defects_found:
		found.append(defect.text)
	return found


static func _append(found: Array[MapDefect], defect: MapDefect) -> void:
	if defect != null:
		found.append(defect)


static func _size_defect(map: MapData) -> MapDefect:
	var size := map.size()
	if size.x < MIN_SIZE.x or size.y < MIN_SIZE.y:
		return MapDefect.at(
			(
				"The board is %dx%d; a map must be at least %dx%d."
				% [size.x, size.y, MIN_SIZE.x, MIN_SIZE.y]
			)
		)
	if size.x > MAX_SIZE.x or size.y > MAX_SIZE.y:
		return MapDefect.at(
			(
				"The board is %dx%d; a map may be at most %dx%d."
				% [size.x, size.y, MAX_SIZE.x, MAX_SIZE.y]
			)
		)
	return null


## What each seat owes: a place on the board, one headquarters, and something
## that builds. Seats run 1..N with no gaps (MapData.roster_for), so a board
## naming seat 3 and skipping seat 2 seats an army with nothing — reported as the
## empty seat it is, and nothing further is asked of it, since every other
## complaint about that seat says the same thing again. Empty seats are named
## together, in one sentence: an author reading the same words four times over
## learns nothing the seat numbers do not already say.
static func _seat_defects(map: MapData) -> Array[MapDefect]:
	var found: Array[MapDefect] = []
	var unseated: Array[int] = []
	for team in map.teams():
		if not _is_seated(map, team):
			unseated.append(team)
			continue
		var owned := _owned_properties(map, team)
		var hqs: Array[Vector2i] = []
		var factories := 0
		for cell in owned:
			var terrain := map.terrain_at(cell)
			if terrain.is_headquarters:
				hqs.append(cell)
			if not terrain.builds.is_empty():
				factories += 1
		if hqs.size() != 1:
			found.append(
				MapDefect.at(
					(
						(
							"Seat %d owns %d headquarters; each seat needs exactly one, or it "
							% [team, hqs.size()]
						)
						+ "can never be beaten by capture."
					),
					hqs if not hqs.is_empty() else owned
				)
			)
		if factories == 0:
			found.append(
				MapDefect.at(
					(
						"Seat %d owns nothing that builds units, so it can never spend its income."
						% team
					),
					owned
				)
			)
	if unseated.is_empty():
		return found
	var merged: Array[MapDefect] = [_unseated_defect(unseated)]
	merged.append_array(found)
	return merged


## Every seat with nothing of its own, in one sentence rather than one apiece.
static func _unseated_defect(seats: Array[int]) -> MapDefect:
	var subject := "Seat %d holds nothing" % seats[0]
	var remedy := "give it a headquarters"
	if seats.size() > 1:
		subject = "Seats %s hold nothing" % _listed(seats)
		remedy = "give each a headquarters"
	return MapDefect.at(
		(
			"%s. Seats are numbered from 1 with no gaps, so %s or drop the higher seats."
			% [subject, remedy]
		)
	)


static func _listed(numbers: Array[int]) -> String:
	var words: PackedStringArray = []
	for number in numbers:
		words.append(str(number))
	var last := words[-1]
	words.remove_at(words.size() - 1)
	return ", ".join(words) + " and " + last


## A board holds at least one property per seat — below that there is nothing to
## take and no income to take it with.
static func _property_count_defect(map: MapData) -> MapDefect:
	var seats := map.player_count()
	var properties := map.property_cells()
	if properties.size() >= seats:
		return null
	return MapDefect.at(
		(
			"The board holds %d properties; %d seats need at least %d."
			% [properties.size(), seats, seats]
		),
		properties
	)


## An unowned headquarters fells nobody — CaptureCommand skips the neutral owner
## — so it is a building that looks decisive and is not.
static func _spare_hq_defect(map: MapData) -> MapDefect:
	for cell in map.property_cells():
		if map.terrain_at(cell).is_headquarters and map.owner_at(cell) == MapData.NEUTRAL:
			return MapDefect.at(
				"The headquarters at %s belongs to nobody; an unowned one fells no army." % cell,
				[cell] as Array[Vector2i]
			)
	return null


## Infantry is the yardstick because it is the only class that crosses every land
## terrain, so "cannot be walked to" means cannot be reached at all — and HQs
## walled off from each other reduce the match to a rout for everybody.
static func _hq_connection_defect(map: MapData) -> MapDefect:
	var hqs := _headquarters(map)
	if hqs.size() < 2:
		return null  # the per-seat count owns this case
	var seen := _flood(map, hqs[0], TerrainType.FOOT)
	for hq in hqs:
		if not seen.has(hq):
			return MapDefect.at(
				"No infantry can walk from the headquarters at %s to the one at %s." % [hqs[0], hq],
				[hqs[0], hq] as Array[Vector2i]
			)
	return null


static func _unit_on_property_defect(map: MapData) -> MapDefect:
	for entry: Dictionary in map.starting_units:
		var cell: Vector2i = entry.cell
		var terrain := map.terrain_at(cell)
		if terrain.is_property:
			return MapDefect.at(
				(
					"A unit starts on the %s at %s; no side should open the match mid-capture."
					% [terrain.display_name, cell]
				),
				[cell] as Array[Vector2i]
			)
	return null


## A dock is only a dock if something can sail out of it, and two docks on two
## separate seas build two fleets that can never meet — the naval plan's R1, which
## the AI cannot plan around because it never ferries. Asked of what the terrain
## builds rather than of its id, so a new facility inherits the check.
static func _dock_defect(map: MapData) -> MapDefect:
	var docks := _docks(map)
	for cell in docks:
		if not _has_sailable_neighbour(map, cell):
			return MapDefect.at(
				(
					"The %s at %s has no water beside it, so every hull it builds is trapped."
					% [map.terrain_at(cell).display_name, cell]
				),
				[cell] as Array[Vector2i]
			)
	if docks.size() < 2:
		return null
	var reachable := _flood(map, docks[0], TerrainType.SHIP)
	for cell in docks:
		if not reachable.has(cell):
			return (
				MapDefect
				. at(
					(
						(
							"No hull can sail from the dock at %s to the one at %s, so their fleets can "
							% [docks[0], cell]
						)
						+ "never meet."
					),
					[docks[0], cell] as Array[Vector2i]
				)
			)
	return null


static func _has_sailable_neighbour(map: MapData, cell: Vector2i) -> bool:
	for step in MovementResolver.DIRECTIONS:
		var next: Vector2i = cell + step
		if map.in_bounds(next) and map.terrain_at(next).is_passable(TerrainType.SHIP):
			return true
	return false


static func _is_seated(map: MapData, team: int) -> bool:
	if not _owned_properties(map, team).is_empty():
		return true
	for entry: Dictionary in map.starting_units:
		if int(entry.team) == team:
			return true
	return false


static func _owned_properties(map: MapData, team: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in map.property_cells():
		if map.owner_at(cell) == team:
			cells.append(cell)
	return cells


static func _headquarters(map: MapData) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in map.property_cells():
		if map.terrain_at(cell).is_headquarters:
			cells.append(cell)
	return cells


static func _docks(map: MapData) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in map.property_cells():
		if map.terrain_at(cell).can_build(TerrainType.SHIP):
			cells.append(cell)
	return cells


## Every cell `move_class` can reach from `start`, `start` included.
static func _flood(map: MapData, start: Vector2i, move_class: StringName) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in MovementResolver.DIRECTIONS:
			var next: Vector2i = cell + step
			if seen.has(next) or not map.in_bounds(next):
				continue
			if not map.terrain_at(next).is_passable(move_class):
				continue
			seen[next] = true
			queue.append(next)
	return seen
