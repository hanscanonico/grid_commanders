extends SceneTree
## Offline commander balance runner (readiness plan G4). Plays AI-vs-AI matches
## across every commander pairing, on rotationally-symmetric scenarios, with
## paired seeds, and writes a CSV of per-match rows plus a JSON summary with the
## plan's thresholds evaluated. It is a *measurement* tool, not a gate: the
## per-hook unit tests and the AI-vs-AI legality soak stay the correctness net;
## this quantifies balance so tuning has evidence behind it.
##
## It calls the exact same AIController and Commands play does, so a match here
## resolves identically to one in the battle scene given the same seed — the
## determinism the plan's report acceptance criteria require (same scenario +
## seed => byte-identical rows on a rerun; nothing here reads the clock or an
## unseeded RNG).
##
## Usage (headless; see `make commander-balance`):
##   Godot --headless --path . -s res://tools/run_commander_balance.gd -- [flags]
##     --commanders=alina_ward,viktor_draeg   subset (default: full roster)
##     --scenarios=clash,ridge                subset (default: all five)
##     --seeds=4                              paired seed count (default: 4)
##     --neutral                              add each commander vs No Commander
##     --days=20                              day cap before a match is a draw
##     --out=reports/commander_balance        output directory (default shown)
##
## The full batch (no flags) is every ordered pair on every scenario at four
## seeds — an explicit release task, deliberately out of `make test`; its size
## and the thresholds it is read against are in docs/commander_balance.md.
## A focused `--commanders`/`--scenarios`/`--seeds` run is the fast iteration loop.
##
## `--difficulty-check` (see `make difficulty-check`) is a second, opt-in mode
## asking a different question: do the tiers actually order Easy < Normal <
## Difficult? Tier against tier, no commanders, both mirrored maps, sides
## swapped, gated on BalanceRunSummary.DIFFICULTY_GATE_PCT. Difficulty ships no
## economy or damage handicap, so that win rate *is* the whole claim (plan D2).

## Both modes are presets over BalanceMatchEngine (plan D1): the match loop,
## the day-cap tiebreak and the termination labels live there now and are shared
## with the Balance Lab, so a number one tool reports means the same thing in the
## other. The bands, the seat bias and the ladder's gate come from
## BalanceRunSummary for the same reason — and because this file extends
## SceneTree, which puts it out of reach of GUT, while that one is driven by
## tests/unit/test_balance_summary.gd. The scaffolding every run needs — the
## databases and the boards — is BalanceHarness's, and which seeds a matchup
## plays is BalanceMatchSchedule's.
##
## This file keeps its CLI and its two committed reports unchanged:
## `docs/commander_balance.md` and `docs/difficulty_check.md` cite these exact
## flags, and the merge bar for touching it is a fixed-seed byte-diff of both
## reports before and after.
const DEFAULT_DAYS := BalanceMatchEngine.DEFAULT_DAYS

## --- difficulty check (plan DF4) ---------------------------------------------
##
## Two committed maps, small and large, because the gate has to answer whether
## the extra thinking pays with room to manoeuvre as well as without. Both are
## exactly 180-degree symmetric (asserted first), so a win here is planning.
const DIFFICULTY_MAPS: Array[String] = ["scrimmage", "ironworks"]
## Adjacent tiers only: each pairing asks whether one step up the ladder is a
## real step. Higher tier second.
const DIFFICULTY_PAIRINGS: Array = [[&"easy", &"normal"], [&"normal", &"hard"]]

const DIFFICULTY_CSV_COLUMNS: Array[String] = [
	"map",
	"seed",
	"low_tier",
	"high_tier",
	"high_side",
	"winner",
	"high_won",
	"termination",
	"day_ended",
	"commands",
	"rejected",
	"cap_stall",
]

