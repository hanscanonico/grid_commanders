extends SceneTree
## The four-army board measurement (asymmetric-board plan AB3): the win spread
## and the match length over N seeds, AI on every seat, neutral commanders — the
## instrument the Four Armies plan already named for boards no symmetry tag can
## hold. Bulwark is its default board and the one it was written for; any
## shipped board and any tier can be read with the same loop, because
## `BalanceMatchEngine` plays exactly two sides (plan R4) and is structurally
## blind to all of them.
##
## `tests/unit/test_alliance_soak.gd` proves the groupings a board offers are
## *legal* — one seeded match each, ten days; this plays the same loop at a
## seed count and a day
## horizon meant to read a direction rather than a legality check, and writes
## the result to docs/bulwark_balance.md by hand. It is a measurement tool, not
## a gate (plan R4 again — so it stays out of `make commander-balance` and
## `make difficulty-check`, and out of `make verify` and `make test` alike), and
## it tunes nothing: AB3 measured, AB4 read the number, and the four board-only
## candidates AB4 tried all lost to leaving the board alone, so the board it
## plays is AB2's.
##
## The loop is `FourArmyLoop`, shared with the mobile soak's planner clock and
## the soak test's `_soak`, not a preset over `BalanceMatchEngine` (whose
## own `_has_independent_planners` / `tiebreak` / `_match_id` all assume exactly
## two teams): `BalanceHarness.map_of` -> `GameState.create` -> `state.sides`
## set directly, exactly as the soak sets it, never read off the map's own
## `# grouping` header (plan D2 — that tag is the lint's alone) -> one
## `AIController` per army, so no two share a turn's cached threat map. Neutral
## commanders throughout: unlike the soak, which seats a doctrine on purpose to
## exercise the hooks, this measures the board, so no `set_commander` call ever
## runs and every army plans through `CommanderType.neutral()`'s defaults.
##
## Usage (headless; see `make bulwark-measure` and `make board-measure`):
##   Godot --headless --path . -s res://tools/run_bulwark_measure.gd -- [flags]
##     --map=bulwark     board by name, shipped or fixture (default bulwark)
##     --tier=normal     the tier every seat plays at (default normal, which is
##                       the planner's own defaults)
##     --seeds=30        matches per grouping (default 30)
##     --seed-offset=0   first seed skipped, so a rerun can extend a sample
##                       without repeating it
##     --days=100        day horizon a match that has not resolved by is
##                       counted undecided rather than played out further
##     --grouping=both   alliance | ffa | both (default), or a `--sides=`
##                       grammar such as 1+3v2+4. `alliance` is Bulwark's own
##                       1+2+3v4 preset and only reads on that board; `ffa` is
##                       the free-for-all every four-seat board's seat strip
##                       also offers, and works on any of them.
##     --out=reports/<map>   output directory (default shown)
##
## Writes matches.csv and summary.json per grouping under --out (gitignored)
## and prints the table docs/bulwark_balance.md was written from.

const TOOL := "board-measure"
const DEFAULT_MAP := "bulwark"
const DEFAULT_TIER := &"normal"

## Seats 1+2+3 against seat 4 — the grouping Bulwark's own header names, stated
## here exactly as `test_alliance_soak.gd` states any board's grouping: through
## the one flag grammar, onto `state.sides`, never derived from
## `MapData.grouping`.
const ALLIANCE_GRAMMAR := "1+2+3v4"
## The two sides of that preset, named the way docs/bulwark_balance.md names
## them. Every other grouping names a side by its seats, there being nothing
## else to call it.
const ALLIANCE_SIDE_NAMES: Dictionary[int, String] = {0: "alliance", 1: "bulwark"}
## What `--grouping` takes, as a refusal names them: the shared loop's two plus
## the preset this tool adds on top of them.
const GROUPING_OPTIONS := "alliance, ffa, both or a grouping like 1+3v2+4"

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

var _harness: BalanceHarness
var _map: MapData
var _profile: AIProfile

