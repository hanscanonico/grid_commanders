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
## The refusal itself is `positive_flag` / `count_flag` below: the message names
## the flag and the tool that read it, so a driver passes both rather than
## spelling the block again.
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


## `--seeds=`, `--days=`, `--appends=`: an integer of at least 1, or -1 with the
## refusal already pushed. `tool_name` and `flag` are what the message names, so
## a driver keeps its own vocabulary and loses only the block that spelled the
## same check a seventh time.
static func positive_flag(tool_name: String, flag: String, value: String) -> int:
	return _bounded_flag(tool_name, flag, value, 1, "a positive integer")


## The non-negative variant — `--seed-offset=`, `--seed=` — where 0 is a legal
## answer and only a negative or a non-number is not.
static func count_flag(tool_name: String, flag: String, value: String) -> int:
	return _bounded_flag(tool_name, flag, value, 0, "a non-negative integer")


## `--out=`: the directory a run may write to, or "" with the refusal pushed.
## BalanceReportWriter.resolve_out is still the single authority on where that
## is; what this adds is the one wording every driver refuses a stray path with.
static func out_flag(tool_name: String, value: String) -> String:
	var resolved := BalanceReportWriter.resolve_out(value.strip_edges())
	if resolved == "":
		push_error(
			(
				"%s: --out is a directory under %s/ (got '%s')"
				% [tool_name, BalanceReportWriter.REPORTS_ROOT, value]
			)
		)
	return resolved


static func _bounded_flag(
	tool_name: String, flag: String, value: String, min_value: int, shape: String
) -> int:
	var parsed := int_flag(value.strip_edges(), min_value)
	if parsed < 0:
		push_error("%s: %s must be %s (got '%s')" % [tool_name, flag, shape, value])
	return parsed
