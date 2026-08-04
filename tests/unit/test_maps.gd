extends GutTest
## Playability lint over every board under maps/ — the shipped roster and the
## fixtures both, including boards added after this file was written, since it
## discovers them through MapCatalog instead of listing them.
##
## The fixtures are linted for the reason they exist: every balance verdict in
## docs/commander_balance.md is measured on one, so a fixture that is quietly
## unplayable does not fail a test, it moves a number nobody can then attribute.
## docs/commander_balance.md still recounts the cap-stall incident — 430 matches
## of 432 stalled, from one bad fixture — which is the class of defect these
## lints were written to catch statically, and they were catching it for every
## board except the ones the verdicts came off (COM-106).
##
## MapData.parse and GameState.create already reject *malformed* maps: ragged
## rows, unknown terrain or unit symbols, owners on non-property cells,
## out-of-bounds entries, two units on one cell, a unit standing on terrain it
## cannot enter. What neither catches is a map that loads perfectly and is then
## unplayable — and each assertion below is one of those:
##
## - An HQ is the building whose capture fells its owner, so a board owes each
##   army exactly one and no spares. An army holding no HQ cannot be taken out by
##   capture at all, which quietly reduces the board to rout-only for it; and a
##   spare, unowned HQ fells nobody — CaptureCommand skips MapData.NEUTRAL,
##   because there is no army behind it — so it is a building that looks decisive
##   and tells the player the match can be won somewhere it cannot.
## - A side with no base has no income engine and an AI that can never build.
## - Seats opening on different buildings open on different income and different
##   production. The `# symmetric` tag catches that on a duel, but it is a
##   180-degree instrument no three- or four-seat board can carry, so the
##   per-seat property count is the lint that holds those level — until a board
##   declares `# grouping`, at which point parity moves from the seat to the
##   side (asymmetric-board plan D3): allied seats still have to match kind for
##   kind, and no side may open on more property, summed, than everyone else
##   combined. The tag is a claim the lint checks, never an instruction a match
##   follows (D2), and it is guarded against becoming a general opt-out: a
##   tagged board whose sides were already going to open level fails too (R5).
## - HQs walled off from each other put every army's HQ beyond the others' reach,
##   so no army can ever be felled by capture, which quietly reduces the match to
##   rout-only.
## - A map whose header claims symmetry and does not have it hands one side a
##   terrain or income edge that no amount of playtesting attributes correctly.
## - A port with no sailable water beside it builds hulls that can never leave
##   the dock, and two ports on separate bodies of water build two fleets that
##   can never meet — the naval plan's R1, which the AI cannot plan its way out
##   of because it cannot ferry.
## - A shoal is road that also floats: identical cost for every land class, plus
##   lander access. That makes a careless one a bridge, and a bridge across water
##   silently deletes whatever the water was there to separate.
##
## Every failure names the map it failed on. "The roster is broken" is not an
## actionable failure message.
##
## The `# grouping` counter-tests live in the sibling test_map_grouping.gd
## rather than here: this file already sits at the gdlintrc
## max-public-methods ceiling, the same reason test_sides_flag.gd split from
## test_match_request.gd. Both suites share the check itself,
## tests/helpers/map_parity.gd, so there is one authority for what "level"
## means either way.

const HQ := &"hq"
const BASE := &"base"
const PORT := &"port"
const SHOAL := &"shoal"

const MapParity := preload("res://tests/helpers/map_parity.gd")

var terrain_db: TerrainDB
var unit_db: UnitDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()


func test_every_map_parses_and_builds_a_game_state() -> void:
	var paths := _board_paths()
	assert_gt(MapCatalog.paths().size(), 0, "maps/ should ship at least one map")
	assert_gt(MapCatalog.fixture_paths().size(), 0, "maps/fixtures/ should hold at least one board")
	for path in paths:
		var map := MapData.load_from_file(path, terrain_db)
		assert_not_null(map, "%s should parse" % path)
		if map != null:
			assert_not_null(GameState.create(map, unit_db), "%s should build a GameState" % path)


