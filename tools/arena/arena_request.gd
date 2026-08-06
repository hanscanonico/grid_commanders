class_name ArenaRequest
extends RefCounted
## One arena shard, stated in full: which candidate profiles meet on which board,
## over which slice of the seed range.
##
## The input a tournament needs is "play *this* parameter vector", and a vector
## is a path to an `AIProfile`. It is deliberately a flag of its own rather than
## a third field in `BalanceSideSpec`: that grammar is shared with watch mode,
## names one of exactly three shipped tiers, and its own docstring says why a
## spec parsed two ways eventually disagrees (arena plan AR3).
##
## Parses and does not vet, like `MatchRequest`: whether a board exists and
## whether a profile loads are `ArenaShard`'s answers, at the point it needs
## them. Node-free and argument-taking, so the grammar is checked without a
## process to launch.

## The pools' first board: a duel that resolves inside `DEFAULT_DAYS` on every
## seed measured. A bare invocation may not land on `ironworks`, which
## `ArenaPools` measured *out* for reaching the match-level command cap at this
## horizon — a run that fails its own invariant is not a default.
const DEFAULT_MAP := "scrimmage"
const DEFAULT_SEEDS := 4
## The horizon that resolves (plan D6). A 20-day cap measures who was ahead
## early, and the two committed readings of the tier ladder disagree because of
## it; on a land board every seed routs by day 41 and a longer cap costs the same
## wall clock as a shorter one, so the arena asks the question that finishes.
const DEFAULT_DAYS := 100
const DEFAULT_OUT_ROOT := "reports/ai_arena"

## Keys a pairings file may carry, per level. A misspelt one is refused rather
## than ignored: `offset` for `seed_offset` would quietly play the wrong seeds
## and the shard would look fine.
const SHARD_KEYS: Array[String] = ["map", "seeds", "seed_offset", "days", "pairings"]
const PAIRING_KEYS: Array[String] = ["map", "red", "blue", "seeds", "seed_offset", "days"]

var map_name := DEFAULT_MAP
var red_path := ""
var blue_path := ""
## The shard file `--pairings=` named, or "" when the flags name one pairing.
var pairings_path := ""
var seeds := DEFAULT_SEEDS
var seed_offset := 0
var days := DEFAULT_DAYS
var out_dir := ""
## Empty while the request is good; otherwise why it is not.
var error := ""


## One matchup to play: two candidate profiles on one board over one slice of
## that board's seed range.
class Pairing:
	var map_name := ""
	var red_path := ""
	var blue_path := ""
	## Resolved by the request, which owns the defaults and what the shard file
	## overrides them with.
	var seeds := 0
	var seed_offset := 0
	var days := 0

	## Two identical vectors. The schedule plays such a matchup from one seat,
	## because swapping the seats of a mirror replays the identical match.
	func mirror() -> bool:
		return red_path == blue_path


