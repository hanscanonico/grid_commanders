class_name MapData
extends RefCounted
## Authoritative map state for the simulation: terrain grid plus property
## ownership. The TileMapLayer in the battle scene is painted *from* this;
## it is never the source of truth.
##
## Map text format (see maps/*.txt):
##   # <one-line description>   -- the first comment line; shown in the menu
##   # symmetric               -- optional tag; asserts 180-degree symmetry
##   # grouping 1+2+3v4        -- optional tag; a parity claim
##                                 tests/unit/test_maps.gd checks (see `grouping`)
##   # any other comment
##   [terrain]
##   <one row of terrain symbols per line, all rows the same width>
##   [owners]
##   <team> <x> <y>       # team is 1-based; only property tiles may be owned
##   [units]
##   <team> <symbol> <x> <y> [tag] [^]  # starting units; symbols defined by UnitType.
##                                   # the tag is optional and names that one unit for
##                                   # a campaign mission's objectives and events: an
##                                   # identifier, and unique on the board.
##                                   # a trailing ^ marks the row a carry slot: a
##                                   # campaign's carried army stands there instead of
##                                   # this unit, at this unit's own type. See
##                                   # CARRY_MARK.
##
## [owners] and [units] must come after [terrain] (they need the bounds).
## [units] is optional: a board that omits it starts both sides with nothing but
## their properties, and the first move of the match is a build (maps/forge.txt).
## Unit symbols are validated later by GameState.create, which has the UnitDB.
## The playability invariants no parser can express — the ones about HQs, bases,
## reachability, the symmetry or grouping a tag above claims, and the water a
## port or a shoal needs — are asserted over every shipped map by
## tests/unit/test_maps.gd, which names each one and the failure it prevents.
##
## The board is also the roster authority (four-players plan D1): how many armies
## a match seats is read off the teams its [owners] and [units] name, never from a
## menu setting. See `teams()`.

const NEUTRAL := 0
## Comment line that opts a map into the mirror check in tests/unit/test_maps.gd.
const SYMMETRIC_TAG := "symmetric"
## Comment prefix declaring how this board's seats claim to group into sides,
## e.g. `# grouping 1+2+3v4` — the same grammar `--sides=` reads
## (MatchRequest.parse_sides_flag). A claim tests/unit/test_maps.gd checks,
## never an instruction a match follows (asymmetric-board plan D2): nothing
## outside that test reads `grouping`, and a board carrying it still plays a
## free-for-all unless a launch says otherwise.
const GROUPING_TAG := "grouping"
## Marks a `[units]` row as a **carry slot**: the campaign's carried army stands
## there if it still has a unit of that row's type, and the row's own unit stands
## there if it has not (campaign-depth D6). So a board always fields exactly the
## army it was authored with, whatever the war has cost.
##
## The last column of the row, after the optional tag, and it can never be read as
## one: a tag is an identifier and this is not, so a board naming `^` is refused
## rather than quietly carrying a unit called that.
const CARRY_MARK := "^"

## Every team a board may seat, in seat order — the legal maximum a roster is a
## prefix of. The one bound on the question, re-exported as `GameState.TEAMS`
## rather than restated there: a board naming a fifth army fails at parse instead
## of loading clean and seating a side that never gets a turn.
const PLAYER_TEAMS: Array[int] = [1, 2, 3, 4]
## The smallest roster a board can seat, and what a board that names nobody gets.
## A match is at least a duel — a terrain-only board is a fixture rather than a
## match, and most movement tests build one.
const DEFAULT_TEAMS: Array[int] = [1, 2]

