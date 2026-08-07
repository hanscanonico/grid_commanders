class_name ArenaShard
extends RefCounted
## Plays a shard's pairings and hands back one record per match.
##
## A third preset over `BalanceMatchEngine`, never a second engine (balance plan
## D1): the loop is the engine's, the seeds and seatings are
## `BalanceMatchSchedule`'s, and all that is new is what each seat's planner
## weighs with — an `AIProfile` loaded from a path, rather than one of the three
## tiers `BalanceSideSpec` can name.
##
## Commanders are **neutral by default**, so `doctrine_weight` is inert and a
## candidate is measured as a planner rather than as a general (plan AR3, R8).
## A pairing may seat one per side — R8 was a scope choice, and a campaign that
## wants doctrines and powers live says so per pairing while every spec that
## says nothing keeps the commander-free measurement it always was.
##
## A record carries the `Outcome` facts a fitness function reads and nothing
## else: no timeline, no command log. At arena volume the telemetry is the
## dominant write cost, and a pairing worth a closer look is re-run through
## `make balance-sim` with the full instruments on — which is what the two
## presets being one engine buys.
##
## Node-free, so GUT plays a shard without a process.

var error := ""

var _terrain_db: TerrainDB
var _unit_db: UnitDB
var _chart: DamageChart
var _commander_db: CommanderDB
var _maps: Dictionary = {}  # name -> MapData, loaded once and shared
var _profiles: Dictionary = {}  # path -> AIProfile, loaded once and shared


func _init(
	p_terrain_db: TerrainDB, p_unit_db: UnitDB, p_chart: DamageChart, p_commander_db: CommanderDB
) -> void:
	_terrain_db = p_terrain_db
	_unit_db = p_unit_db
	_chart = p_chart
	_commander_db = p_commander_db


## Every match of every pairing, in play order. Stops at the first one it cannot
## play, with `error` saying why: a shard that skipped a pairing would score its
## candidate over fewer matches than its rivals', and nothing downstream could
## see that it had.
func play(pairings: Array) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for pairing: ArenaRequest.Pairing in pairings:
		var map := board(pairing.map_name)
		if map == null:
			return []
		if profile(pairing.red_path) == null or profile(pairing.blue_path) == null:
			return []
		if commander(pairing.red_co) == null or commander(pairing.blue_co) == null:
			return []
		var slots: Array = BalanceMatchSchedule.slots(
			pairing.map_name, pairing.seeds, pairing.seed_offset, pairing.mirror()
		)
		for slot: BalanceMatchSchedule.Slot in slots:
			var swapped := slot.seat == 1
			var record := _play(
				map,
				pairing,
				slot.seed_val,
				slot.seat,
				pairing.blue_path if swapped else pairing.red_path,
				pairing.red_path if swapped else pairing.blue_path,
				pairing.blue_co if swapped else pairing.red_co,
				pairing.red_co if swapped else pairing.blue_co
			)
			if record.is_empty():
				return []
			records.append(record)
	return records


## The candidate at `path`, loaded once per shard. Null with `error` set when the
## path names nothing, leaves the project, or holds something that is not an
## `AIProfile` — a run that quietly fell back to the shipped defaults would
## measure the very tier the arena is trying to beat.
func profile(path: String) -> AIProfile:
	if _profiles.has(path):
		var cached: AIProfile = _profiles[path]
		return cached
	var res_path := ArenaRequest.project_path(path)
	if res_path == "":
		error = "profile '%s' is outside the project; use a path under it" % path
		return null
	if not ResourceLoader.exists(res_path):
		error = "no profile at '%s'" % res_path
		return null
	var loaded: Resource = load(res_path)
	if not (loaded is AIProfile):
		error = "'%s' is not an AIProfile" % res_path
		return null
	var candidate: AIProfile = loaded
	_profiles[path] = candidate
	return candidate


## The commander a seat carries: the neutral one for "", otherwise the roster's
## by id — refused, never guessed, for an id it does not know. `CommanderDB`'s
## own lookup deliberately falls back to neutral for a missing general, which
## here would quietly measure the commander-free matchup while reporting the
## seated one (the Lab's side grammar refuses the same way).
func commander(id_text: String) -> CommanderType:
	if id_text == "":
		return CommanderType.neutral()
	var id := StringName(id_text)
	if not _commander_db.has(id):
		error = "unknown commander '%s'" % id_text
		return null
	return _commander_db.by_id(id)


