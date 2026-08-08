extends SceneTree
## The Balance Lab: two independent AIs on any shipped board, each side carrying
## any commander at any difficulty tier, over N seeded matches with both seats
## swapped — recording not just who won but a turn-by-turn timeline of how.
##
## It is the general instrument the two shipped presets are special cases of.
## `make commander-balance` and `make difficulty-check` still answer the two
## standing documents' exact questions with their exact flags; this answers
## everything in between — "why does Gideon crush Cass on ironworks?", "is this
## board fair?", "is Difficult worth a commander handicap?" — and any matchup it
## can score it can also *show*, because the same spec and seed boot the real
## battle scene with both sides AI-driven (`make balance-watch`).
##
## Usage (headless; see `make balance-sim`):
##   Godot --headless --path . -s res://tools/run_balance_sim.gd -- [flags]
##     --map=ironworks           any shipped map, or a balance fixture
##                               (clash/ridge/combined/holdings/channel);
##                               default first_steps
##     --red=<co>:<tier>         a side spec — commander id or `none`, tier
##     --blue=<co>:<tier>        easy/normal/hard/brutal. Default none:normal.
##     --seeds=10                paired seed count (default 4)
##     --seed=1003               one pinned seed instead, both seats played —
##                               `make balance-watch` replays the seat-0 row
##     --seed-offset=8           skip the first N seeds of that range, so a
##                               driver can split one matchup's seeds across
##                               processes without deriving the seeds itself
##                               (tools/balance_pool.py)
##     --days=20                 day cap before the match is scored on points
##     --sweep=commanders        one free axis per run (plan D5):
##     --sweep=maps                commanders — every commander vs --blue at --tier
##     --sweep=tiers              maps       — --red vs --blue on every shipped board
##                                tiers      — the adjacent-tier ladder, both sides
##                                             carrying --commander
##     --tier=normal             the tier both sides play at, for --sweep=commanders
##     --commander=alina_ward    the doctrine both sides carry, for --sweep=tiers
##     --no-commands             skip commands.jsonl (a big sweep's is large)
##     --replays                 also write a watchable replay per match
##     --out=reports/...         output directory (default reports/balance_sim/<run>)
##
## Writes five files (four with --no-commands), all gitignored with reports/:
##   matches.csv   — one row per match
##   timeline.csv  — one row per side per played turn, keyed by match_id
##   commands.jsonl— one line per applied command (plan Q3)
##   summary.json  — the aggregates and flags
##   report.html   — the same numbers, drawn (plan BS4)
##
## With `--replays`, a `replays/` directory beside them holds one file per match,
## named by match id. `commands.jsonl` describes what happened and this can be
## re-issued, which is the difference: a suspicious row becomes
## `make replay REPLAY=<that file>` (replay plan D7).
##
## Determinism: same map + seed + side specs => byte-identical rows, because the
## RNG is seeded, the AI is lookahead-free and RNG-free, and nothing here reads
## the clock. `planning_ms` in the timeline is the one exception and is excluded
## from the determinism test for exactly that reason.

const DEFAULT_OUT_ROOT := "reports/balance_sim"
const DEFAULT_MAP := "first_steps"

## Adjacent tiers only, matching the difficulty ladder: each pairing asks whether
## one step up is a real step. Higher tier second.
const TIER_LADDER: Array = [[&"easy", &"normal"], [&"normal", &"hard"]]

const MATCH_COLUMNS: Array[String] = [
	"match_id",
	"sweep_axis",
	"sweep_value",
	"map",
	"seed",
	"seat",
	"mirror",
	"naval",
	"red_commander",
	"red_tier",
	"blue_commander",
	"blue_tier",
	"subject_side",
	"subject_won",
	"winner",
	"termination",
	"day_ended",
	"commands",
	"rejected",
	"cap_stall",
	"turn_cap_hits",
	"red_units",
	"blue_units",
	"red_props",
	"blue_props",
	"red_funds",
	"blue_funds",
	"red_army_value",
	"blue_army_value",
	"red_powers",
	"blue_powers",
]

var _harness: BalanceHarness