func test_every_map_gives_each_team_exactly_one_hq_it_owns() -> void:
	for map in _maps():
		var hq_owners := []
		for cell in _cells_of_terrain(map, HQ):
			hq_owners.append(map.owner_at(cell))
		assert_eq(
			hq_owners.size(),
			map.player_count(),
			(
				"%s: one HQ per team and no spares — an army with no HQ can only be " % _name(map)
				+ "routed, and an unowned HQ fells nobody while looking like it would"
			)
		)
		for team in map.teams():
			assert_eq(
				hq_owners.count(team), 1, "%s: team %d should start on one HQ" % [_name(map), team]
			)


func test_every_map_gives_each_team_a_base() -> void:
	for map in _maps():
		for team in map.teams():
			var bases := 0
			for cell in _cells_of_terrain(map, BASE):
				if map.owner_at(cell) == team:
					bases += 1
			assert_gt(
				bases,
				0,
				(
					(
						"%s: team %d owns no base, so it has no production and the AI "
						% [_name(map), team]
					)
					+ "has nothing to spend income on"
				)
			)


## Income and production are what an army fights with, so two seats that open on
## different holdings are playing two different matches — and the difference
## reads back as "that commander is stronger" rather than "that seat is", which
## is the one attribution no amount of playtesting recovers from. Nothing else
## catches it: a board that hands one side a spare city parses, loads and plays
## perfectly, and is quietly unfair every time.
##
## The army each seat opens with is the same question asked of the other half of
## the board, and priced in funds for the same reason MapParity counts properties
## by kind — four Infantry are not a Md Tank. `# symmetric` catches both at once,
## but only on a board that carries the tag, and it is a 180-degree instrument no
## three- or four-seat board can carry, so this is what holds the rest level.
func test_every_map_deals_each_team_the_same_holdings() -> void:
	for map in _maps():
		var lead_team: int = map.teams()[0]
		var lead_cost := _starting_army_cost(map, lead_team)
		for team in map.teams():
			assert_eq(
				_starting_army_cost(map, team),
				lead_cost,
				(
					(
						"%s: team %d opens with %d funds of army to team %d's %d — a seat "
						% [_name(map), team, _starting_army_cost(map, team), lead_team, lead_cost]
					)
					+ "handed more materiel is an edge no playtest attributes right"
				)
			)
		assert_eq(
			MapParity.error(map),
			"",
			(
				"%s: a seat (or, on a `# grouping` board, a side) with more income " % _name(map)
				+ "or more production is an edge no playtest attributes right"
			)
		)


func test_every_map_keeps_its_hqs_reachable_on_foot() -> void:
	for map in _maps():
		assert_eq(
			_hq_connection_error(map),
			"",
			(
				"%s: infantry must be able to walk between the HQs, or no army can " % _name(map)
				+ "ever be felled by capture and only a rout can end the match"
			)
		)


func test_no_unit_starts_on_a_property() -> void:
	for map in _maps():
		for entry: Dictionary in map.starting_units:
			var cell: Vector2i = entry.cell
			assert_false(
				map.terrain_at(cell).is_property,
				(
					(
						"%s: a unit starts on the %s at %s — no side should open a "
						% [_name(map), map.terrain_at(cell).display_name, cell]
					)
					+ "capture ahead of turn one"
				)
			)


func test_maps_tagged_symmetric_really_are() -> void:
	var tagged := 0
	for map in _maps():
		if not map.symmetric:
			continue
		tagged += 1
		assert_eq(
			_mirror_error(map),
			"",
			"%s carries the `# symmetric` tag, so it has to mirror exactly" % _name(map)
		)
	assert_gt(tagged, 0, "at least one shipped map should be tagged `# symmetric`")


## A port is only a port if something can sail out of it. Nothing in the parser
## notices one dropped a cell inland, and the failure it produces is silent: the
## build menu offers hulls, they spawn, and they are stuck on the dock forever.
func test_every_port_opens_onto_water_a_hull_can_use() -> void:
	for map in _maps():
		for cell in _cells_of_terrain(map, PORT):
			var sailable := false
			for step in MovementResolver.DIRECTIONS:
				var next: Vector2i = cell + step
				if map.in_bounds(next) and map.terrain_at(next).is_passable(TerrainType.SHIP):
					sailable = true
					break
			assert_true(
				sailable,
				(
					(
						"%s: the port at %s has no sailable cell beside it, so every "
						% [_name(map), cell]
					)
					+ "hull it builds is trapped on the dock"
				)
			)


