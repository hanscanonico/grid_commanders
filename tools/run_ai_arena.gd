extends SceneTree
## The AI Arena's match driver: two arbitrary candidate AIs, played against each
## other headlessly, written down as one JSON record per match.
##
## A sibling of run_balance_sim.gd and a **third preset over the one match
## loop** (balance plan D1), not a second engine: same `BalanceMatchEngine`, same
## seeds, same both-seats pairing. What it adds is the one input a tournament
## needs and the Lab has no grammar for — "play *this* parameter vector". A Lab
## side is `<commander>:<tier>`, so it can be exactly one of the three shipped
## profiles; a candidate is a path to a fourth (arena plan AR3).
##
## Usage (headless; see `make ai-arena`):
##   Godot --headless --path . -s res://tools/run_ai_arena.gd -- [flags]
##     --red-profile=<path.tres>  the candidate in the first seat
##     --blue-profile=<path.tres> and the one in the second. Project-relative or
##                                res://-spelled; a searched profile lives under
##                                reports/ beside the run that wrote it.
##     --pairings=<file.json>     play a whole shard instead: every pairing the
##                                file names, which is one process's unit of work
##     --red-co= / --blue-co=     seat a commander on a side by id (default
##                                neutral, R8's commander-free measurement); a
##                                shard file says `red_co`/`blue_co` per pairing
##     --map=scrimmage            board for pairings that name none
##     --seeds=4                  paired seeds per pairing, both seats each
##     --seed-offset=8            skip the first N seeds of that range, so a pool
##                                can split one pairing across processes without
##                                deriving the seeds itself
##     --days=100                 day cap; the default is the horizon that
##                                resolves (plan D6)
##     --out=reports/...          output directory (default reports/ai_arena/<run>)
##
## A shard file is the flags, once per pairing:
##
##   {"map": "scrimmage", "seeds": 4, "days": 100, "pairings": [
##     {"red": "data/ai/default.tres", "blue": "reports/arena/gen1/c7.tres"},
##     {"red": "data/ai/hard.tres",    "blue": "reports/arena/gen1/c7.tres"}]}
##
## Nearest setting wins: a pairing's own, then the file's, then the flags'.
##
## Writes exactly one artifact, `matches.json` — an array of one record per
## match, carrying the `Outcome` facts a fitness function reads and nothing else.
## No CSV, no timeline, no commands.jsonl: at arena volume the telemetry is the
## dominant write cost and answers a question nobody is asking, and a single
## interesting pairing is re-run through `make balance-sim` with the full
## instruments on — which is the point of the two being one engine.
##
## Commanders are neutral by default, so `doctrine_weight` is inert and a
## candidate is measured as a planner rather than as a general (plan R8); a
## pairing that seats generals measures it with doctrines and powers live.
##
## Determinism: same board, seed and profiles => the same match and the same
## record, and the Lab plays that same match from the same seed —
## BalanceMatchSchedule owns the range both read.

const DAMAGE_CHART_PATH := "res://data/damage_chart.tres"
const RECORD_FILE := "matches.json"


func _init() -> void:
	var request := ArenaRequest.parse(OS.get_cmdline_user_args())
	if request.error != "":
		_refuse(request.error)
		return
	var text := _shard_text(request)
	if request.error != "":
		_refuse(request.error)
		return
	var pairings: Array = request.pairings(text)
	if request.error != "":
		_refuse(request.error)
		return
	print("ai-arena: %d pairing(s) to play" % pairings.size())
	var shard := ArenaShard.new(
		TerrainDB.load_default(),
		UnitDB.load_default(),
		load(DAMAGE_CHART_PATH),
		CommanderDB.load_default()
	)
	var records := shard.play(pairings)
	if shard.error != "":
		_refuse(shard.error)
		return
	if not _write(request, records):
		quit(1)
		return
	var flawed := ArenaShard.flawed(records)
	if flawed > 0:
		push_error("ai-arena: %d match(es) rejected a command or would not resolve" % flawed)
	quit(1 if flawed > 0 else 0)


## The shard file's contents, or "" when the flags name one pairing instead. A
## file that cannot be read is a refusal rather than an empty shard: a run that
## played nothing and wrote an empty record file would resume as complete.
func _shard_text(request: ArenaRequest) -> String:
	if request.pairings_path == "":
		return ""
	var path := ArenaRequest.project_path(request.pairings_path)
	if path == "" or not FileAccess.file_exists(path):
		request.error = "cannot read the shard file '%s'" % request.pairings_path
		return ""
	return FileAccess.get_file_as_string(path)


func _write(request: ArenaRequest, records: Array[Dictionary]) -> bool:
	var out := request.artifact_dir()
	var dir := BalanceReportWriter.prepare_dir(out)
	if dir == "":
		return false
	if not BalanceReportWriter.write_json(dir.path_join(RECORD_FILE), records):
		push_error("ai-arena: failed to write %s/%s" % [out, RECORD_FILE])
		return false
	print("ai-arena: wrote %d match records to %s/%s" % [records.size(), out, RECORD_FILE])
	return true


func _refuse(reason: String) -> void:
	push_error("ai-arena: %s" % reason)
	quit(2)
