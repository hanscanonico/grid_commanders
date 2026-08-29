class_name MapDocument
extends RefCounted
## A board being edited: the mutable draft `MapData` is the frozen read of.
##
## MapData is the simulation's board and is read-only once parsed, which is
## right for a match and useless for an author. This is the other half — a grid
## somebody paints on — and `to_text` is the one seam between them: a draft is
## saved by writing the exact `maps/*.txt` grammar `MapData.parse` reads, so
## nothing downstream ever learns a board was authored in the game rather than
## shipped. Every rule about what a board *means* stays MapData's; this class
## only knows what a cell currently holds.
##
## One unit per cell, because `GameState.create` refuses two — a draft that
## could hold a pair would only be refused later, when the author is no longer
## looking at the cell that did it.
##
## Node-free like the rest of `core/`.

## The one field the text grammar does not carry: which file this draft saves
## to, without its directory or its `.txt`. Empty until an author names it.
var map_name := ""
## The first comment line — the one-line pitch the map dropdown shows.
var description := ""
## Claims about the board, carried through `from_map` so a draft seeded off a
## shipped board is still that board. See MapData's tags of the same names.
var symmetric := false
var grouping := ""
var width := 0
var height := 0
var _db: TerrainDB
var _terrain: Array[TerrainType] = []  # row-major, width * height entries
var _owners: Dictionary[Vector2i, int] = {}  # missing key = neutral
## cell -> {team: int, symbol: String, tag: StringName, carry: bool}, the row
## shape `MapData.starting_units` hands back, keyed by where it stands.
var _units: Dictionary[Vector2i, Dictionary] = {}


## An empty board of open ground, the surface every property is drawn over.
static func blank(map_width: int, map_height: int, db: TerrainDB) -> MapDocument:
	var doc := MapDocument.new()
	doc._db = db
	doc.resize(map_width, map_height)
	return doc


## Seeds a draft from a parsed board, so a shipped map can be opened and edited.
static func from_map(map: MapData, db: TerrainDB) -> MapDocument:
	var doc := blank(map.width, map.height, db)
	doc.map_name = map.source_path.get_file().trim_suffix(".txt")
	doc.description = map.description
	doc.symmetric = map.symmetric
	doc.grouping = map.grouping
	for y in map.height:
		for x in map.width:
			doc._terrain[y * map.width + x] = map.terrain_at(Vector2i(x, y))
	doc._owners = map.initial_owners()
	for entry: Dictionary in map.starting_units:
		doc._units[entry.cell] = {
			"team": entry.team, "symbol": entry.symbol, "tag": entry.tag, "carry": entry.carry
		}
	return doc


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func terrain_at(cell: Vector2i) -> TerrainType:
	if not in_bounds(cell):
		return null
	return _terrain[cell.y * width + cell.x]


func owner_at(cell: Vector2i) -> int:
	return _owners.get(cell, MapData.NEUTRAL)


## The unit standing here, as a copy of its row, or an empty dictionary.
func unit_at(cell: Vector2i) -> Dictionary:
	var entry: Dictionary = _units.get(cell, {})
	return entry.duplicate()


func size() -> Vector2i:
	return Vector2i(width, height)


## Grows or crops the board, keeping what both sizes hold. Whatever falls
## outside is gone — its ownership and its unit with it, since a row naming a
## cell off the board is a text `MapData.parse` refuses.
func resize(map_width: int, map_height: int) -> void:
	var kept := _terrain
	var kept_width := width
	var kept_height := height
	width = maxi(map_width, 0)
	height = maxi(map_height, 0)
	_terrain = []
	for y in height:
		for x in width:
			var inside := x < kept_width and y < kept_height
			_terrain.append(kept[y * kept_width + x] if inside else _db.ground())
	for cell: Vector2i in _owners.keys():
		if not in_bounds(cell):
			_owners.erase(cell)
	for cell: Vector2i in _units.keys():
		if not in_bounds(cell):
			_units.erase(cell)