## Five 180-degree rotationally-symmetric boards (see _assert_symmetric), so
## neither side gets a terrain or income edge and a first-side bias in the
## results is the doctrines' doing, not the map's.
##
## clash: open and decisive — both armies in reach on day one, so games resolve
## rather than stall into day-cap draws. ridge: the same fairness with more
## terrain between the lines (woods, mountains, four contested cities). combined:
## all three domains at once — an airfield, a port and a shared channel — because
## a doctrine tuned only against tanks is tuned against a third of the game, and
## the hooks that read a unit's move class or domain (Viktor Draeg's breakthrough,
## Nia Rowan's terrain discount, Cassian Rook's heavies) behave differently when
## half the army is not on the ground. holdings gives economy doctrines enough
## income to express their cost curve; channel gives naval doctrines one shared
## ocean around a land bridge where the ground armies still engage immediately.
##
## Its lake is centred, which is what keeps it self-symmetric under the rotation
## while both fleets share one basin — and it is small enough that the land armies
## walk past it rather than around a coast. That last part is not decoration: an
## earlier, larger version of this board separated the armies with water, ground
## to the day cap in 430 of 432 matches, and produced a twenty-point first-side
## bias out of the tiebreak alone. A fixture that does not resolve measures the
## clock, not the doctrines.
##
## The five live in maps/fixtures/ rather than as strings in this file, so the
## Balance Lab can name one with `--map=` and the battle scene can boot one for
## watch mode. That directory is deliberately *not* maps/ itself: MapCatalog
## scans only the top level, so a fixture stays out of the menu, out of the map
## lint, and out of the shipped roster.
const SCENARIO_NAMES: Array[String] = ["clash", "ridge", "combined", "holdings", "channel"]

const CSV_COLUMNS: Array[String] = [
	"scenario",
	"seed",
	"red",
	"blue",
	"winner",
	"termination",
	"day_ended",
	"commands",
	"red_powers",
	"blue_powers",
	"red_first_ready",
	"red_first_fired",
	"blue_first_ready",
	"blue_first_fired",
	"red_units",
	"blue_units",
	"red_props",
	"blue_props",
	"red_funds",
	"blue_funds",
	"rejected",
	"cap_stall",
]

var _harness: BalanceHarness

var _commander_ids: Array[StringName] = []
var _scenario_names: Array[String] = []
var _seed_count := BalanceHarness.DEFAULT_SEEDS
var _days_cap := DEFAULT_DAYS
var _include_neutral := false
var _difficulty_check := false
var _out_dir := ""
## Turns the shared engine cut short at MAX_COMMANDS_PER_TURN, across the whole
## run. Must stay zero: a cut turn resolves differently from the committed report
## this gate stands behind, and neither CSV has a column that would say so.
var _turn_cap_hits := 0


func _init() -> void:
	_harness = BalanceHarness.load_default()
	if not _parse_args():
		quit(2)
		return
	if _difficulty_check:
		_run_difficulty_check()
		return
	for name in _scenario_names:
		if not _assert_symmetric(name):
			return
	var rows := _run_all()
	var summary := _summarise(rows)
	var write_ok := _write_reports(rows, summary)
	_print_summary(summary)
	# Hard invariants only: a rejected command or a cap stall means the AI and the
	# rules disagree, or a match never resolves — both real bugs. Out-of-band win
	# rates are review triggers and never fail the run. A write failure is a
	# third, and it must never be masked by the other two coming back clean.
	var failed: bool = summary["total_rejected"] > 0 or summary["total_cap_stalls"] > 0
	quit(1 if failed or not write_ok else 0)


# --- setup -------------------------------------------------------------------