## Reads the flags. Returns a request whose `error` says why it is unusable
## rather than quietly playing something else — a mistyped profile path that fell
## back to the shipped default would measure the tier the arena is trying to beat.
static func parse(args: PackedStringArray) -> ArenaRequest:
	var request := ArenaRequest.new()
	for arg in args:
		if arg.begins_with("--map="):
			request.map_name = arg.get_slice("=", 1).strip_edges()
		elif arg.begins_with("--red-profile="):
			request.red_path = arg.get_slice("=", 1).strip_edges()
		elif arg.begins_with("--blue-profile="):
			request.blue_path = arg.get_slice("=", 1).strip_edges()
		elif arg.begins_with("--pairings="):
			request.pairings_path = arg.get_slice("=", 1).strip_edges()
		elif arg.begins_with("--seeds="):
			request.seeds = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--seed-offset="):
			request.seed_offset = maxi(0, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--days="):
			request.days = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--out="):
			request.out_dir = arg.get_slice("=", 1).strip_edges()
		else:
			request.error = "unknown flag '%s'" % arg
			return request
	request._check()
	return request


## The matches this shard is made of: the file's pairings, or the single one the
## flags name. `text` is the shard file's contents and is ignored when no file
## was named — reading it is the driver's, so the grammar stays testable without
## a disk.
func pairings(text: String) -> Array[Pairing]:
	if pairings_path == "":
		return [_pairing(map_name, red_path, blue_path, seeds, seed_offset, days)]
	var json := JSON.new()
	if json.parse(text) != OK:
		error = (
			"%s: %s (line %d)" % [pairings_path, json.get_error_message(), json.get_error_line()]
		)
		return []
	if not (json.data is Dictionary):
		error = "%s is not a JSON object" % pairings_path
		return []
	var shard: Dictionary = json.data
	var unknown := _unknown_key(shard, SHARD_KEYS)
	if unknown != "":
		error = "%s: unknown key '%s'" % [pairings_path, unknown]
		return []
	if not (shard.get("pairings") is Array):
		error = "%s: 'pairings' must be a list of {red, blue}" % pairings_path
		return []
	return _read_pairings(shard)


## Where this shard's record goes, derived from the spec and never from a clock —
## the Lab's rule, so rerunning a shard overwrites its own directory and two runs
## of one question are diffable.
func run_name() -> String:
	var parts: Array[String] = []
	if pairings_path != "":
		parts.append(pairings_path.get_file().trim_suffix(".json"))
	else:
		parts.append_array([map_name, slug(red_path), "vs", slug(blue_path)])
		parts.append("s%d" % seeds)
		if seed_offset > 0:
			parts.append("o%d" % seed_offset)
		parts.append("d%d" % days)
	parts.append(digest())
	return "_".join(parts)


## The whole spec, digested — what a name spelled out of readable parts leaves
## out. A candidate is a path and its slug is only the filename, so the
## generation layout a search writes (`g1/c1.tres`, `g2/c1.tres`) names one
## directory between the two and the second run overwrites the first's records;
## a shard file is named the same way. `balance_pool.py` keys its shards on a
## digest of the arguments for exactly this reason, and naming the dimensions by
## hand is what such a key must never do — this one covers every field the
## request carries and cannot forget the next.
func digest() -> String:
	var spec := (
		"%s|%s|%s|%s|%d|%d|%d"
		% [pairings_path, map_name, red_path, blue_path, seeds, seed_offset, days]
	)
	return spec.sha1_text().substr(0, 8)


func artifact_dir() -> String:
	return out_dir if out_dir != "" else DEFAULT_OUT_ROOT.path_join(run_name())


## A candidate's short name: the profile's filename. What a record is read by, so
## two profiles in one run should not share one.
static func slug(profile_path: String) -> String:
	return profile_path.get_file().trim_suffix(".tres")


## A path spelled the way the engine reads one, or "" when it leaves the project.
## Everything the arena reads or writes lives under the project root — a searched
## profile sits beside the run that wrote it, under `reports/` — and `load()`
## cannot reach outside it at all.
static func project_path(path: String) -> String:
	if path.begins_with("/"):
		return ""
	return path if path.contains("://") else "res://".path_join(path)


func _check() -> void:
	if pairings_path != "" and (red_path != "" or blue_path != ""):
		error = "--pairings= names its own profiles; drop --red-profile/--blue-profile"
	elif pairings_path == "" and (red_path == "" or blue_path == ""):
		error = "a side is a profile: --red-profile=<path.tres> --blue-profile=<path.tres>"
	elif out_dir != "":
		var resolved := BalanceReportWriter.resolve_out(out_dir)
		if resolved == "":
			error = (
				"--out is a directory under %s/ (got '%s')"
				% [BalanceReportWriter.REPORTS_ROOT, out_dir]
			)
		out_dir = resolved


func _read_pairings(shard: Dictionary) -> Array[Pairing]:
	var result: Array[Pairing] = []
	var entries: Array = shard["pairings"]
	for entry: Variant in entries:
		if not (entry is Dictionary):
			error = "%s: a pairing is an object with 'red' and 'blue'" % pairings_path
			return []
		var pairing: Dictionary = entry
		var unknown := _unknown_key(pairing, PAIRING_KEYS)
		if unknown != "":
			error = "%s: unknown key '%s' in a pairing" % [pairings_path, unknown]
			return []
		var red: String = str(pairing.get("red", ""))
		var blue: String = str(pairing.get("blue", ""))
		if red == "" or blue == "":
			error = "%s: a pairing needs both 'red' and 'blue'" % pairings_path
			return []
		result.append(
			_pairing(
				str(_setting(pairing, shard, "map", map_name)),
				red,
				blue,
				int(_setting(pairing, shard, "seeds", seeds)),
				int(_setting(pairing, shard, "seed_offset", seed_offset)),
				int(_setting(pairing, shard, "days", days))
			)
		)
	if result.is_empty():
		error = "%s: no pairings to play" % pairings_path
	return result


## Nearest wins: a pairing's own setting, else the file's default for the shard,
## else what the command line asked for.
static func _setting(
	pairing: Dictionary, shard: Dictionary, key: String, fallback: Variant
) -> Variant:
	if pairing.has(key):
		return pairing[key]
	return shard.get(key, fallback)


static func _unknown_key(source: Dictionary, allowed: Array[String]) -> String:
	for key: Variant in source:
		if not (str(key) in allowed):
			return str(key)
	return ""


static func _pairing(
	map_name: String, red: String, blue: String, seeds: int, offset: int, days: int
) -> Pairing:
	var pairing := Pairing.new()
	pairing.map_name = map_name
	pairing.red_path = red
	pairing.blue_path = blue
	pairing.seeds = maxi(1, seeds)
	pairing.seed_offset = maxi(0, offset)
	pairing.days = maxi(1, days)
	return pairing