var _map_name := DEFAULT_MAP
var _red_text := BalanceSideSpec.DEFAULT_TEXT
var _blue_text := BalanceSideSpec.DEFAULT_TEXT
var _sweep := ""
var _sweep_tier := Difficulty.DEFAULT_ID
var _sweep_commander := CommanderType.NEUTRAL_ID
var _seed_count := BalanceHarness.DEFAULT_SEEDS
## Where in the seed range `--seeds=` starts counting. 0 unless a shard of a
## parallel run asked for a later slice of it.
var _seed_offset := 0
## -1 unless `--seed=` pinned one, in which case the run is that single seed —
## the same one a watch-mode launch replays.
var _pinned_seed := -1
var _days_cap := BalanceMatchEngine.DEFAULT_DAYS
var _out_dir := ""
var _log_commands := true
var _write_replays := false
## Where this run's artifacts go, resolved once at startup rather than at write
## time: the replays are opened while the matches are being played.
var _artifact_dir := ""


## One match to play: which board, which seat holds which spec, and what swept
## value the row belongs to.
class Job:
	var value := ""
	var map_name := ""
	var red: BalanceSideSpec
	var blue: BalanceSideSpec
	## The spec the swept value names, whose side-normalized win rate is the
	## question the run is asking. Its seat alternates with `seat`.
	var subject_side := "red"
	var seat := 0
	var seed_val := 0
	var mirror := false


func _init() -> void:
	_harness = BalanceHarness.load_default()
	if not _parse_args():
		quit(2)
		return
	_artifact_dir = _out_dir if _out_dir != "" else DEFAULT_OUT_ROOT.path_join(_run_name())
	var jobs := _build_jobs()
	if jobs.is_empty():
		push_error("balance-sim: nothing to play")
		quit(2)
		return
	var recorder := BalanceMatchRecorder.new(_log_commands)
	var matches := _run(jobs, recorder)
	if matches.is_empty():
		quit(2)
		return
	var summary := BalanceRunSummary.build(_config(), matches, recorder.rows())
	var write_ok := _write(matches, recorder, summary)
	_print_summary(summary, matches)
	var totals: Dictionary = summary["totals"]
	quit(0 if write_ok and totals["invariants_clean"] else 1)


# --- setup -------------------------------------------------------------------


## Returns false on any bad flag rather than quietly playing something else: a
## mistyped commander would otherwise measure a neutral matchup and the run would
## look fine.
func _parse_args() -> bool:
	for arg in CmdArgs.user():
		if arg.begins_with("--map="):
			_map_name = arg.get_slice("=", 1).strip_edges()
		elif arg.begins_with("--red="):
			_red_text = arg.get_slice("=", 1)
		elif arg.begins_with("--blue="):
			_blue_text = arg.get_slice("=", 1)
		elif arg.begins_with("--sweep="):
			_sweep = arg.get_slice("=", 1).strip_edges()
		elif arg.begins_with("--tier="):
			_sweep_tier = StringName(arg.get_slice("=", 1).strip_edges())
		elif arg.begins_with("--commander="):
			_sweep_commander = StringName(arg.get_slice("=", 1).strip_edges())
		elif arg.begins_with("--seeds="):
			var value := arg.get_slice("=", 1)
			var parsed := _int_flag(value, 1)
			if parsed < 0:
				push_error("balance-sim: --seeds must be a positive integer (got '%s')" % value)
				return false
			_seed_count = parsed
		elif arg.begins_with("--seed="):
			# Watch mode's spelling, accepted here too: a suspicious row's flags
			# copied verbatim off the CSV replay that seed headlessly. It pins the
			# seed and nothing else, so both seatings are still played and watch
			# mode — which seats --red as red — reproduces the seat-0 row of the two.
			var value := arg.get_slice("=", 1)
			var parsed := _int_flag(value, 0)
			if parsed < 0:
				push_error("balance-sim: --seed must be a non-negative integer (got '%s')" % value)
				return false
			_pinned_seed = parsed
		elif arg.begins_with("--seed-offset="):
			var value := arg.get_slice("=", 1)
			var parsed := _int_flag(value, 0)
			if parsed < 0:
				push_error(
					"balance-sim: --seed-offset must be a non-negative integer (got '%s')" % value
				)
				return false
			_seed_offset = parsed
		elif arg.begins_with("--days="):
			var value := arg.get_slice("=", 1)
			var parsed := _int_flag(value, 1)
			if parsed < 0:
				push_error("balance-sim: --days must be a positive integer (got '%s')" % value)
				return false
			_days_cap = parsed
		elif arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1).strip_edges()
		elif arg == "--no-commands":
			_log_commands = false
		elif arg == "--replays":
			_write_replays = true
		else:
			push_error("balance-sim: unknown flag '%s'" % arg)
			return false
	if _out_dir != "":
		var resolved := BalanceReportWriter.resolve_out(_out_dir)
		if resolved == "":
			push_error("balance-sim: --out is a directory under reports/ (got '%s')" % _out_dir)
			return false
		_out_dir = resolved
	if _sweep != "" and _sweep not in ["commanders", "maps", "tiers"]:
		push_error("balance-sim: --sweep must be commanders, maps or tiers (got '%s')" % _sweep)
		return false
	if not _harness.difficulty_db.has(_sweep_tier):
		push_error("balance-sim: unknown tier '%s'" % _sweep_tier)
		return false
	if not _harness.commander_db.has(_sweep_commander):
		push_error("balance-sim: unknown commander '%s'" % _sweep_commander)
		return false
	if _pinned_seed >= 0 and _seed_offset > 0:
		push_error("balance-sim: --seed= pins one seed; --seed-offset= slices a range")
		return false
	if _sweep != "maps" and _harness.map_of(_map_name) == null:
		return false
	return _spec(_red_text) != null and _spec(_blue_text) != null