func _parse_args() -> bool:
	_commander_ids = _all_commander_ids()
	_scenario_names = SCENARIO_NAMES.duplicate()
	for arg in CmdArgs.user():
		if arg.begins_with("--commanders="):
			_commander_ids = _parse_commander_list(arg.get_slice("=", 1))
		elif arg.begins_with("--scenarios="):
			_scenario_names = _parse_scenario_list(arg.get_slice("=", 1))
		elif arg.begins_with("--seeds="):
			_seed_count = BalanceHarness.positive_flag("balance", "--seeds", arg.get_slice("=", 1))
			if _seed_count < 0:
				return false
		elif arg.begins_with("--days="):
			_days_cap = BalanceHarness.positive_flag("balance", "--days", arg.get_slice("=", 1))
			if _days_cap < 0:
				return false
		elif arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
		elif arg == "--neutral":
			_include_neutral = true
		elif arg == "--difficulty-check":
			_difficulty_check = true
	if _out_dir == "":
		_out_dir = "reports/difficulty_check" if _difficulty_check else "reports/commander_balance"
	_out_dir = BalanceHarness.out_flag("balance", _out_dir)
	return _out_dir != ""


## The matrix measures doctrines against each other, so the roster is the
## playable one: "no commander" is a legal seat but not a doctrine, and pairing
## it here would put a control in among the subjects. (The Balance Lab's
## commander sweep does include it, deliberately — there it is the baseline every
## other row is read against.)
func _all_commander_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for co in _harness.commander_db.playable():
		ids.append(co.id)
	return ids


func _parse_commander_list(value: String) -> Array[StringName]:
	var ids: Array[StringName] = []
	for token in value.split(",", false):
		var id := StringName(token.strip_edges())
		if _harness.commander_db.is_playable(id):
			ids.append(id)
		else:
			push_error("balance: unknown commander id '%s', skipping" % id)
	return ids


func _parse_scenario_list(value: String) -> Array[String]:
	var names: Array[String] = []
	for token in value.split(",", false):
		var name := token.strip_edges()
		if name in SCENARIO_NAMES:
			names.append(name)
		else:
			push_error("balance: unknown scenario '%s', skipping" % name)
	return names


## Fails loudly if a scenario is not 180-degree rotationally symmetric with the
## teams swapped: terrain must map onto itself, and every owned cell and unit must
## have a mirror belonging to the other side. A broken map would quietly bias the
## whole run, which is the one thing the paired design exists to prevent.
func _assert_symmetric(name: String) -> bool:
	return _assert_map_symmetric(name, _harness.map_of(name))


## The same check against any already-parsed board, so the difficulty gate can
## hold its committed maps to the identical standard as the embedded scenarios.
func _assert_map_symmetric(name: String, map: MapData) -> bool:
	if map == null:
		return _fatal("cannot load board '%s'" % name)
	var state := GameState.create(map, _harness.unit_db, _harness.chart)
	var w := map.width
	var h := map.height
	for y in h:
		for x in w:
			var a := Vector2i(x, y)
			var b := Vector2i(w - 1 - x, h - 1 - y)
			if map.terrain_at(a).id != map.terrain_at(b).id:
				return _fatal("board '%s' terrain not symmetric at %s vs %s" % [name, a, b])
			if state.owner_at(a) != BalanceMatchEngine.swap_team(state.owner_at(b)):
				return _fatal("board '%s' ownership not mirror-symmetric at %s" % [name, a])
	for unit in state.units:
		var mirror := Vector2i(w - 1 - unit.cell.x, h - 1 - unit.cell.y)
		var twin := state.unit_at(mirror)
		if (
			twin == null
			or twin.team != BalanceMatchEngine.swap_team(unit.team)
			or twin.type.id != unit.type.id
		):
			return _fatal(
				"board '%s' unit %s at %s has no mirror" % [name, unit.type.id, unit.cell]
			)
	return true


func _fatal(message: String) -> bool:
	push_error("balance: " + message)
	quit(2)
	return false


# --- run ---------------------------------------------------------------------