var width := 0
var height := 0
## First comment line: the one-line pitch the map dropdown shows as a tooltip.
var description := ""
## Set by the `# symmetric` tag: this map claims 180-degree rotational symmetry.
var symmetric := false
## Set by `# grouping <spec>`: this map claims its seats stand in the given
## sides. Raw text, e.g. "1+2+3v4" — MapData interprets none of it; only
## tests/unit/test_maps.gd reads it, through MatchRequest.parse_sides_flag.
## Empty when the tag is absent.
var grouping := ""
## Where this map was read from; empty for maps parsed straight from a string.
var source_path := ""
## Raw starting-unit entries: {team: int, symbol: String, cell: Vector2i,
## tag: StringName, carry: bool}. The tag is empty for a unit the board did not
## name, and `carry` is true only for a row marked `^` — see CARRY_MARK.
var starting_units: Array[Dictionary] = []
var _terrain: Array[TerrainType] = []  # row-major, width * height entries
var _owners: Dictionary[Vector2i, int] = {}  # missing key = neutral
var _property_cells: Array[Vector2i] = []  # cached by property_cells()
var _property_cells_built := false
## The names taken so far, appended beside each tagged `starting_units` row, so a
## row asks what is free without rebuilding the list. Parse scratch: `parse` makes
## a MapData per board, so it never outlives the one read that fills it.
var _tags: Array[StringName] = []
## The seats this board deals, built by `_build_roster` when `parse` finishes.
## Empty on a MapData nothing has parsed into; `teams()` answers for that.
var _teams: Array[int] = []


static func load_from_file(path: String, db: TerrainDB) -> MapData:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("MapData: cannot read map file '%s'" % path)
		return null
	var map := parse(text, db)
	if map != null:
		map.source_path = path
	return map


## Returns null (with a pushed error) on any malformed input.
static func parse(text: String, db: TerrainDB) -> MapData:
	var map := MapData.new()
	var section := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			map._read_comment(line.trim_prefix("#").strip_edges())
			continue
		if line.begins_with("["):
			section = line
			continue
		match section:
			"[terrain]":
				if not map._append_terrain_row(line, db):
					return null
			"[owners]":
				if not map._set_owner_from_line(line):
					return null
			"[units]":
				if not map._append_unit_from_line(line):
					return null
			_:
				push_error("MapData: line outside a known section: '%s'" % line)
				return null
	if map.width == 0 or map.height == 0:
		push_error("MapData: map has no terrain rows")
		return null
	map._build_roster()
	return map


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func terrain_at(cell: Vector2i) -> TerrainType:
	if not in_bounds(cell):
		return null
	return _terrain[cell.y * width + cell.x]


func owner_at(cell: Vector2i) -> int:
	return _owners.get(cell, NEUTRAL)


## Copy of the starting ownership for GameState; runtime capture never
## mutates the map itself.
func initial_owners() -> Dictionary[Vector2i, int]:
	return _owners.duplicate()


## Every capturable property cell on the map, row-major (computed once on
## demand). Returns a copy, like initial_owners: the cache stays ours.
func property_cells() -> Array[Vector2i]:
	if not _property_cells_built:
		for y in height:
			for x in width:
				if _terrain[y * width + x].is_property:
					_property_cells.append(Vector2i(x, y))
		_property_cells_built = true
	return _property_cells.duplicate()


## The armies this board seats, in seat order: seat 1 up to the highest one its
## [owners] and [units] name, and never fewer than a duel. `GameState.create`
## copies it into the match roster, so how many armies play is a property of the
## board (four-players plan D1). Returns a copy, like `initial_owners`.
func teams() -> Array[int]:
	return _teams.duplicate() if not _teams.is_empty() else DEFAULT_TEAMS.duplicate()


## How many armies the board seats — what the menu prints beside the size.
func player_count() -> int:
	return teams().size()


func size() -> Vector2i:
	return Vector2i(width, height)


## The cell `cell` rotates onto under 180 degrees. Its own inverse, and the one
## definition of "mirrored" the maps and their symmetry lint share.
func mirrored(cell: Vector2i) -> Vector2i:
	return Vector2i(width - 1 - cell.x, height - 1 - cell.y)


## Comments carry three pieces of data: the `# symmetric` and `# grouping`
## tags, and the first comment line, which by convention is the map's
## one-line description.
func _read_comment(comment: String) -> void:
	if comment == SYMMETRIC_TAG:
		symmetric = true
	elif comment.begins_with(GROUPING_TAG + " "):
		grouping = comment.trim_prefix(GROUPING_TAG + " ").strip_edges()
	elif description.is_empty():
		description = comment


func _append_terrain_row(line: String, db: TerrainDB) -> bool:
	if width == 0:
		width = line.length()
	elif line.length() != width:
		push_error("MapData: row %d is %d wide, expected %d" % [height, line.length(), width])
		return false
	for symbol in line:
		var terrain := db.by_symbol(symbol)
		if terrain == null:
			push_error("MapData: unknown terrain symbol '%s' in row %d" % [symbol, height])
			return false
		_terrain.append(terrain)
	height += 1
	return true