## Validates a numeric flag's raw text before coercing it: an integer at least
## `min_value`, or -1 (never legal here) otherwise — so `--seeds=four` and
## `--days=-5` refuse out loud instead of the old `maxi(1, int(...))` quietly
## landing on 1.
func _int_flag(value: String, min_value: int) -> int:
	if not value.is_valid_int():
		return -1
	var parsed := value.to_int()
	return parsed if parsed >= min_value else -1


func _spec(text: String) -> BalanceSideSpec:
	var spec := BalanceSideSpec.parse(text, _harness.commander_db, _harness.difficulty_db)
	if spec.error != "":
		push_error("balance-sim: %s" % spec.error)
		return null
	return spec


# --- the run ------------------------------------------------------------------


## Expands the run's one free axis (plan D5) into the flat list of matches to
## play. Every job is a fully-pinned matchup, so the loop below has no branching
## left in it and a sweep is just a longer list.
func _build_jobs() -> Array[Job]:
	var jobs: Array[Job] = []
	var red := _spec(_red_text)
	var blue := _spec(_blue_text)
	match _sweep:
		"commanders":
			# Every commander against the pinned opponent, both at --tier: a
			# power-level reading of the roster on one board. `all()` rather than
			# `playable()`, unlike the commander matrix: here the neutral row is
			# the baseline the doctrines are read against, not a control among
			# the subjects.
			for co in _harness.commander_db.all():
				var subject := BalanceSideSpec.new()
				subject.commander = co.id
				subject.tier = _sweep_tier
				var against := BalanceSideSpec.new()
				against.commander = blue.commander
				against.tier = _sweep_tier
				jobs.append_array(_pair(String(co.id), _map_name, subject, against))
		"maps":
			var skipped := 0
			for path in MapCatalog.paths():
				var name := path.get_file().trim_suffix(".txt")
				var map := _harness.map_of(name)
				if map == null:
					continue
				var seats := map.player_count()
				if seats > 2:
					print(
						(
							(
								"balance-sim: skipping %s — seats %d armies and the engine plays two "
								+ "(asymmetric-board R4)"
							)
							% [name, seats]
						)
					)
					skipped += 1
					continue
				jobs.append_array(_pair(name, name, red, blue))
			if skipped > 0:
				print(
					(
						"balance-sim: skipped %d multi-seat board(s) of %d shipped"
						% [skipped, MapCatalog.paths().size()]
					)
				)
		"tiers":
			for pairing: Array in TIER_LADDER:
				var high := BalanceSideSpec.new()
				high.commander = _sweep_commander
				high.tier = pairing[1]
				var low := BalanceSideSpec.new()
				low.commander = _sweep_commander
				low.tier = pairing[0]
				jobs.append_array(
					_pair("%s over %s" % [pairing[1], pairing[0]], _map_name, high, low)
				)
		_:
			jobs.append_array(_pair("%s vs %s" % [red.slug(), blue.slug()], _map_name, red, blue))
	return jobs


## Every seed of one matchup, played from **both seats** so a first-move edge
## cancels out of the win rate and is reported separately as bias. Which seeds
## those are, and which of them a mirror skips, is BalanceMatchSchedule's — the
## one authority every preset over this engine shares.
func _pair(
	value: String, map_name: String, red: BalanceSideSpec, blue: BalanceSideSpec
) -> Array[Job]:
	var jobs: Array[Job] = []
	var mirror := red.text() == blue.text()
	var slots: Array = BalanceMatchSchedule.slots(
		map_name, _seed_count, _seed_offset, mirror, _pinned_seed
	)
	for slot: BalanceMatchSchedule.Slot in slots:
		var job := Job.new()
		job.value = value
		job.map_name = map_name
		job.seed_val = slot.seed_val
		job.seat = slot.seat
		job.mirror = mirror
		job.red = red if slot.seat == 0 else blue
		job.blue = blue if slot.seat == 0 else red
		job.subject_side = "red" if slot.seat == 0 else "blue"
		jobs.append(job)
	return jobs