func _run_all() -> Array[Dictionary]:
	var pairings := _pairings()
	var total := pairings.size() * _scenario_names.size() * _seed_count
	print(
		(
			"balance: %d commanders, %d scenarios, %d seeds -> %d matches"
			% [_commander_ids.size(), _scenario_names.size(), _seed_count, total]
		)
	)
	var rows: Array[Dictionary] = []
	var done := 0
	for scenario in _scenario_names:
		for pair in pairings:
			for s in _seed_count:
				# Paired seeds: the same seed set for every pairing, so A-vs-B and
				# B-vs-A (ordered pairs) meet on identical luck and the side-swap is
				# clean. Seeds vary by scenario so the two boards are not correlated.
				var seed_val := BalanceMatchSchedule.seed_at(scenario, s)
				rows.append(_play(scenario, pair[0], pair[1], seed_val))
				done += 1
				if done % 100 == 0:
					print("balance: %d / %d matches" % [done, total])
	return rows


## Every ordered pair, mirrors included (a commander against itself is a control:
## a symmetric board plus a mirror pairing should sit at 50%). Optionally each
## commander against neutral, both sides, as a power-level reference.
func _pairings() -> Array:
	var pairs: Array = []
	for red in _commander_ids:
		for blue in _commander_ids:
			pairs.append([red, blue])
	if _include_neutral:
		for id in _commander_ids:
			pairs.append([id, CommanderType.NEUTRAL_ID])
			pairs.append([CommanderType.NEUTRAL_ID, id])
	return pairs


## Plays one match and tallies the per-match metrics the plan's report calls for.
##
## The loop itself is BalanceMatchEngine's. Both seats use the default profile,
## but each owns its AIController instance, matching the live scene and keeping
## mutable planner state inside one team.
func _play(scenario: String, red: StringName, blue: StringName, seed_val: int) -> Dictionary:
	var unit_db := _harness.unit_db
	var setup := BalanceMatchEngine.Setup.new()
	setup.map = _harness.map_of(scenario)
	setup.unit_db = unit_db
	setup.chart = _harness.chart
	setup.seed_val = seed_val
	setup.days_cap = _days_cap
	setup.commanders = {
		1: _harness.commander_db.by_id(red),
		2: _harness.commander_db.by_id(blue),
	}
	setup.planners = {1: AIController.new(unit_db), 2: AIController.new(unit_db)}
	var outcome := BalanceMatchEngine.play(setup)
	_turn_cap_hits += outcome.turn_cap_hits
	var row := {
		"scenario": scenario,
		"seed": seed_val,
		"red": String(red),
		"blue": String(blue),
		# Not a CSV column — the committed report's shape is fixed — but the seat
		# bias below is measured on non-mirror games, and this is what says which
		# a row is. matches.csv carries the same column in the Balance Lab, so one
		# reading of "is this a mirror?" serves both.
		"mirror": 1 if red == blue else 0,
		"red_powers": outcome.powers[1],
		"blue_powers": outcome.powers[2],
		"red_first_ready": outcome.first_ready[1],
		"red_first_fired": outcome.first_fired[1],
		"blue_first_ready": outcome.first_ready[2],
		"blue_first_fired": outcome.first_fired[2],
	}
	row.merge(BalanceMatchEngine.outcome_row(outcome))
	return row


# --- summary -----------------------------------------------------------------