func _set_owner_from_line(line: String) -> bool:
	var parts := line.split(" ", false)
	if parts.size() != 3:
		push_error("MapData: bad owner line '%s' (expected: team x y)" % line)
		return false
	if not parts[1].is_valid_int() or not parts[2].is_valid_int():
		push_error("MapData: owner cell must be integer coordinates in '%s'" % line)
		return false
	var team := int(parts[0])
	var cell := Vector2i(int(parts[1]), int(parts[2]))
	if not parts[0].is_valid_int() or not PLAYER_TEAMS.has(team):
		push_error(_team_bound_message("owner", line))
		return false
	if not in_bounds(cell):
		push_error("MapData: owner cell %s out of bounds" % cell)
		return false
	if not terrain_at(cell).is_property:
		push_error("MapData: cell %s is not a property, cannot be owned" % cell)
		return false
	_owners[cell] = team
	return true


func _append_unit_from_line(line: String) -> bool:
	var parts := line.split(" ", false)
	# Taken off the end first, so everything below reads the row the format had
	# before carry slots existed.
	var carry := parts.size() > 4 and parts[parts.size() - 1] == CARRY_MARK
	if carry:
		parts.resize(parts.size() - 1)
	if parts.size() < 4 or parts.size() > 5:
		push_error("MapData: bad unit line '%s' (expected: team symbol x y [tag] [^])" % line)
		return false
	if not parts[2].is_valid_int() or not parts[3].is_valid_int():
		push_error("MapData: unit cell must be integer coordinates in '%s'" % line)
		return false
	var team := int(parts[0])
	var cell := Vector2i(int(parts[2]), int(parts[3]))
	if not parts[0].is_valid_int() or not PLAYER_TEAMS.has(team):
		push_error(_team_bound_message("unit", line))
		return false
	if not in_bounds(cell):
		push_error("MapData: unit cell %s out of bounds" % cell)
		return false
	var tag: StringName = StringName(parts[4]) if parts.size() == 5 else &""
	var tag_error := _tag_error(tag, line)
	if tag_error != "":
		push_error(tag_error)
		return false
	starting_units.append(
		{"team": team, "symbol": parts[1], "cell": cell, "tag": tag, "carry": carry}
	)
	if tag != &"":
		_tags.append(tag)
	return true


## "" when `tag` is a name a mission may reach this unit by, else why it is not,
## in this parser's voice. What makes a name legal is `UnitTag`'s and not this
## file's, because a save carries the same field and the two must refuse the same
## strings; the board is only the first place one can be refused, before anything
## has picked it.
func _tag_error(tag: StringName, line: String) -> String:
	var error := UnitTag.name_error(tag)
	if error == "":
		error = UnitTag.taken_error(tag, _tags)
	if error == "":
		return ""
	return "MapData: %s in '%s'" % [error, line]


## The roster a board naming `named_teams` seats — the one statement of the rule,
## asked by `_build_roster` here and by `MapDocument.teams()` for a draft that is
## not saved yet, so a board says the same thing about itself both times.
##
## Seats run from 1 up to the highest one the board names, never fewer than the
## two a match needs. Two things make it a range rather than the exact set of
## teams mentioned. Seats are positional everywhere downstream — turn order, the
## seat strip, the colour fallback — so a hole is a side every one of those
## indexes past; and a board that only ever mentions one army (which most test
## fixtures are, and which no match is) has always been played as a duel with an
## empty seat opposite.
static func roster_for(named_teams: Array[int]) -> Array[int]:
	var seats := DEFAULT_TEAMS.size()
	for team in named_teams:
		seats = maxi(seats, team)
	return PLAYER_TEAMS.slice(0, seats)


## Reads the roster off the board, once, at the end of `parse` — the last line may
## be the one that seats the last army.
func _build_roster() -> void:
	var named: Array[int] = []
	for cell: Vector2i in _owners:
		named.append(_owners[cell])
	for entry: Dictionary in starting_units:
		named.append(entry.team)
	_teams = roster_for(named)


func _team_bound_message(what: String, line: String) -> String:
	return (
		"MapData: %s team must be 1..%d in '%s'"
		% [what, PLAYER_TEAMS[PLAYER_TEAMS.size() - 1], line]
	)