var _map_name := DEFAULT_MAP
var _tier_id := DEFAULT_TIER
var _seed_count := 30
var _seed_offset := 0
var _days_cap := 100
var _grouping := "both"
var _out_dir := ""


func _init() -> void:
	if not _parse_args():
		quit(2)
		return
	_harness = BalanceHarness.load_default()
	_map = _harness.map_of(_map_name)
	if _map == null:
		quit(2)
		return
	var tiers := DifficultyDB.load_default()
	if not tiers.has(_tier_id):
		push_error(
			"%s: --tier is one of %s (got '%s')" % [TOOL, ", ".join(_tier_names(tiers)), _tier_id]
		)
		quit(2)
		return
	_profile = tiers.by_id(_tier_id).profile()
	var broken := false
	for run: Dictionary in _runs():
		broken = _run(run) or broken
	quit(1 if broken else 0)


## Returns false on any bad flag rather than quietly playing something else, the
## same policy `tools/run_balance_sim.gd` states: a mistyped `--seeds=` would
## otherwise spend half an hour measuring a sample width nobody asked for.
func _parse_args() -> bool:
	for arg in CmdArgs.user():
		if arg.begins_with("--map="):
			_map_name = arg.get_slice("=", 1)
		elif arg.begins_with("--tier="):
			_tier_id = StringName(arg.get_slice("=", 1))
		elif arg.begins_with("--seeds="):
			var value := arg.get_slice("=", 1)
			var parsed := BalanceHarness.int_flag(value, 1)
			if parsed < 0:
				push_error("%s: --seeds must be a positive integer (got '%s')" % [TOOL, value])
				return false
			_seed_count = parsed
		elif arg.begins_with("--seed-offset="):
			var value := arg.get_slice("=", 1)
			var parsed := BalanceHarness.int_flag(value, 0)
			if parsed < 0:
				push_error(
					"%s: --seed-offset must be a non-negative integer (got '%s')" % [TOOL, value]
				)
				return false
			_seed_offset = parsed
		elif arg.begins_with("--days="):
			var value := arg.get_slice("=", 1)
			var parsed := BalanceHarness.int_flag(value, 1)
			if parsed < 0:
				push_error("%s: --days must be a positive integer (got '%s')" % [TOOL, value])
				return false
			_days_cap = parsed
		elif arg.begins_with("--grouping="):
			_grouping = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
		else:
			push_error("%s: unknown flag '%s'" % [TOOL, arg])
			return false
	if not _grouping_readable():
		return false
	if _out_dir == "":
		_out_dir = "reports".path_join(_map_name)
	var resolved := BalanceReportWriter.resolve_out(_out_dir)
	if resolved == "":
		push_error("%s: --out is a directory under reports/ (got '%s')" % [TOOL, _out_dir])
		return false
	_out_dir = resolved
	return true


## `alliance` and `both` name Bulwark's own preset, so they say nothing about
## another board's seats — a board measured under a grouping of its own states
## it in the `--sides=` grammar, which every four-seat board can express and
## which nothing here re-spells.
func _grouping_readable() -> bool:
	if _grouping in ["alliance", "both"]:
		if _map_name != DEFAULT_MAP:
			push_error(
				(
					"%s: --grouping=%s is %s's preset; name --map=%s's own (ffa, or 1+3v2+4)"
					% [TOOL, _grouping, DEFAULT_MAP, _map_name]
				)
			)
			return false
		return true
	return FourArmyLoop.grouping_readable(TOOL, _grouping, GROUPING_OPTIONS)


## What this invocation plays, in order: label, output slug, sides and the names
## its sides are reported under.
func _runs() -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	if _grouping in ["alliance", "both"]:
		runs.append(_plan("3v1", "alliance", ALLIANCE_GRAMMAR, ALLIANCE_SIDE_NAMES))
	if _grouping in ["ffa", "both"]:
		runs.append(_plan("free-for-all", "free_for_all", "", {}))
	if runs.is_empty():
		runs.append(_plan(_grouping, _grouping.replace("+", "_"), _grouping, {}))
	return runs