func _summarise(rows: Array[Dictionary]) -> Dictionary:
	var per_co: Dictionary = {}  # id -> {matches, wins}
	for id in _commander_ids:
		per_co[String(id)] = {"matches": 0, "wins": 0}
	var decisive := 0
	var draws := 0
	var total_rejected := 0
	var total_cap_stalls := 0
	for row in rows:
		total_rejected += int(row["rejected"])
		total_cap_stalls += int(row["cap_stall"])
		var red: String = row["red"]
		var blue: String = row["blue"]
		var winner: int = row["winner"]
		# Each commander's aggregate win rate is already side-normalised: ordered
		# pairs mean every commander plays each opponent from both sides.
		_credit(per_co, red, winner == 1)
		_credit(per_co, blue, winner == 2)
		if winner != 0:
			decisive += 1
		else:
			draws += 1

	var commanders: Array = []
	for id in _commander_ids:
		var key := String(id)
		var stats: Dictionary = per_co[key]
		var rate := 100.0 * float(stats["wins"]) / maxf(1.0, float(stats["matches"]))
		(
			commanders
			. append(
				{
					"id": key,
					"matches": stats["matches"],
					"wins": stats["wins"],
					"win_rate": rate,
					"flag": BalanceRunSummary.band_flag(rate),
				}
			)
		)
	# Worst first, then by id: sort_custom is not stable, so without the second
	# key two commanders on the same rate order by wherever the sort left them,
	# and one more `--commanders=` entry reshuffles rows that did not move.
	commanders.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["win_rate"] != b["win_rate"]:
				return a["win_rate"] < b["win_rate"]
			return a["id"] < b["id"]
	)

	# Mirrors excluded: a commander against itself is this run's control, and the
	# bias figure is read as a caveat on the win rates above, which come from the
	# non-mirror games. BalanceRunSummary.bias owns both readings.
	var seat := BalanceRunSummary.bias(rows, true)
	return {
		"matches": rows.size(),
		"decisive": decisive,
		"draws": draws,
		"total_rejected": total_rejected,
		"total_cap_stalls": total_cap_stalls,
		"red_side_win_pct": seat["red_win_pct"],
		"side_bias_pp": seat["bias_pp"],
		"side_bias_ok": seat["ok"],
		"commanders": commanders,
	}


func _credit(per_co: Dictionary, id: String, won: bool) -> void:
	if not per_co.has(id):
		return
	per_co[id]["matches"] += 1
	if won:
		per_co[id]["wins"] += 1


# --- output ------------------------------------------------------------------


func _write_reports(rows: Array[Dictionary], summary: Dictionary) -> bool:
	var dir := BalanceReportWriter.prepare_dir(_out_dir)
	if dir == "":
		return false
	return BalanceReportWriter.write_run("balance", dir, "matches.csv", rows, CSV_COLUMNS, summary)


## Says out loud when the shared engine had to cut a turn short. Neither report
## has a column for it, and a cut turn moves the numbers this file's two
## committed documents were written from — so silence would look like agreement.
##
## Printed rather than written into matches.csv or summary.json on purpose: both
## are byte-diffed across any change to this runner (plan D1), and a new column
## would break that bar to report something that is zero on every run so far.
func _warn_turn_caps() -> void:
	if _turn_cap_hits == 0:
		return
	print(
		(
			(
				"WARNING: %d turn(s) hit the %d-command per-turn cap and were force-ended. "
				% [_turn_cap_hits, BalanceMatchEngine.MAX_COMMANDS_PER_TURN]
			)
			+ "Those matches did not resolve the way the committed report's did."
		)
	)
	push_warning(
		(
			"balance: %d turn(s) hit the per-turn command cap; the report is not comparable"
			% _turn_cap_hits
		)
	)


func _print_summary(summary: Dictionary) -> void:
	print("\n=== commander balance ===")
	print(
		(
			"matches %d   decisive %d   draws %d   rejected %d   cap-stalls %d"
			% [
				summary["matches"],
				summary["decisive"],
				summary["draws"],
				summary["total_rejected"],
				summary["total_cap_stalls"],
			]
		)
	)
	# The definition is in the label because the Balance Lab prints a line that
	# reads almost the same and counts mirrors — see BalanceRunSummary.bias.
	print(
		(
			"first-side bias (non-mirror decisive games) %+.1f pp (%s, threshold +-%.0f)"
			% [
				summary["side_bias_pp"],
				"ok" if summary["side_bias_ok"] else "REVIEW",
				BalanceRunSummary.MAX_SIDE_BIAS_PP,
			]
		)
	)
	print("commander            win%   n   band")
	for co: Dictionary in summary["commanders"]:
		print("  %-18s %5.1f  %3d  %s" % [co["id"], co["win_rate"], co["matches"], co["flag"]])
	_warn_turn_caps()
	if summary["total_rejected"] > 0 or summary["total_cap_stalls"] > 0:
		print("FAIL: rejected commands or cap stalls — the AI and the rules disagree.")
	else:
		print("hard invariants clean (0 rejected, 0 cap stalls). Band flags are review triggers.")