## A board by name, read once and shared across every match played on it. Safe to
## share: `GameState.create` copies the ownership it needs and never writes back.
func board(map_name: String) -> MapData:
	if _maps.has(map_name):
		var cached: MapData = _maps[map_name]
		return cached
	var path := MapCatalog.resolve(map_name)
	if path == "":
		error = (
			"unknown map '%s'. Known: %s" % [map_name, ", ".join(MapCatalog.resolvable_names())]
		)
		return null
	var map := MapData.load_from_file(path, _terrain_db)
	if map == null:
		error = "cannot read the board '%s'" % path
		return null
	_maps[map_name] = map
	return map


## Matches whose hard invariants did not hold: a rejected command, or a match
## that would not resolve. Neither is a result — it is the AI and the rules
## disagreeing — so a run that produced any of them reports as failed.
##
## What counts as one is `ArenaFitness`'s to say, asked here rather than
## restated: a second reading of it would let the run's exit code and the
## leaderboard's `invalid` count drift apart.
static func flawed(records: Array[Dictionary]) -> int:
	var count := 0
	for record in records:
		if ArenaFitness.result_of(record) == ArenaFitness.Result.INVALID:
			count += 1
	return count


func _play(
	map: MapData,
	pairing: ArenaRequest.Pairing,
	seed_val: int,
	seat: int,
	red_path: String,
	blue_path: String,
	red_co: String,
	blue_co: String
) -> Dictionary:
	var setup := BalanceMatchEngine.Setup.new()
	setup.map = map
	setup.unit_db = _unit_db
	setup.chart = _chart
	setup.seed_val = seed_val
	setup.days_cap = pairing.days
	setup.match_id = _match_id(pairing.map_name, red_path, blue_path, red_co, blue_co, seed_val)
	setup.commanders = {1: commander(red_co), 2: commander(blue_co)}
	# One planner per side, each carrying its own candidate vector. That is the
	# whole of what this preset adds: the engine already demands a controller and
	# a commander per seat, and the pairing owns what both of them are.
	setup.planners = {
		1: AIController.new(_unit_db, profile(red_path)),
		2: AIController.new(_unit_db, profile(blue_path)),
	}
	var outcome := BalanceMatchEngine.play(setup)
	if outcome.state == null:
		error = "could not build a match on '%s' (%s)" % [pairing.map_name, outcome.termination]
		return {}
	var state := outcome.state
	return {
		"match_id": setup.match_id,
		"map": pairing.map_name,
		"seed": seed_val,
		"seat": seat,
		"red": red_path,
		"blue": blue_path,
		"red_co": red_co if red_co != "" else str(CommanderType.NEUTRAL_ID),
		"blue_co": blue_co if blue_co != "" else str(CommanderType.NEUTRAL_ID),
		"winner": outcome.winner,
		"termination": outcome.termination,
		"day_ended": outcome.day_ended,
		"commands": outcome.commands,
		"rejected": outcome.rejected,
		"cap_stall": outcome.cap_stall,
		"turn_cap_hits": outcome.turn_cap_hits,
		"red_units": state.units_of(1).size(),
		"blue_units": state.units_of(2).size(),
		"red_props": state.properties_of(1).size(),
		"blue_props": state.properties_of(2).size(),
		"red_funds": int(state.funds.get(1, 0)),
		"blue_funds": int(state.funds.get(2, 0)),
		"red_army_value": BalanceMatchEngine.army_value(state, 1),
		"blue_army_value": BalanceMatchEngine.army_value(state, 2),
	}


## Names the match by what it is: the board, the two seated candidates in seat
## order — each carrying its commander when one is seated — and the seed.
## Derived from the spec like the Lab's ids, so the same shard rerun writes the
## same ones.
static func _match_id(
	map_name: String,
	red_path: String,
	blue_path: String,
	red_co: String,
	blue_co: String,
	seed_val: int
) -> String:
	return (
		"%s#%s_vs_%s#s%d"
		% [
			map_name,
			ArenaRequest.side_label(red_path, red_co),
			ArenaRequest.side_label(blue_path, blue_co),
			seed_val,
		]
	)