## Naval plan R1, as a test rather than a paragraph: the AI never builds
## transports, so it can only fight a fleet it can sail to. Two ports on two
## separate seas give it a navy that shells nothing, which reads to a player as
## "the AI is broken" rather than "this map is".
func test_all_ports_on_a_map_share_one_body_of_water() -> void:
	for map in _maps():
		var ports := _cells_of_terrain(map, PORT)
		if ports.size() < 2:
			continue
		var reachable := _flood(map, ports[0], TerrainType.SHIP)
		for port in ports:
			assert_true(
				reachable.has(port),
				(
					(
						"%s: no hull can sail from %s to %s, so fleets built at "
						% [_name(map), ports[0], port]
					)
					+ "the two ports can never engage each other"
				)
			)


## Shoals cost every land class exactly what road does, so a shoal is walkable by
## everything that drives. One placed carelessly — or a chain of them — is a ford
## across water that no header mentions and no other test sees. Comparing the
## land graph with and without them says the real thing: beaches may extend a
## coast, never join two of them.
func test_no_shoal_joins_two_landmasses() -> void:
	for map in _maps():
		if _cells_of_terrain(map, SHOAL).is_empty():
			continue
		assert_eq(
			_land_components(map, true),
			_land_components(map, false),
			(
				"%s: its shoals merge landmasses the water separates — a beach may " % _name(map)
				+ "extend a coast, but a chain of them is a bridge for everything that drives"
			)
		)


## A beach nothing can land on is decoration wearing design's clothes. Shoals
## exist so a lander can put armour ashore, and a lander comes from a port — so
## every beach has to be sailable to from one. Catches the two ways to get this
## wrong: a shoal walled off from the sea, and a shoal on water no dock opens
## onto.
func test_every_shoal_can_be_reached_by_a_landing_craft() -> void:
	for map in _maps():
		var shoals := _cells_of_terrain(map, SHOAL)
		if shoals.is_empty():
			continue
		var beachable := {}
		for port in _cells_of_terrain(map, PORT):
			beachable.merge(_flood(map, port, TerrainType.LANDER))
		for shoal in shoals:
			assert_true(
				beachable.has(shoal),
				(
					(
						"%s: no lander can sail from any port to the beach at %s, "
						% [_name(map), shoal]
					)
					+ "so nothing can ever land on it"
				)
			)


## A property no army can walk to is income nobody collects — unless something
## can be *delivered* to it, which is the whole point of an island of cities.
## Air freight is not a promise the board can make — a t-copter needs an airport
## somebody happens to own — so the lander is the yardstick, and it unloads from
## a shoal or a port and nowhere else (DropCommand, over UnitType.unload_terrain).
## An offshore property therefore owes its own landmass one of those, and one a
## lander can actually sail to. Without it the cities are scenery that pays nobody for
## the whole match, and nothing else on the board says so — the map parses, the
## HQs connect, and the beach lint above is silent because there is no beach.
func test_every_property_off_the_mainland_can_be_landed_on() -> void:
	for map in _maps():
		assert_eq(
			_delivery_error(map),
			"",
			(
				"%s: a property no army can walk to is only a prize if a landing " % _name(map)
				+ "craft can put a soldier beside it"
			)
		)


## The two lints above pass on every shipped map, which is only reassuring if
## they can fail at all. These two check the mechanism against a board built to
## break it, so "green" keeps meaning something after the next map lands.
func test_the_shared_water_lint_can_tell_two_seas_apart() -> void:
	# Two one-cell harbours with dry land between them.
	var map := MapData.parse("[terrain]\nPSS.SSP\n", terrain_db)
	assert_not_null(map)
	var ports := _cells_of_terrain(map, PORT)
	assert_eq(ports.size(), 2, "the fixture should have a dock at each end")
	assert_false(
		_flood(map, ports[0], TerrainType.SHIP).has(ports[1]),
		"a hull cannot sail across dry land, and the lint has to notice"
	)


