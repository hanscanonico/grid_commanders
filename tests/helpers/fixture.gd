class_name Fixture
extends RefCounted
## The board a test plays on, in one call: `Fixture.state("[terrain]\n..\n...")`.
##
## Thirty-nine of the suite's test scripts opened by writing the same eight lines
## — load three databases in `before_each`, then a `_state(map_text)` that parses
## the board and builds a GameState from it — and about twenty of those were
## byte-identical to each other. That is one fixture bug away from thirty-nine
## edits, and it is the first thing anybody writing a new test copies.
##
## Node-free like everything else the suite is allowed to touch, so it is a
## `RefCounted` with statics and no scene, no `Node` and no autoload.
##
## The databases are built once for the process, and that is safe rather than
## merely convenient: `TerrainDB.load_default()` and `UnitDB.load_default()`
## reach their `.tres` files through `load()`, which the engine caches, so every
## test in the suite has *always* been handed the same `TerrainType` and
## `UnitType` instances. Caching the registries that index them shares nothing
## the process was not already sharing — it only stops each test re-walking two
## directories. What a test may still never do is write to one of those shared
## resources; nothing in the suite does, and a test that wants a doctored unit
## type builds its own rather than editing the shipped one.

## COM-206: `CombatResolver._luck` always draws from `state.rng`, and
## `GameState.rng`'s own doc says seed it explicitly for a deterministic test —
## unseeded, a fixture-built state drew combat luck from the engine's own
## entropy and made a test's outcome depend on when it ran. Every board this
## builds seeds the same way, so a test that wants a *different* seed sets
## `state.rng.seed` itself after calling; a later assignment fully re-seeds
## `RandomNumberGenerator`'s stream rather than mixing into it.
const DEFAULT_SEED := 1701

static var _terrain_db: TerrainDB
static var _unit_db: UnitDB
static var _commander_db: CommanderDB
static var _chart: DamageChart


## A match on `map_text`, parsed and built exactly as `MapData.parse` and
## `GameState.create` do it for the game. `commanders` seats one general per
## team by id — `{1: &"alina_ward", 2: &"viktor_draeg"}` — and an empty
## dictionary leaves both sides neutral, which is what most boards want.
static func state(map_text: String, commanders: Dictionary = {}) -> GameState:
	var map := MapData.parse(map_text, terrain_db())
	if map == null:
		return null  # MapData.parse has already named the line it refused
	var game := GameState.create(map, unit_db(), chart())
	if game == null:
		push_error("Fixture: the board does not build a GameState:\n%s" % map_text)
		return null
	game.rng.seed = DEFAULT_SEED
	for team: int in commanders:
		game.set_commander(team, commander_db().by_id(commanders[team]))
	return game


## The same match, on a board that lives on disk — `MapData.load_from_file`
## rather than `parse`, and `map_path` set to where it came from, which is what
## a save, a replay and a resume all read the board back through.
static func state_from_file(path: String, commanders: Dictionary = {}) -> GameState:
	var map := MapData.load_from_file(path, terrain_db())
	if map == null:
		push_error("Fixture: no board at %s" % path)
		return null
	var game := GameState.create(map, unit_db(), chart())
	if game == null:
		push_error("Fixture: the board at %s does not build a GameState" % path)
		return null
	game.rng.seed = DEFAULT_SEED
	game.map_path = path
	for team: int in commanders:
		game.set_commander(team, commander_db().by_id(commanders[team]))
	return game


## `[Vector2i(0, 0), Vector2i(1, 0)]` typed as the commands take it. An untyped
## Array literal is what a test writes and `Array[Vector2i]` is what a path is.
static func path(cells: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for cell: Vector2i in cells:
		typed.append(cell)
	return typed


## `["--map=dustbowl", "--seed=3"]` typed as `CmdArgs` and `MatchRequest` take
## the command line: a `PackedStringArray`, never the bare Array a test writes.
static func args(list: Array) -> PackedStringArray:
	var typed := PackedStringArray()
	for item: String in list:
		typed.append(item)
	return typed


## Banks `team`'s Command Power cost and fires it — `team = 0` (no team plays
## at 0) means "whichever team is on turn", the two doctrines that fire mid
## sequence rather than for the seated side. Returns `PowerCommand.validate`'s
## error so the caller keeps its own assertion; `Fixture` asserts nothing; it
## has no `GutTest` to assert with.
static func fire_power(state: GameState, team: int = 0) -> String:
	var acting := team if team != 0 else state.current_team
	state.add_charge(acting, state.commander_of(acting).power_cost)
	var command := PowerCommand.new()
	var error := command.validate(state)
	if error == "":
		command.apply(state)
	return error


static func terrain_db() -> TerrainDB:
	if _terrain_db == null:
		_terrain_db = TerrainDB.load_default()
	return _terrain_db


static func unit_db() -> UnitDB:
	if _unit_db == null:
		_unit_db = UnitDB.load_default()
	return _unit_db


static func commander_db() -> CommanderDB:
	if _commander_db == null:
		_commander_db = CommanderDB.load_default()
	return _commander_db


static func chart() -> DamageChart:
	if _chart == null:
		_chart = load("res://data/damage_chart.tres")
	return _chart
