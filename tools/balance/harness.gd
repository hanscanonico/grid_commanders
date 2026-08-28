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

## What `take` did with an argument: consumed it, refused the run over it, or
## left it to the driver's own arms.
enum { NOT_MINE, TAKEN, REFUSED }

## Every flag `take` knows. A sample lists the ones its own driver offers, so
## sharing the loop can never widen a grammar — `run_mobile_soak.gd` and
## `run_commander_balance.gd` have no `--seed-offset=` and keep none.
const SAMPLE_FLAGS: Array[String] = ["--seeds", "--seed-offset", "--days", "--out"]

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


## `--fog=on`, `--fog=off`: 1 or 0, or -1 with the refusal pushed. A switch is
## the one flag shape where a typo has no shape of its own — anything that is
## not "on" reads as off — so it is refused by name like every number beside it.
static func bool_flag(tool_name: String, flag: String, value: String) -> int:
	var text := value.strip_edges().to_lower()
	if text in ["on", "true", "1"]:
		return 1
	if text in ["off", "false", "0"]:
		return 0
	push_error("%s: %s is on/true/1 or off/false/0 (got '%s')" % [tool_name, flag, value])
	return -1


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


## The sample one offline run plays: how many seeds, from where in the range,
## under what day horizon, writing where. Every default is the caller's — the
## widths and horizons two committed documents cite are each driver's own — and
## so is the `--out=` fallback and the `out_flag` finish, which is why `out_dir`
## is the raw text and nothing here resolves it.
class SampleFlags:
	extends RefCounted

	var seeds := 0
	var seed_offset := 0
	var days_cap := 0
	var out_dir := ""
	var offers: Array[String] = []


## A sample with this driver's own defaults and this driver's own grammar.
## Refuses a flag name nothing reads rather than quietly never taking it.
static func sample(seeds: int, days_cap: int, offers: Array[String]) -> SampleFlags:
	for flag in offers:
		if not flag in SAMPLE_FLAGS:
			push_error("balance: '%s' is not a sample flag" % flag)
	var flags := SampleFlags.new()
	flags.seeds = seeds
	flags.days_cap = days_cap
	flags.offers = offers
	return flags


## The loop arm six offline drivers each spelled: the four flags that state a
## sample, validated by the three checks above and each followed by the same
## refusal. A driver's own flags go in the NOT_MINE arm, so what it lost is the
## copy rather than its grammar.
static func take(flags: SampleFlags, tool_name: String, arg: String) -> int:
	if flags.offers.has("--seeds") and arg.begins_with("--seeds="):
		flags.seeds = positive_flag(tool_name, "--seeds", arg.get_slice("=", 1))
		return REFUSED if flags.seeds < 0 else TAKEN
	if flags.offers.has("--seed-offset") and arg.begins_with("--seed-offset="):
		flags.seed_offset = count_flag(tool_name, "--seed-offset", arg.get_slice("=", 1))
		return REFUSED if flags.seed_offset < 0 else TAKEN
	if flags.offers.has("--days") and arg.begins_with("--days="):
		flags.days_cap = positive_flag(tool_name, "--days", arg.get_slice("=", 1))
		return REFUSED if flags.days_cap < 0 else TAKEN
	if flags.offers.has("--out") and arg.begins_with("--out="):
		flags.out_dir = arg.get_slice("=", 1).strip_edges()
		return TAKEN
	return NOT_MINE


static func _int_flag(value: String, min_value: int) -> int:
	if not value.is_valid_int():
		return -1
	var parsed := value.to_int()
	return parsed if parsed >= min_value else -1


## Validates a numeric flag's raw text before coercing it: an integer at least
## `min_value`, or -1 (never legal for any flag that asks) otherwise — so
## `--seeds=four` and `--days=-5` refuse out loud instead of the old
## `maxi(1, int(...))` quietly landing on 1. The message names the flag and the
## tool that read it, so a driver passes both rather than spelling the block
## again.
static func _bounded_flag(
	tool_name: String, flag: String, value: String, min_value: int, shape: String
) -> int:
	var parsed := _int_flag(value.strip_edges(), min_value)
	if parsed < 0:
		push_error("%s: %s must be %s (got '%s')" % [tool_name, flag, shape, value])
	return parsed
