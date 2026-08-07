extends SceneTree
## The Bulwark fairness measurement (asymmetric-board plan AB3): the win spread
## over N seeds, AI on all four seats, neutral commanders — the instrument the
## Four Armies plan already named for a board no symmetry tag can hold.
##
## `tests/unit/test_alliance_soak.gd` proves the two groupings this board offers
## are *legal* — one seeded match each, ten days; this plays the same loop at a
## seed count and a day
## horizon meant to read a direction rather than a legality check, and writes
## the result to docs/bulwark_balance.md by hand. It is a measurement tool, not
## a gate (plan R4: BalanceMatchEngine plays two sides, and this board is four
## — so it stays out of `make commander-balance` and `make difficulty-check`,
## and out of `make verify` and `make test` alike), and it tunes nothing: AB3
## measured, AB4 read the number, and the four board-only candidates AB4 tried
## all lost to leaving the board alone, so the board it plays is AB2's.
##
## The loop is the soak's `_soak`, not a preset over `BalanceMatchEngine`
## (which the plan's R4 forbids pointing at this board and whose own
## `_has_independent_planners` / `tiebreak` / `_match_id` all assume exactly two
## teams): `MapData.load_from_file` -> `GameState.create` -> `state.sides` set
## directly, exactly as the soak sets it, never read off the map's own
## `# grouping` header (plan D2 — that tag is the lint's alone) -> one
## `AIController` per army, so no two share a turn's cached threat map. Neutral
## commanders throughout: unlike the soak, which seats a doctrine on purpose to
## exercise the hooks, this measures the board, so no `set_commander` call ever
## runs and every army plans through `CommanderType.neutral()`'s defaults.
##
## Usage (headless; see `make bulwark-measure`):
##   Godot --headless --path . -s res://tools/run_bulwark_measure.gd -- [flags]
##     --seeds=30        matches per grouping (default 30)
##     --seed-offset=0   first seed skipped, so a rerun can extend a sample
##                       without repeating it
##     --days=100        day horizon a match that has not resolved by is
##                       counted undecided rather than played out further
##     --grouping=both   alliance | ffa | both (default) — alliance is the
##                       board's own 1+2+3v4, ffa is the free-for-all every
##                       four-seat board's seat strip also offers
##     --out=reports/bulwark   output directory (default shown)
##
## Writes matches.csv and summary.json per grouping under --out (gitignored)
## and prints the table docs/bulwark_balance.md was written from.

const MAP_PATH := "res://maps/bulwark.txt"
const DAMAGE_CHART_PATH := "res://data/damage_chart.tres"

## Seats 1+2+3 against seat 4 — the grouping the board's own header names,
## stated here exactly as `test_alliance_soak.gd` states any board's grouping:
## directly on `state.sides`, never derived from `MapData.grouping`.
const ALLIANCE: Dictionary = {1: 0, 2: 0, 3: 0, 4: 1}
const FREE_FOR_ALL: Dictionary = {}
const ALLIANCE_TEAMS: Array[int] = [1, 2, 3]
const BULWARK_TEAM := 4

const CSV_COLUMNS: Array[String] = [
	"grouping",
	"seed",
	"winner",
	"winner_side",
	"day_ended",
	"commands",
	"rejected",
	"cap_stall",
	"turn_cap_hits",
	"eliminated",
]

var _terrain_db: TerrainDB
var _unit_db: UnitDB
var _chart: DamageChart
var _map: MapData

var _seed_count := 30
var _seed_offset := 0
var _days_cap := 100
var _grouping := "both"
var _out_dir := "reports/bulwark"


func _init() -> void:
	if not _parse_args():
		quit(2)
		return
	_terrain_db = TerrainDB.load_default()
	_unit_db = UnitDB.load_default()
	_chart = load(DAMAGE_CHART_PATH)
	_map = MapData.load_from_file(MAP_PATH, _terrain_db)
	if _map == null:
		push_error("bulwark: cannot load %s" % MAP_PATH)
		quit(2)
		return
	var broken := false
	if _grouping in ["alliance", "both"]:
		broken = _run("3v1", "alliance", ALLIANCE) or broken
	if _grouping in ["ffa", "both"]:
		broken = _run("free-for-all", "free_for_all", FREE_FOR_ALL) or broken
	quit(1 if broken else 0)