## Same treatment for the delivery lint: one island city with no beach, and the
## same island with one, so "green" means the check looked rather than shrugged.
func test_the_delivery_lint_can_tell_a_prize_from_a_marooned_city() -> void:
	var marooned := MapData.parse("[terrain]\nPSSSS\nSSSCS\nSSSSS\n", terrain_db)
	assert_not_null(marooned)
	assert_ne(
		_delivery_error(marooned),
		"",
		"a city ringed by open water can never be captured, and the lint has to notice"
	)
	var landable := MapData.parse("[terrain]\nPSSSS\nSSSC_\nSSSSS\n", terrain_db)
	assert_not_null(landable)
	assert_eq(
		_delivery_error(landable), "", "the same city with a beach beside it is a prize, not a trap"
	)


func test_the_shoal_lint_can_tell_a_beach_from_a_bridge() -> void:
	var islands := MapData.parse("[terrain]\nSSSSS\nS.S.S\nSSSSS\n", terrain_db)
	assert_not_null(islands)
	assert_eq(_land_components(islands, true), 2, "two islands with water between them")
	var bridged := MapData.parse("[terrain]\nSSSSS\nS._.S\nSSSSS\n", terrain_db)
	assert_not_null(bridged)
	assert_eq(_land_components(bridged, false), 2, "the same two islands, beach ignored")
	assert_eq(
		_land_components(bridged, true),
		1,
		"the beach joins them into one landmass — exactly what the lint is for"
	)


## The bridge check works by counting components, so anything that adds a
## component fails it. An offshore beach — a landing point out in open water,
## touching no land at all — is one of those, and it is the one shape that would
## make the lint accuse a map of the opposite of what it did.
func test_the_shoal_lint_does_not_mistake_an_offshore_beach_for_a_bridge() -> void:
	var offshore := MapData.parse("[terrain]\nSSSSS\nS.S.S\nSSSSS\nSS_SS\n", terrain_db)
	assert_not_null(offshore)
	assert_eq(
		_cells_of_terrain(offshore, SHOAL).size(), 1, "the fixture should have one offshore beach"
	)
	assert_eq(
		_land_components(offshore, true),
		_land_components(offshore, false),
		"a beach no land touches is a lander waypoint, not a bridge, and the lint has to say so"
	)
	assert_eq(_land_components(offshore, true), 2, "the two islands are still the only landmasses")


func test_every_map_describes_itself_for_the_menu() -> void:
	for path in MapCatalog.paths():
		var map := MapData.load_from_file(path, terrain_db)
		assert_not_null(map, "%s should parse" % path)
		if map == null:
			continue
		assert_ne(
			map.description,
			"",
			(
				"%s: the first comment line is the map dropdown's tooltip, so it " % _name(map)
				+ "has to be a one-line description of the board"
			)
		)


## The menu opens on item 0, so the order MapCatalog hands it decides the
## default match. The teaching board leads; the rest remain smallest first.
func test_the_menu_offers_the_tutorial_board_first_then_smallest() -> void:
	var maps := MapCatalog.ordered(terrain_db)
	assert_eq(maps.size(), MapCatalog.paths().size(), "every shipped map should reach the menu")
	assert_eq(maps[0].source_path, MapCatalog.TUTORIAL_MAP_PATH)
	for i in range(2, maps.size()):
		var previous := maps[i - 1]
		assert_lte(
			previous.width * previous.height,
			maps[i].width * maps[i].height,
			"%s should not come before %s" % [_name(previous), _name(maps[i])]
		)


## COM-122: the strip teaches on one board and no other, so exactly one shipped
## map may answer to `teaches` — and it has to be a map that ships, not a path
## that was renamed out from under the constant.
func test_exactly_one_shipped_board_teaches() -> void:
	var teaching: Array[String] = []
	for path in MapCatalog.paths():
		if MapCatalog.teaches(path):
			teaching.append(path)
	assert_eq(
		teaching,
		[MapCatalog.TUTORIAL_MAP_PATH],
		(
			"the mission strip runs on the tutorial board alone — every other board "
			+ "is an ordinary match and shows no hints"
		)
	)


## The tutorial board is the one map whose *shape* is a promise: the mission
## strip asks for select, move, capture, build and end turn on the first turn, so
## a board where the player cannot reach a neutral property or afford a unit on
## day one teaches steps it cannot let them perform. Nothing in the parser
## notices — it would load and play perfectly well as an ordinary duel.
func test_the_tutorial_board_can_answer_every_step_it_teaches() -> void:
	var map := MapData.load_from_file(MapCatalog.TUTORIAL_MAP_PATH, terrain_db)
	assert_not_null(map, "the tutorial board should parse")
	if map == null:
		return
	var game := GameState.create(map, unit_db)
	assert_not_null(game, "the tutorial board should build a GameState")
	if game == null:
		return
	var team: int = game.teams[0]
	assert_gt(_capturable_in_reach(game, team), 0, _step_failure("Capture"))
	assert_gt(_affordable_builds(game, team), 0, _step_failure("Build"))