func _run(jobs: Array[Job], recorder: BalanceMatchRecorder) -> Array[Dictionary]:
	print(
		(
			"balance-sim: %s, %d seeds, day cap %d -> %d matches"
			% [_axis_label(), _seeds_played(), _days_cap, jobs.size()]
		)
	)
	var rows: Array[Dictionary] = []
	var done := 0
	for job in jobs:
		var row := _play(job, recorder)
		if row.is_empty():
			return []
		rows.append(row)
		done += 1
		if done % 50 == 0:
			print("balance-sim: %d / %d matches" % [done, jobs.size()])
	return rows


func _play(job: Job, recorder: BalanceMatchRecorder) -> Dictionary:
	var map := _harness.map_of(job.map_name)
	var unit_db := _harness.unit_db
	var difficulty_db := _harness.difficulty_db
	var setup := BalanceMatchEngine.Setup.new()
	setup.map = map
	setup.unit_db = unit_db
	setup.chart = _harness.chart
	setup.seed_val = job.seed_val
	setup.days_cap = _days_cap
	setup.match_id = (
		"%s#%s_vs_%s#s%d" % [job.map_name, job.red.slug(), job.blue.slug(), job.seed_val]
	)
	setup.commanders = {
		1: _harness.commander_db.by_id(job.red.commander),
		2: _harness.commander_db.by_id(job.blue.commander),
	}
	setup.tiers = {1: job.red.tier, 2: job.blue.tier}
	# One planner per side, each with its own profile and its own per-turn threat
	# map. The tier's whole effect is which profile plans the moves — no economy,
	# vision, damage or luck differs at any tier (difficulty plan D2/D3).
	setup.planners = {
		1: AIController.new(unit_db, difficulty_db.by_id(job.red.tier).profile()),
		2: AIController.new(unit_db, difficulty_db.by_id(job.blue.tier).profile()),
	}
	if _write_replays:
		var match_id := setup.match_id
		setup.replay = ReplayRecorder.new(func() -> ReplayFile: return _open_replay(match_id))
	var outcome := BalanceMatchEngine.play(setup, recorder)
	if setup.replay != null:
		setup.replay.close()
	if outcome.state == null:
		push_error("balance-sim: could not build a match on '%s'" % job.map_name)
		return {}
	var state := outcome.state
	# The timeline is checked against the board it describes on every match, not
	# once at the end: a miscount is a red build, never a quiet lie in the data.
	var problem := recorder.reconcile(state, outcome.starting_units)
	if problem != "":
		push_error(
			"balance-sim: telemetry does not reconcile on %s: %s" % [setup.match_id, problem]
		)
		return {}
	var subject_team := 1 if job.subject_side == "red" else 2
	return {
		"match_id": setup.match_id,
		"sweep_axis": _sweep if _sweep != "" else "matchup",
		"sweep_value": job.value,
		"map": job.map_name,
		"seed": job.seed_val,
		"seat": job.seat,
		"mirror": 1 if job.mirror else 0,
		"naval": 1 if _is_naval(map) else 0,
		"red_commander": String(job.red.commander),
		"red_tier": String(job.red.tier),
		"blue_commander": String(job.blue.commander),
		"blue_tier": String(job.blue.tier),
		"subject_side": job.subject_side,
		"subject_won": 1 if outcome.winner == subject_team else 0,
		"winner": outcome.winner,
		"termination": outcome.termination,
		"day_ended": outcome.day_ended,
		"commands": outcome.commands,
		"rejected": outcome.rejected,
		"cap_stall": 1 if outcome.cap_stall else 0,
		"turn_cap_hits": outcome.turn_cap_hits,
		"red_units": state.units_of(1).size(),
		"blue_units": state.units_of(2).size(),
		"red_props": state.properties_of(1).size(),
		"blue_props": state.properties_of(2).size(),
		"red_funds": int(state.funds.get(1, 0)),
		"blue_funds": int(state.funds.get(2, 0)),
		"red_army_value": BalanceMatchEngine.army_value(state, 1),
		"blue_army_value": BalanceMatchEngine.army_value(state, 2),
		"red_powers": outcome.powers[1],
		"blue_powers": outcome.powers[2],
	}