## Returns false on any bad flag rather than quietly playing something else, the
## same policy `tools/run_balance_sim.gd` states: a mistyped `--seeds=` would
## otherwise spend half an hour measuring a sample width nobody asked for.
func _parse_args() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			_seed_count = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--seed-offset="):
			_seed_offset = maxi(0, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--days="):
			_days_cap = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--grouping="):
			_grouping = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
		else:
			push_error("bulwark: unknown flag '%s'" % arg)
			return false
	if not (_grouping in ["alliance", "ffa", "both"]):
		push_error("bulwark: --grouping is alliance, ffa or both (got '%s')" % _grouping)
		return false
	var resolved := BalanceReportWriter.resolve_out(_out_dir)
	if resolved == "":
		push_error("bulwark: --out is a directory under reports/ (got '%s')" % _out_dir)
		return false
	_out_dir = resolved
	return true


## Plays one grouping over the whole seed range and reports whether anything
## broke — a rejected command or a genuine stall — which is the "no rejected
## command, no stall" half of AB3's gate. A match that simply has not resolved
## by `_days_cap` is neither: it is the other half of the gate's answer.
func _run(label: String, slug: String, sides: Dictionary) -> bool:
	print("bulwark: %s — %d seeds, %d-day horizon" % [label, _seed_count, _days_cap])
	var rows: Array[Dictionary] = []
	for i in _seed_count:
		var seed_val := _seed_offset + i + 1
		var row := _play(label, sides, seed_val)
		if row.is_empty():
			push_error(
				"bulwark: %s seed %d could not be seated on %s" % [label, seed_val, MAP_PATH]
			)
			return true
		rows.append(row)
	var summary := _summarise(label, sides, rows)
	var write_ok := _write(slug, rows, summary)
	_print(summary)
	return summary["total_rejected"] > 0 or summary["total_cap_stalls"] > 0 or not write_ok


## One match, fresh state and one `AIController` per army. Mirrors
## `test_alliance_soak.gd::_soak`'s loop exactly, with three differences: no
## commander is ever seated (neutral throughout, measuring the board rather
## than a doctrine); the day horizon is a measurement's rather than a legality
## check's ten; and fog stays off for every seed, where the soak alternates it
## by seed to walk the shared-sight path — fog moves AI pathing (a committed
## path is walked with the mover's own visibility) and switches off the AR1
## plan cache, so alternating it would measure two boards and report one
## number. Returns an empty row when the board cannot be seated at all.
func _play(label: String, sides: Dictionary, seed_val: int) -> Dictionary:
	var state := GameState.create(_map, _unit_db, _chart)
	if state == null:
		return {}
	state.sides = sides
	state.rng.seed = seed_val
	var planners: Dictionary = {}
	for team in state.teams:
		planners[team] = AIController.new(_unit_db)
	var cap := BalanceMatchEngine.command_ceiling(_days_cap, state.teams.size())
	var commands := 0
	var rejected := 0
	var turn_cap_hits := 0
	var commands_this_turn := 0
	while state.winner == 0 and state.day <= _days_cap and commands < cap:
		var team: int = state.current_team
		var ai: AIController = planners[team]
		var command := ai.plan_next_command(state)
		# The scene's own per-turn safety net (BalanceMatchEngine.play), applied
		# here too: a planner that overstays is cut, not counted as a rejection.
		if (
			commands_this_turn >= BalanceMatchEngine.MAX_COMMANDS_PER_TURN
			and not (command is EndTurnCommand)
		):
			turn_cap_hits += 1
			command = EndTurnCommand.new()
		var error := command.validate(state)
		if error != "":
			rejected += 1
			push_error(
				(
					"bulwark %s seed %d (day %d, team %d): %s"
					% [label, seed_val, state.day, team, error]
				)
			)
			command = EndTurnCommand.new()
			if command.validate(state) != "":
				break
		commands_this_turn = 0 if command is EndTurnCommand else commands_this_turn + 1
		command.apply(state)
		commands += 1
	return {
		"grouping": label,
		"seed": seed_val,
		"winner": state.winner,
		"winner_side": _winner_side(state, sides),
		"day_ended": state.day,
		"commands": commands,
		"rejected": rejected,
		"cap_stall": 1 if (state.winner == 0 and commands >= cap) else 0,
		"turn_cap_hits": turn_cap_hits,
		"eliminated": ";".join(state.eliminated.keys().map(func(t: int) -> String: return str(t))),
	}


## "undecided" while the match runs past `_days_cap` with nobody eliminated
## down to one side; "bulwark" or "alliance" under the 3v1 grouping;
## "seat_<n>" under the free-for-all, where nothing groups the winner at all.
func _winner_side(state: GameState, sides: Dictionary) -> String:
	if state.winner == 0:
		return "undecided"
	if sides.is_empty():
		return "seat_%d" % state.winner
	return "bulwark" if state.winner == BULWARK_TEAM else "alliance"


## Tallies the numbers the design question actually asks: how often each side
## of the grouping wins, how many matches never got there by the horizon, and —
## only meaningful under the alliance grouping, where the three seats are
## nominally on one team — how often each allied seat fell along the way,
## whether or not its side went on to win.
func _summarise(label: String, sides: Dictionary, rows: Array[Dictionary]) -> Dictionary:
	var total_rejected := 0
	var total_cap_stalls := 0
	var total_turn_cap_hits := 0
	var undecided := 0
	var winners: Dictionary = {}
	var allied_falls: Dictionary = {}
	if not sides.is_empty():
		for team in ALLIANCE_TEAMS:
			allied_falls[team] = 0
	for row in rows:
		total_rejected += int(row["rejected"])
		total_cap_stalls += int(row["cap_stall"])
		total_turn_cap_hits += int(row["turn_cap_hits"])
		var side: String = row["winner_side"]
		if side == "undecided":
			undecided += 1
		else:
			winners[side] = int(winners.get(side, 0)) + 1
		if sides.is_empty():
			continue
		var fallen: String = row["eliminated"]
		if fallen == "":
			continue
		for token in fallen.split(";", false):
			var team := int(token)
			if allied_falls.has(team):
				allied_falls[team] += 1
	var n := rows.size()
	return {
		"grouping": label,
		"matches": n,
		"total_rejected": total_rejected,
		"total_cap_stalls": total_cap_stalls,
		"total_turn_cap_hits": total_turn_cap_hits,
		"undecided": undecided,
		"undecided_pct": 100.0 * float(undecided) / maxf(1.0, float(n)),
		"winners": winners,
		"allied_falls": allied_falls,
		"days_cap": _days_cap,
	}


func _write(slug: String, rows: Array[Dictionary], summary: Dictionary) -> bool:
	var dir := BalanceReportWriter.prepare_dir(_out_dir.path_join(slug))
	if dir == "":
		return false
	var ok := BalanceReportWriter.write_csv(dir.path_join("matches.csv"), rows, CSV_COLUMNS)
	ok = BalanceReportWriter.write_json(dir.path_join("summary.json"), summary) and ok
	if not ok:
		push_error("bulwark: failed to write matches.csv and summary.json to %s" % dir)
		return false
	print("bulwark: wrote matches.csv and summary.json to %s" % dir)
	return true


func _print(summary: Dictionary) -> void:
	print(
		(
			"\n=== bulwark: %s (%d seeds, %d-day horizon) ==="
			% [summary["grouping"], summary["matches"], summary["days_cap"]]
		)
	)
	print(
		(
			"rejected %d   cap-stalls %d   turn-cap-hits %d   undecided %d/%d (%.1f%%)"
			% [
				summary["total_rejected"],
				summary["total_cap_stalls"],
				summary["total_turn_cap_hits"],
				summary["undecided"],
				summary["matches"],
				summary["undecided_pct"],
			]
		)
	)
	var winners: Dictionary = summary["winners"]
	var decided: int = summary["matches"] - summary["undecided"]
	for side: String in winners.keys():
		var wins: int = winners[side]
		var pct := 100.0 * float(wins) / maxf(1.0, float(decided))
		print("  %-10s %3d win(s)  %5.1f%% of decided" % [side, wins, pct])
	var allied_falls: Dictionary = summary["allied_falls"]
	if not allied_falls.is_empty():
		print("  allied seat fell during the match (of %d):" % summary["matches"])
		for team: int in allied_falls.keys():
			print("    seat %d   %d" % [team, allied_falls[team]])
	if summary["total_rejected"] > 0 or summary["total_cap_stalls"] > 0:
		print("FAIL: rejected commands or cap stalls — the AI and the rules disagree.")