## Every property `team` does not own that one of its capturing units can stop on
## this turn. Asked through MovementResolver rather than by counting steps, so it
## answers with the rules the board is actually played under.
func _capturable_in_reach(game: GameState, team: int) -> int:
	var found := 0
	for unit in game.units_of(team):
		if not unit.type.can_capture:
			continue
		var reach := MovementResolver.reachable(game, unit)
		for cell in reach.cells():
			if not reach.can_stop_at(cell):
				continue
			if game.map.terrain_at(cell).is_property and game.owner_at(cell) != team:
				found += 1
	return found


## How many units `team` could actually buy on day one. Every candidate goes
## through BuildCommand.validate, which owns the answer — funds, the terrain's
## roster and an occupied pad are all its call, not a second opinion's.
func _affordable_builds(game: GameState, team: int) -> int:
	var found := 0
	for cell in game.map.property_cells():
		for type in unit_db.all():
			if BuildCommand.new(team, type, cell).validate(game) == "":
				found += 1
	return found


func _step_failure(step: String) -> String:
	return (
		(
			"%s: the mission strip teaches %s on this board, so turn one has to let "
			% [
				MapCatalog.TUTORIAL_MAP_PATH.get_file(),
				step,
			]
		)
		+ "the player perform it"
	)


# --- helpers -----------------------------------------------------------------


## Every board the playability lints run on: the shipped roster and the fixtures.
## The menu-facing checks ask MapCatalog.paths() directly, because a fixture is
## deliberately not on the menu and owes it nothing.
func _board_paths() -> Array[String]:
	return MapCatalog.paths() + MapCatalog.fixture_paths()


func _maps() -> Array[MapData]:
	var maps: Array[MapData] = []
	for path in _board_paths():
		var map := MapData.load_from_file(path, terrain_db)
		if map != null:
			maps.append(map)
	return maps


func _name(map: MapData) -> String:
	return map.source_path.get_file()


## Every cell of one terrain, row-major, over the whole grid rather than the
## property cache — so it answers for shoals and reefs, which nobody captures,
## as readily as for HQs and ports.
func _cells_of_terrain(map: MapData, terrain_id: StringName) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			if map.terrain_at(cell).id == terrain_id:
				cells.append(cell)
	return cells


## What `team` opens the match holding, in funds. Priced off UnitType.cost, the
## same number every purchase and every AI valuation is denominated in.
func _starting_army_cost(map: MapData, team: int) -> int:
	var total := 0
	for entry: Dictionary in map.starting_units:
		if int(entry.team) != team:
			continue
		var type := unit_db.by_symbol(entry.symbol)
		if type != null:
			total += type.cost
	return total


## Every cell `move_class` can reach from `start`, `start` included.
func _flood(map: MapData, start: Vector2i, move_class: StringName) -> Dictionary:
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


## How many separate landmasses the map has. Infantry is the yardstick for the
## same reason _hq_connection_error uses it — the only class that enters every
## land terrain, so its components *are* the landmasses. With `with_shoals`
## false, beaches count as water, which is what makes the pair of counts
## comparable.
##
## A component of nothing but shoals is not a landmass, and is not counted in
## either pass: an offshore beach — a lander waypoint no land touches — exists
## only in the with-shoals graph, and counting it would read as a bridge that
## appeared out of open water, which is the opposite of what it is.
func _land_components(map: MapData, with_shoals: bool) -> int:
	var seen := {}
	var components := 0
	for y in map.height:
		for x in map.width:
			var start := Vector2i(x, y)
			if seen.has(start) or not _is_land(map, start, with_shoals):
				continue
			seen[start] = true
			var solid := map.terrain_at(start).id != SHOAL
			var queue: Array[Vector2i] = [start]
			while not queue.is_empty():
				var cell: Vector2i = queue.pop_back()
				for step in MovementResolver.DIRECTIONS:
					var next: Vector2i = cell + step
					if seen.has(next) or not map.in_bounds(next):
						continue
					if not _is_land(map, next, with_shoals):
						continue
					seen[next] = true
					solid = solid or map.terrain_at(next).id != SHOAL
					queue.append(next)
			if solid:
				components += 1
	return components