## A board where the naval domain is actually in play — one that can *build* a
## hull, not merely one with water on it. Almost every shipped map is framed by a
## decorative sea border, so "has a sea tile" would annotate the whole roster and
## the flag would mean nothing; a port is what puts a fleet, and therefore the
## ferry problem, on the board.
##
## Read off TerrainType.builds rather than a terrain id or a map name, like every
## other question about what a property does — so a board that gains a port is
## annotated the day it does, and only then.
##
## Plan R1: the AI never plans a ferry, so what the Lab measures on one of these
## is what the AI can express there, not what the board is worth to a human.
func _is_naval(map: MapData) -> bool:
	for y in map.height:
		for x in map.width:
			var builds := map.terrain_at(Vector2i(x, y)).builds
			if TerrainType.SHIP in builds or TerrainType.LANDER in builds:
				return true
	return false


# --- output ------------------------------------------------------------------


func _config() -> Dictionary:
	return {
		"axis": _sweep if _sweep != "" else "matchup",
		"label": _axis_label(),
		"map": "(swept)" if _sweep == "maps" else _map_name,
		"red": _red_text,
		"blue": _blue_text,
		"seeds": _seeds_played(),
		"seed": _pinned_seed,
		"seed_offset": _seed_offset,
		"days_cap": _days_cap,
		"command_log": _log_commands,
	}


## Seeds this run actually plays: `--seed=` pins exactly one, and reporting the
## `--seeds=` default beside a single played match would be a number the run
## never measured.
func _seeds_played() -> int:
	return 1 if _pinned_seed >= 0 else _seed_count


func _axis_label() -> String:
	match _sweep:
		"commanders":
			return "every commander at %s on %s" % [_sweep_tier, _map_name]
		"maps":
			return "%s vs %s on every shipped board" % [_red_text, _blue_text]
		"tiers":
			return "the tier ladder on %s, both sides %s" % [_map_name, _sweep_commander]
	return "%s vs %s on %s" % [_red_text, _blue_text, _map_name]


## Derived from the spec, never from a clock — so rerunning the same batch
## overwrites its own directory instead of littering a new one, and two runs of
## the same question are diffable file for file.
##
## **Every flag that changes the numbers is in the name.** The pinned seed and the
## day cap are part of the spec, not decoration: two `--seed=` replays of one
## matchup are different matches, and a 25-day run of it is a different question
## from a 20-day one. Leaving either out silently overwrote one run's report with
## another's.
func _run_name() -> String:
	var parts: Array[String] = []
	parts.append(_sweep if _sweep != "" else "matchup")
	parts.append("(swept)" if _sweep == "maps" else _map_name)
	if _sweep != "commanders":
		parts.append("%s_vs_%s" % [_red_text, _blue_text])
	if _sweep == "commanders":
		parts.append(String(_sweep_tier))
	if _sweep == "tiers":
		parts.append(String(_sweep_commander))
	if _pinned_seed >= 0:
		parts.append("seed%d" % _pinned_seed)
	else:
		parts.append("s%d" % _seed_count)
		if _seed_offset > 0:
			parts.append("o%d" % _seed_offset)
	parts.append("d%d" % _days_cap)
	return "_".join(parts).replace(":", "-").replace(" ", "").replace("(", "").replace(")", "")


## This match's recording. Named by match id like the timeline rows are, so a
## suspicious CSV row and the file that replays it share a key. Called by the
## recorder on the first command rather than up front, so a match that never
## reaches one leaves no file behind.
func _open_replay(match_id: String) -> ReplayFile:
	var dir := BalanceReportWriter.prepare_dir(_artifact_dir.path_join("replays"))
	var name := match_id.replace(":", "-").replace("/", "-")
	return ReplayFile.open_at(dir.path_join(name + ReplayFile.EXTENSION))


