class_name BalanceHarness
extends RefCounted
## What every offline balance run needs before it can play anything: the
## databases a match is built from, the boards its flags name, and the seed each
## match is played on.
##
## The two runners were two copies of this — the same constants, the same
## database load and two map caches — and one copy is the same reason the match
## loop itself is shared (plan D1).
##
## It holds no run state and decides nothing: which boards a run plays and how
## many seeds it takes stay each runner's own business, because those are the
## flags two committed documents cite. Which seeds those are is
## BalanceMatchSchedule's and what an army is worth is BalanceMatchEngine's —
## every preset over the one loop shares both, so neither is restated here.
##
## Node-free, like the rest of tools/balance/.

## Paired seed count when a run's flags do not say. Each seed plays both seats.
const DEFAULT_SEEDS := 4

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB
var difficulty_db: DifficultyDB

var _maps: Dictionary = {}  # name -> MapData, resolved once and shared


static func load_default() -> BalanceHarness:
	var harness := BalanceHarness.new()
	harness.terrain_db = TerrainDB.load_default()
	harness.unit_db = UnitDB.load_default()
	harness.chart = load(DamageChart.DEFAULT_PATH)
	harness.commander_db = CommanderDB.load_default()
	harness.difficulty_db = DifficultyDB.load_default()
	return harness


## Validates a numeric flag's raw text before coercing it: an integer at least
## `min_value`, or -1 (never legal for any flag that asks) otherwise — so
## `--seeds=four` and `--days=-5` refuse out loud instead of the old
## `maxi(1, int(...))` quietly landing on 1.
##
## The three drivers share the check and keep their own refusal, because the
## message names the flag and the tool that read it.
static func int_flag(value: String, min_value: int) -> int:
	if not value.is_valid_int():
		return -1
	var parsed := value.to_int()
	return parsed if parsed >= min_value else -1


## A board by name — a fixture for the commander matrix, a shipped map for the
## difficulty ladder or the Lab — read once per run and shared across every match
## played on it. Safe to share: GameState.create copies the ownership it needs
## and never writes back, which is the same reason the battle scene hands one
## MapData around.
##
## Every tool comes through here, so "which board is <name>?" has one answer for
## the whole repo (MapCatalog.resolve), and a name nothing answers to is reported
## with the ones that do rather than failing somewhere further in.
func map_of(name: String) -> MapData:
	if _maps.has(name):
		var cached: MapData = _maps[name]
		return cached
	var path := MapCatalog.resolve(name)
	if path == "":
		push_error(
			(
				"balance: unknown map '%s'. Known: %s"
				% [name, ", ".join(MapCatalog.resolvable_names())]
			)
		)
		return null
	var map := MapData.load_from_file(path, terrain_db)
	if map == null:
		return null
	_maps[name] = map
	return map