func _plan(
	label: String, slug: String, grammar: String, side_names: Dictionary[int, String]
) -> Dictionary:
	return {
		"label": label,
		"slug": slug,
		"sides": _sides_of(grammar),
		"side_names": side_names,
	}


## `MatchRequest.parse_sides_flag` is the one reader of the grouping grammar —
## the flag a launch states its sides with, so a measured grouping and a played
## one can never be two different readings of the same string.
func _sides_of(grammar: String) -> Dictionary[int, int]:
	var sides: Dictionary[int, int] = {}
	var parsed := MatchRequest.parse_sides_flag(grammar)
	for seat: int in parsed:
		sides[seat] = int(parsed[seat])
	return sides


func _tier_names(tiers: DifficultyDB) -> Array[String]:
	var names: Array[String] = []
	for tier in tiers.all():
		names.append(String(tier.id))
	return names


## Plays one grouping over the whole seed range and reports whether anything
## broke — a rejected command or a genuine stall — which is the "no rejected
## command, no stall" half of AB3's gate. A match that simply has not resolved
## by `_days_cap` is neither: it is the other half of the gate's answer.
func _run(run: Dictionary) -> bool:
	var label: String = run["label"]
	var sides: Dictionary[int, int] = run["sides"]
	print("%s: %s — %d seeds, %d-day horizon" % [_map_name, label, _seed_count, _days_cap])
	var rows: Array[Dictionary] = []
	for i in _seed_count:
		var seed_val := _seed_offset + i + 1
		var row := _play(run, seed_val)
		if row.is_empty():
			push_error(
				(
					"%s: %s seed %d could not be seated on %s"
					% [TOOL, label, seed_val, _map.source_path]
				)
			)
			return true
		rows.append(row)
	var summary := _summarise(label, sides, rows)
	var write_ok := _write(run["slug"], rows, summary)
	_print(summary)
	return summary["total_rejected"] > 0 or summary["total_cap_stalls"] > 0 or not write_ok


## One match through `FourArmyLoop`, read back as the row this report is
## written from. The loop mirrors `test_alliance_soak.gd::_soak`'s exactly, with
## three differences here: no commander is ever seated (neutral throughout,
## measuring the board rather than a doctrine); the day horizon is a
## measurement's rather than a legality check's ten; and fog stays off for every
## seed, where the soak alternates it by seed to walk the shared-sight path —
## fog moves AI pathing (a committed path is walked with the mover's own
## visibility) and switches off the AR1 plan cache, so alternating it would
## measure two boards and report one number. Returns an empty row when the board
## cannot be seated at all.
func _play(run: Dictionary, seed_val: int) -> Dictionary:
	var sides: Dictionary[int, int] = run["sides"]
	var played := FourArmyLoop.play(_map, _harness, _profile, sides, seed_val, _days_cap)
	if played.is_empty():
		return {}
	var state: GameState = played["state"]
	return {
		"grouping": run["label"],
		"seed": seed_val,
		"winner": state.winner,
		"winner_side": _winner_side(state, run),
		"day_ended": state.day,
		"commands": played["commands"],
		"rejected": played["rejected"],
		"cap_stall": played["cap_stall"],
		"turn_cap_hits": played["turn_cap_hits"],
		"eliminated": ";".join(state.eliminated.keys().map(func(t: int) -> String: return str(t))),
	}


## "undecided" while the match runs past `_days_cap` with nobody eliminated
## down to one side; the winning side's own name under a grouping — Bulwark's
## two are "alliance" and "bulwark", any other grouping's are its seats — and
## "seat_<n>" under the free-for-all, where nothing groups the winner at all.
func _winner_side(state: GameState, run: Dictionary) -> String:
	if state.winner == 0:
		return "undecided"
	var sides: Dictionary[int, int] = run["sides"]
	if sides.is_empty():
		return "seat_%d" % state.winner
	var side: int = sides.get(state.winner, -1)
	var names: Dictionary[int, String] = run["side_names"]
	if names.has(side):
		return names[side]
	return "+".join(_seats_on(sides, side).map(func(t: int) -> String: return str(t)))