## Returns whether every artifact landed. A write failure is reported here and
## must reach the exit code the caller quits with — a half-written sweep must
## never print its wrote-N-rows line and then exit 0.
func _write(
	matches: Array[Dictionary], recorder: BalanceMatchRecorder, summary: Dictionary
) -> bool:
	var out := _artifact_dir
	var dir := BalanceReportWriter.prepare_dir(out)
	if dir == "":
		return false
	var ok := true
	ok = BalanceReportWriter.write_csv(dir.path_join("matches.csv"), matches, MATCH_COLUMNS) and ok
	ok = (
		BalanceReportWriter.write_csv(
			dir.path_join("timeline.csv"), recorder.rows(), BalanceMatchRecorder.TIMELINE_COLUMNS
		)
		and ok
	)
	ok = BalanceReportWriter.write_json(dir.path_join("summary.json"), summary) and ok
	if _log_commands:
		ok = (
			BalanceReportWriter.write_jsonl(dir.path_join("commands.jsonl"), recorder.command_log())
			and ok
		)
	ok = (
		BalanceReportWriter.write_text(
			dir.path_join("report.html"), BalanceReportHtml.render(summary, recorder.rows())
		)
		and ok
	)
	if not ok:
		push_error("balance-sim: failed to write the report to %s" % out)
		return false
	print(
		(
			"balance-sim: wrote %d match rows, %d timeline rows%s to %s"
			% [
				matches.size(),
				recorder.rows().size(),
				(
					" and %d command log lines" % recorder.command_log().size()
					if _log_commands
					else ""
				),
				out,
			]
		)
	)
	print("balance-sim: open %s/report.html to read it" % out)
	return true


func _print_summary(summary: Dictionary, matches: Array[Dictionary]) -> void:
	var totals: Dictionary = summary["totals"]
	var bias: Dictionary = summary["bias"]["overall"]
	print("\n=== balance lab: %s ===" % summary["run"]["label"])
	print(
		(
			"matches %d   decisive %d   draws %d   rejected %d   cap-stalls %d"
			% [
				totals["matches"],
				totals["decisive"],
				totals["draws"],
				totals["total_rejected"],
				totals["total_cap_stalls"],
			]
		)
	)
	# The definition is in the label because the commander matrix prints a line
	# that reads almost the same and excludes mirrors — see BalanceRunSummary.bias.
	print(
		(
			"first-seat bias (all decisive games, mirrors counted) %+.1f pp (%s, threshold +-%.0f)"
			% [
				bias["bias_pp"],
				"ok" if bias["ok"] else "REVIEW",
				BalanceRunSummary.MAX_SIDE_BIAS_PP,
			]
		)
	)
	print(
		(
			"  %-26s %6s %5s  %-6s %-11s %8s %6s"
			% ["value", "win%", "n", "band", "confidence", "kills/1k", "exch."]
		)
	)
	for entry: Dictionary in summary["values"]:
		var economy: Dictionary = entry["economy"]
		print(
			(
				"  %-26s %6.1f %5d  %-6s %-11s %8.0f %6s"
				% [
					entry["value"],
					entry["win_rate"],
					entry["matches"],
					entry["flag"],
					entry["confidence"],
					economy["killed_per_1000_spent"],
					BalanceReportHtml.ratio(economy["exchange_ratio"]),
				]
			)
		)
	if summary["bias"]["per_map"].size() > 1:
		print("per-board first-seat bias:")
		for entry: Dictionary in summary["bias"]["per_map"]:
			print(
				(
					"  %-14s %+6.1f pp  (%d decisive)%s"
					% [
						entry["map"],
						entry["bias_pp"],
						entry["decisive"],
						"  [naval: AI-bounded]" if entry["naval_bounded"] else "",
					]
				)
			)
	for note: String in summary["notes"]:
		print("note: %s" % note)
	_warn_turn_caps(matches)
	if totals["invariants_clean"]:
		print("hard invariants clean (0 rejected, 0 cap stalls). Band flags are review triggers.")
	else:
		print("FAIL: rejected commands or cap stalls — the AI and the rules disagree.")


## Says out loud when the shared engine had to cut a turn short — the warning the
## commander matrix has always printed and this runner never did, though it plays
## the same loop and writes the count into every row of matches.csv. A cut turn
## resolves differently from the same flags let run, so a silent report reads as
## agreement with one that was not cut.
func _warn_turn_caps(matches: Array[Dictionary]) -> void:
	var hits := 0
	for row in matches:
		hits += int(row["turn_cap_hits"])
	if hits == 0:
		return
	print(
		(
			(
				"WARNING: %d turn(s) hit the %d-command per-turn cap and were force-ended. "
				% [hits, BalanceMatchEngine.MAX_COMMANDS_PER_TURN]
			)
			+ "Those matches did not resolve the way an uncut run's would."
		)
	)
	push_warning("balance-sim: %d turn(s) hit the per-turn command cap" % hits)