## Lays `terrain_id` on `cell`. Ownership clears when the cell stops being a
## property: a team owns a building, not the ground it stood on.
func paint(cell: Vector2i, terrain_id: StringName) -> bool:
	var terrain := _db.by_id(terrain_id)
	if terrain == null:
		push_error("MapDocument: unknown terrain id '%s'" % terrain_id)
		return false
	if not in_bounds(cell):
		push_error("MapDocument: cell %s out of bounds" % cell)
		return false
	_terrain[cell.y * width + cell.x] = terrain
	if not terrain.is_property:
		_owners.erase(cell)
	return true


## Hands `cell` to `team`, or back to nobody with `MapData.NEUTRAL`.
func set_owner(cell: Vector2i, team: int) -> bool:
	if not in_bounds(cell):
		push_error("MapDocument: cell %s out of bounds" % cell)
		return false
	if team == MapData.NEUTRAL:
		_owners.erase(cell)
		return true
	if not MapData.PLAYER_TEAMS.has(team):
		push_error("MapDocument: no seat %d to own %s" % [team, cell])
		return false
	if not terrain_at(cell).is_property:
		push_error("MapDocument: cell %s is not a property, cannot be owned" % cell)
		return false
	_owners[cell] = team
	return true


## Stands one of `team`'s units on `cell`, replacing whatever stood there.
## Takes the type rather than its symbol so the board is authored in the same
## terms the roster is; the symbol is the type's own.
func place_unit(cell: Vector2i, unit_type: UnitType, team: int) -> bool:
	if not in_bounds(cell):
		push_error("MapDocument: cell %s out of bounds" % cell)
		return false
	if not MapData.PLAYER_TEAMS.has(team):
		push_error("MapDocument: no seat %d to field a unit on %s" % [team, cell])
		return false
	_units[cell] = {"team": team, "symbol": unit_type.symbol, "tag": &"", "carry": false}
	return true


func remove_unit(cell: Vector2i) -> void:
	_units.erase(cell)


## The armies this draft seats, answered by `MapData.roster_for` off the seats
## the draft names — the board is the roster authority (four-players plan D1),
## and a draft has to say the same thing about itself that it will say once it
## is saved and read back.
func teams() -> Array[int]:
	var named: Array[int] = []
	for cell: Vector2i in _owners:
		named.append(_owners[cell])
	for cell: Vector2i in _units:
		named.append(_units[cell].team)
	return MapData.roster_for(named)


func player_count() -> int:
	return teams().size()


## The draft as map text: what a saved user board is, and the whole of what
## `MapData.parse` will read back. An empty section is omitted rather than left
## bare — a board with no starting army has no `[units]`, which is how the
## production maps already say it (production-maps plan D1).
func to_text() -> String:
	var lines := PackedStringArray()
	if description != "":
		lines.append("# %s" % description)
	if symmetric:
		lines.append("# %s" % MapData.SYMMETRIC_TAG)
	if grouping != "":
		lines.append("# %s %s" % [MapData.GROUPING_TAG, grouping])
	lines.append("[terrain]")
	for y in height:
		var row := ""
		for x in width:
			row += _terrain[y * width + x].symbol
		lines.append(row)
	if not _owners.is_empty():
		lines.append("[owners]")
		for cell in _sorted_cells(_owners):
			lines.append("%d %d %d" % [_owners[cell], cell.x, cell.y])
	if not _units.is_empty():
		lines.append("[units]")
		for cell in _sorted_cells(_units):
			lines.append(_unit_line(cell))
	return "\n".join(lines) + "\n"


func _unit_line(cell: Vector2i) -> String:
	var entry: Dictionary = _units[cell]
	var line: String = "%d %s %d %d" % [entry.team, entry.symbol, cell.x, cell.y]
	if entry.tag != &"":
		line += " %s" % entry.tag
	if entry.carry:
		line += " %s" % MapData.CARRY_MARK
	return line


## The keys of a cell-keyed dictionary, row-major — so the same draft always
## writes the same bytes, whatever order it was painted in.
func _sorted_cells(cells: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(cells.keys())
	result.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return result