func _seats_on(sides: Dictionary[int, int], side: int) -> Array[int]:
	var seats: Array[int] = []
	for seat: int in sides:
		if sides[seat] == side:
			seats.append(seat)
	seats.sort()
	return seats


## Tallies the numbers the design question actually asks: how often each side
## of the grouping wins, how long a match that resolved took, how many never
## got there by the horizon, and — only meaningful for seats that share a side,
## which is Bulwark's three allies — how often one of them fell along the way,
## whether or not its side went on to win.
func _summarise(label: String, sides: Dictionary[int, int], rows: Array[Dictionary]) -> Dictionary:
	var total_rejected := 0
	var total_cap_stalls := 0
	var total_turn_cap_hits := 0
	var undecided := 0
	var winners: Dictionary = {}
	var decided_days: Array[int] = []
	var allied_falls: Dictionary = {}
	for seat in _allied_seats(sides):
		allied_falls[seat] = 0
	for row in rows:
		total_rejected += int(row["rejected"])
		total_cap_stalls += int(row["cap_stall"])
		total_turn_cap_hits += int(row["turn_cap_hits"])
		var side: String = row["winner_side"]
		if side == "undecided":
			undecided += 1
		else:
			winners[side] = int(winners.get(side, 0)) + 1
			decided_days.append(int(row["day_ended"]))
		var fallen: String = row["eliminated"]
		if fallen == "":
			continue
		for token in fallen.split(";", false):
			var team := int(token)
			if allied_falls.has(team):
				allied_falls[team] += 1
	var n := rows.size()
	var decided := n - undecided
	return {
		"map": _map_name,
		"tier": String(_tier_id),
		"grouping": label,
		"matches": n,
		"total_rejected": total_rejected,
		"total_cap_stalls": total_cap_stalls,
		"total_turn_cap_hits": total_turn_cap_hits,
		"undecided": undecided,
		"undecided_pct": 100.0 * float(undecided) / maxf(1.0, float(n)),
		"decided": decided,
		"decided_pct": 100.0 * float(decided) / maxf(1.0, float(n)),
		# Over the matches that resolved only: an undecided match has no length
		# to average, only a horizon it outlived, so counting it as `days_cap`
		# would report the horizon as a measurement.
		"mean_day": FourArmyLoop.mean(decided_days),
		"median_day": FourArmyLoop.median(decided_days),
		"winners": winners,
		"allied_falls": allied_falls,
		"days_cap": _days_cap,
	}


## The seats that share a side with another seat: whose falling is a loss the
## side may still win past, which is what makes it worth counting separately.
func _allied_seats(sides: Dictionary[int, int]) -> Array[int]:
	var seats: Array[int] = []
	for seat: int in sides:
		if _seats_on(sides, sides[seat]).size() > 1:
			seats.append(seat)
	seats.sort()
	return seats


func _write(slug: String, rows: Array[Dictionary], summary: Dictionary) -> bool:
	var dir := BalanceReportWriter.prepare_dir(_out_dir.path_join(slug))
	if dir == "":
		return false
	var ok := BalanceReportWriter.write_csv(dir.path_join("matches.csv"), rows, CSV_COLUMNS)
	ok = BalanceReportWriter.write_json(dir.path_join("summary.json"), summary) and ok
	if not ok:
		push_error("%s: failed to write matches.csv and summary.json to %s" % [TOOL, dir])
		return false
	print("%s: wrote matches.csv and summary.json to %s" % [TOOL, dir])
	return true


func _print(summary: Dictionary) -> void:
	print(
		(
			"\n=== %s: %s (%d seeds, %d-day horizon, %s) ==="
			% [
				summary["map"],
				summary["grouping"],
				summary["matches"],
				summary["days_cap"],
				summary["tier"],
			]
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
	print(
		(
			"decided %d/%d (%.1f%%)   day ended: mean %.1f   median %.1f"
			% [
				summary["decided"],
				summary["matches"],
				summary["decided_pct"],
				summary["mean_day"],
				summary["median_day"],
			]
		)
	)
	var winners: Dictionary = summary["winners"]
	var decided: int = summary["decided"]
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