func _is_land(map: MapData, cell: Vector2i, with_shoals: bool) -> bool:
	var terrain := map.terrain_at(cell)
	if terrain == null or not terrain.is_passable(TerrainType.FOOT):
		return false
	return with_shoals or terrain.id != SHOAL


## The first property this board strands, as a sentence, or "" when every one of
## them is either walkable from an HQ or landable from a dock. Walkable is asked
## first because it is the ordinary case: on a board with no islands at all this
## returns before a single lander flood runs.
func _delivery_error(map: MapData) -> String:
	var walkable := {}
	for hq in _cells_of_terrain(map, HQ):
		walkable.merge(_flood(map, hq, TerrainType.FOOT))
	var beachable := {}
	for port in _cells_of_terrain(map, PORT):
		beachable.merge(_flood(map, port, TerrainType.LANDER))
	for cell in map.property_cells():
		if walkable.has(cell) or _has_landing_point(map, cell, beachable):
			continue
		return (
			"no lander can put a soldier on the %s at %s"
			% [map.terrain_at(cell).display_name, cell]
		)
	return ""


## Whether the landmass holding `cell` carries a beach or a dock a lander can
## sail to — the two terrains a landing craft may unload from, so the two that
## turn an island into ground an army can stand on.
func _has_landing_point(map: MapData, cell: Vector2i, beachable: Dictionary) -> bool:
	for ashore: Vector2i in _flood(map, cell, TerrainType.FOOT):
		if not beachable.has(ashore):
			continue
		var id := map.terrain_at(ashore).id
		if id == SHOAL or id == PORT:
			return true
	return false


## Flood fills from one HQ over every cell infantry can enter and reports the
## first HQ it fails to reach. Infantry is the yardstick because it is the only
## class that can cross every land terrain, so "unreachable on foot" means
## unreachable, full stop.
func _hq_connection_error(map: MapData) -> String:
	var hqs := _cells_of_terrain(map, HQ)
	if hqs.size() < 2:
		return ""  # the HQ-count assertion owns this case
	var seen := _flood(map, hqs[0], TerrainType.FOOT)
	for hq in hqs:
		if not seen.has(hq):
			return "no foot path from %s to %s" % [hqs[0], hq]
	return ""


## Checks the whole board against the 180-degree rotation, teams swapped, and
## reports the first cell that breaks it. Terrain, starting ownership and
## starting armies all have to mirror: any one of them alone is an edge.
func _mirror_error(map: MapData) -> String:
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var twin := map.mirrored(cell)
			if map.terrain_at(cell).id != map.terrain_at(twin).id:
				return (
					"%s is %s but %s is %s"
					% [
						cell,
						map.terrain_at(cell).id,
						twin,
						map.terrain_at(twin).id,
					]
				)
	var owners := map.initial_owners()
	for cell: Vector2i in owners:
		var twin: Vector2i = map.mirrored(cell)
		var twin_owner := int(owners.get(twin, MapData.NEUTRAL))
		if twin_owner != _opposing(map, int(owners[cell])):
			return (
				"%s starts owned by team %d, but %s does not mirror it" % [cell, owners[cell], twin]
			)
	var by_cell := {}
	for entry: Dictionary in map.starting_units:
		by_cell[entry.cell] = entry
	for entry: Dictionary in map.starting_units:
		var twin: Vector2i = map.mirrored(entry.cell)
		if not by_cell.has(twin):
			return "the unit on %s has no counterpart on %s" % [entry.cell, twin]
		var other: Dictionary = by_cell[twin]
		if other.symbol != entry.symbol or int(other.team) != _opposing(map, int(entry.team)):
			return "the unit on %s is not mirrored by the one on %s" % [entry.cell, twin]
	return ""


## The other side, read off the board's own roster rather than hardcoded as
## `3 - team`, so this says what it means while a mirrored board stays two-sided.
func _opposing(map: MapData, team: int) -> int:
	var roster := map.teams()
	var index := roster.find(team)
	return roster[(index + 1) % roster.size()]