# --- difficulty check (plan DF4) ---------------------------------------------


## Plays the tier ladder and gates on it: each adjacent pairing on both mirrored
## maps, every seed, from both seats, with no commanders on either side — a
## doctrine would be noise in a measurement of planning alone.
func _run_difficulty_check() -> void:
	for name in DIFFICULTY_MAPS:
		if not _assert_map_symmetric(name, _harness.map_of(name)):
			return
	for pair: Array in DIFFICULTY_PAIRINGS:
		for id: StringName in pair:
			if not _harness.difficulty_db.has(id):
				_fatal("unknown difficulty tier '%s'" % id)
				return

	var total := DIFFICULTY_PAIRINGS.size() * DIFFICULTY_MAPS.size() * _seed_count * 2
	print(
		(
			"difficulty: %d pairings x %d maps x %d seeds x 2 sides -> %d matches"
			% [DIFFICULTY_PAIRINGS.size(), DIFFICULTY_MAPS.size(), _seed_count, total]
		)
	)
	var rows: Array[Dictionary] = []
	var timing: Dictionary = {}
	var done := 0
	for map_name in DIFFICULTY_MAPS:
		for pair: Array in DIFFICULTY_PAIRINGS:
			for s in _seed_count:
				# Paired seeds, same shape as the commander run: both seatings of a
				# pairing meet on identical luck, so the side-swap is clean.
				var seed_val := BalanceMatchSchedule.seed_at(map_name, s)
				for high_is_red: bool in [true, false]:
					rows.append(
						_play_tiers(map_name, pair[0], pair[1], high_is_red, seed_val, timing)
					)
					done += 1
					if done % 10 == 0:
						print("difficulty: %d / %d matches" % [done, total])

	var summary := BalanceRunSummary.difficulty(rows, DIFFICULTY_PAIRINGS, DIFFICULTY_MAPS)
	var turn_times := _turn_times(timing)
	var write_ok := _write_difficulty_reports(rows, summary, turn_times)
	_print_difficulty_summary(summary, turn_times)
	quit(0 if summary["passed"] and write_ok else 1)


## One tier-versus-tier match. `high_is_red` swaps which seat the stronger tier
## takes, and each side gets its own AIController — its own profile, and its own
## per-turn threat map.
func _play_tiers(
	map_name: String,
	low: StringName,
	high: StringName,
	high_is_red: bool,
	seed_val: int,
	timing: Dictionary
) -> Dictionary:
	var red_tier: StringName = high if high_is_red else low
	var blue_tier: StringName = low if high_is_red else high
	var tiers := {1: red_tier, 2: blue_tier}
	var unit_db := _harness.unit_db
	var difficulty_db := _harness.difficulty_db
	var setup := BalanceMatchEngine.Setup.new()
	setup.map = _harness.map_of(map_name)
	setup.unit_db = unit_db
	setup.chart = _harness.chart
	setup.seed_val = seed_val
	setup.days_cap = _days_cap
	setup.tiers = tiers
	setup.planners = {
		1: AIController.new(unit_db, difficulty_db.by_id(red_tier).profile()),
		2: AIController.new(unit_db, difficulty_db.by_id(blue_tier).profile()),
	}
	# No commanders on either side: a doctrine would be noise in a measurement of
	# planning alone (difficulty plan DF4).
	var outcome := BalanceMatchEngine.play(setup)
	_turn_cap_hits += outcome.turn_cap_hits
	_record_time(timing, tiers, outcome)
	var high_team := 1 if high_is_red else 2
	return {
		"map": map_name,
		"seed": seed_val,
		"low_tier": String(low),
		"high_tier": String(high),
		"high_side": "red" if high_is_red else "blue",
		"winner": outcome.winner,
		"high_won": 1 if outcome.winner == high_team else 0,
		"termination": outcome.termination,
		"day_ended": outcome.day_ended,
		"commands": outcome.commands,
		"rejected": outcome.rejected,
		"cap_stall": 1 if outcome.cap_stall else 0,
	}


## Folds one match's planning wall-clock into the per-tier totals, a turn counted
## each time one ends. The only number here that is not reproducible run to run,
## so it is reported and never gated on — it answers R3: does the extra thinking
## cost a perceptible pause? It leaves this runner through timing.json, never
## summary.json: the two reports are the ones byte-diffed across a change (plan
## D1), and a clock inside one of them made that bar unmeetable as stated.
func _record_time(
	timing: Dictionary, tiers: Dictionary, outcome: BalanceMatchEngine.Outcome
) -> void:
	for team: int in tiers:
		var key := String(tiers[team])
		if not timing.has(key):
			timing[key] = {"usec": 0, "turns": 0}
		timing[key]["usec"] += int(outcome.planning_usec.get(team, 0))
		timing[key]["turns"] += int(outcome.planning_turns.get(team, 0))


## Mean planning milliseconds per turn per tier. R3's budget is "no perceptible
## pause versus today", so Normal is the baseline, not any absolute number.
func _turn_times(timing: Dictionary) -> Array:
	var result: Array = []
	for key: String in timing:
		var stats: Dictionary = timing[key]
		var turns := maxi(1, int(stats["turns"]))
		var row := {
			"tier": key,
			"turns": stats["turns"],
			"mean_ms": float(stats["usec"]) / 1000.0 / float(turns),
		}
		result.append(row)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tier"] < b["tier"])
	return result


func _write_difficulty_reports(
	rows: Array[Dictionary], summary: Dictionary, turn_times: Array
) -> bool:
	var dir := BalanceReportWriter.prepare_dir(_out_dir)
	if dir == "":
		return false
	var ok := BalanceReportWriter.write_run(
		"difficulty", dir, "matches.csv", rows, DIFFICULTY_CSV_COLUMNS, summary
	)
	return (
		BalanceReportWriter.write_json(dir.path_join("timing.json"), {"turn_ms": turn_times}) and ok
	)


func _print_difficulty_summary(summary: Dictionary, turn_times: Array) -> void:
	print("\n=== difficulty ladder ===")
	print(
		(
			"matches %d   rejected %d   cap-stalls %d   gate >= %.0f%%"
			% [
				summary["matches"],
				summary["total_rejected"],
				summary["total_cap_stalls"],
				summary["gate_pct"],
			]
		)
	)
	for pairing: Dictionary in summary["pairings"]:
		print(
			(
				"  %-7s over %-7s  %5.1f%%  (%d/%d)  %s"
				% [
					pairing["high"],
					pairing["low"],
					pairing["win_rate"],
					pairing["wins"],
					pairing["played"],
					"ok" if pairing["gate_ok"] else "FAIL",
				]
			)
		)
		for entry: Dictionary in pairing["maps"]:
			print(
				(
					"      on %-11s %5.1f%%  (%d/%d)"
					% [entry["map"], entry["win_rate"], entry["wins"], entry["played"]]
				)
			)
	print("mean AI planning per turn:")
	for entry: Dictionary in turn_times:
		print("  %-7s %7.1f ms over %d turns" % [entry["tier"], entry["mean_ms"], entry["turns"]])
	_warn_turn_caps()
	if summary["passed"]:
		print("PASS: every higher tier clears the gate.")
	else:
		print("FAIL: tune the tier .tres weights (or zero a misbehaving smart) — not this gate.")
