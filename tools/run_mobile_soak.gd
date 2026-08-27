extends SceneTree
## The mobile soak's desktop baseline (mobile plan MB8 / MOB-13): the three
## clocks a phone build is suspected of being slow on, measured here so the
## device reading has something to be compared against.
##
## MB8 is a hand-played soak on hardware — backgrounding, audio interruption,
## rotation refusal, a control off screen — and none of that is measurable from
## a desk. What *is* measurable, and what the plan asks for a number on, is:
##
##   planner   how long one computer command and one whole computer turn take
##             to plan, on the board and seat count that costs the most (R5:
##             "60-400 ms per computer turn, on the main thread, per computer
##             seat", estimated from docs/difficulty_check.md and never measured
##             as a per-turn distribution).
##   replay    what the recorder's per-command append costs, since it flushes to
##             storage once per applied command (core/replay_file.gd) and flash
##             is not an SSD.

## The board's own per-frame cost is deliberately NOT here: `UnitSprite` and
## `BoardBeat` read the `Settings` autoload, which a `-s` script does not have,
## so a beat timed from this side would be timing the harness. docs/mobile_soak.md
## records how the frame clock is read instead — the real scene, headless, with
## `--print-fps`.
##
## It is an instrument, not a gate: out of `make verify` and `make test`, it
## tunes nothing, and it writes nothing but the scratch file the storage clock
## times and then removes. docs/mobile_soak.md is the committed record, and —
## like every instrument doc here — a later measurement supersedes it wholesale
## rather than editing it.
##
## Nothing under `core/` or `ai/` learns this exists: the planner loop is
## `tools/balance/four_army_loop.gd`, wrapped in a clock.
##
## Usage (headless; see `make mobile-soak`):
##   Godot --headless --path . -s res://tools/run_mobile_soak.gd -- [flags]
##     --sections=planner,replay          which clocks to read (default both)
##     --map=bulwark      board the planner clock is read on (default bulwark)
##     --tier=all         a shipped tier, or `all` for every one of them
##     --grouping=1+2+3v4 sides in the `--sides=` grammar, or `ffa`
##     --seeds=2          matches per tier
##     --days=20          day horizon per match — a soak reads the opening days,
##                        which is where a four-army board is busiest
##     --fog=on           fog on by default: the AR1 plan cache is inert with fog
##                        on, so this is the clock the live game runs
##     --appends=200      replay lines written for the storage clock
const TOOL := "mobile-soak"
const DEFAULT_MAP := "bulwark"
const DEFAULT_GROUPING := "1+2+3v4"
## The one grouping that is not seats: `MatchRequest.parse_sides_flag` reads the
## empty grammar as a free-for-all, and `ffa` is what a reader types for it.
const FREE_FOR_ALL := "ffa"
const ALL_SECTIONS: Array[String] = ["planner", "replay"]
## Where the storage clock writes: `user://`, the storage the recorder writes to,
## but deliberately beside the player's rotating slots rather than inside them —
## a run interrupted mid-clock would otherwise leave a file in `ReplayFile.DIR`
## that the next match's `prune` counts against `KEEP` and evicts a real
## recording for.
const REPLAY_PROBE := "user://mobile_soak_probe.jsonl"
## What `--grouping` takes, as a refusal names them.
const GROUPING_OPTIONS := "ffa or a grouping like 1+2+3v4"

var _harness: BalanceHarness
var _map: MapData
var _tiers: DifficultyDB

var _sections: Array[String] = ALL_SECTIONS.duplicate()
var _map_name := DEFAULT_MAP
var _tier_id := "all"
var _grouping := DEFAULT_GROUPING
var _seed_count := 2
var _days_cap := 20
var _fog := true
var _append_count := 200

## What the running match has spent planning this turn, banked by the loop's
## per-command callback: a lambda captures a local by value, so the clock's own
## running total lives here.
var _turn_ms := 0.0


func _init() -> void:
	if not _parse_args():
		quit(2)
		return
	_harness = BalanceHarness.load_default()
	_tiers = DifficultyDB.load_default()
	_map = _harness.map_of(_map_name)
	if _map == null:
		quit(2)
		return
	print("%s — %s, %s" % [TOOL, OS.get_name(), Engine.get_version_info()["string"]])
	if "planner" in _sections:
		_planner_section()
	if "replay" in _sections:
		_replay_section()
	quit(0)


func _parse_args() -> bool:
	for arg in CmdArgs.user():
		if arg.begins_with("--sections="):
			_sections.clear()
			for name in arg.get_slice("=", 1).split(",", false):
				var section := name.strip_edges()
				if not section in ALL_SECTIONS:
					push_error(
						(
							"%s: --sections is any of %s (got '%s')"
							% [TOOL, ", ".join(ALL_SECTIONS), section]
						)
					)
					return false
				_sections.append(section)
		elif arg.begins_with("--map="):
			_map_name = arg.get_slice("=", 1)
		elif arg.begins_with("--tier="):
			_tier_id = arg.get_slice("=", 1)
		elif arg.begins_with("--grouping="):
			_grouping = arg.get_slice("=", 1)
		elif arg.begins_with("--seeds="):
			_seed_count = _positive(arg)
			if _seed_count < 0:
				return false
		elif arg.begins_with("--days="):
			_days_cap = _positive(arg)
			if _days_cap < 0:
				return false
		elif arg.begins_with("--appends="):
			_append_count = _positive(arg)
			if _append_count < 0:
				return false
		elif arg.begins_with("--fog="):
			_fog = arg.get_slice("=", 1) in ["on", "true", "1"]
		else:
			push_error("%s: unknown flag '%s'" % [TOOL, arg])
			return false
	return _sections.size() > 0 and _grouping_readable()


## -1 for a value that is not a positive integer, so the caller refuses the run:
## a horizon that quietly fell back to its default would be a reading of a
## different question than the one asked for.
func _positive(arg: String) -> int:
	var parsed := BalanceHarness.int_flag(arg.get_slice("=", 1), 1)
	if parsed < 0:
		push_error(
			(
				"%s: %s takes a positive integer (got '%s')"
				% [TOOL, arg.get_slice("=", 0), arg.get_slice("=", 1)]
			)
		)
	return parsed


## Refused here rather than at the board, because `parse_sides_flag` answers an
## unreadable grouping with a free-for-all: the run would be timed on a seating
## nobody asked for, under a heading naming the one they did.
func _grouping_readable() -> bool:
	return FourArmyLoop.grouping_readable(TOOL, _grouping, GROUPING_OPTIONS)


# --- the planner clock -------------------------------------------------------


## Every shipped tier, or the one named. `all` is the default because R5's claim
## is about the ladder rather than about a tier.
func _tier_ids() -> Array[String]:
	if _tier_id != "all":
		return [_tier_id]
	var ids: Array[String] = []
	for tier in _tiers.all():
		ids.append(String(tier.id))
	return ids


func _planner_section() -> void:
	print(
		(
			"\n== planner clock — %s, %s, fog %s, %d seeds x %d days =="
			% [_map_name, _grouping, "on" if _fog else "off", _seed_count, _days_cap]
		)
	)
	print("tier      seats  commands  cmd_mean  cmd_p50  cmd_p90  cmd_max  turn_mean  turn_max")
	for id in _tier_ids():
		if not _tiers.has(StringName(id)):
			push_error("%s: no tier '%s'" % [TOOL, id])
			continue
		var profile := _tiers.by_id(StringName(id)).profile()
		var commands: Array[float] = []
		var turns: Array[float] = []
		var seats := 0
		for i in _seed_count:
			seats = _play(id, profile, i + 1, commands, turns)
		print(
			(
				"%-9s %5d %9d %9.1f %8.1f %8.1f %8.1f %10.1f %9.1f"
				% [
					id,
					seats,
					commands.size(),
					FourArmyLoop.mean(commands),
					_percentile(commands, 0.5),
					_percentile(commands, 0.9),
					_max(commands),
					FourArmyLoop.mean(turns),
					_max(turns)
				]
			)
		)


## One match through `FourArmyLoop` — the loop the board measurement plays, one
## AIController per army, neutral commanders, the same per-turn safety net —
## with a clock hung off its per-command callback and the result thrown away:
## this measures how long the board takes to think, never who wins. Returns the
## seat count it played.
func _play(
	tier: String, profile: AIProfile, seed_val: int, commands: Array[float], turns: Array[float]
) -> int:
	var sides: Dictionary[int, int] = {}
	var parsed := MatchRequest.parse_sides_flag("" if _grouping == FREE_FOR_ALL else _grouping)
	for seat: int in parsed:
		sides[seat] = int(parsed[seat])
	_turn_ms = 0.0
	var clock := func(spent_usec: int, ends_turn: bool) -> void:
		var spent := float(spent_usec) / 1000.0
		commands.append(spent)
		_turn_ms += spent
		if ends_turn:
			turns.append(_turn_ms)
			_turn_ms = 0.0
	var played := FourArmyLoop.play(
		_map, _harness, profile, sides, seed_val, _days_cap, tier, clock, _fog
	)
	if played.is_empty():
		return 0
	var state: GameState = played["state"]
	return state.teams.size()


# --- the storage clock -------------------------------------------------------


## What the recorder costs per applied command. `ReplayFile.append` stores one
## line and flushes it, and the flush is the whole point of the measurement: on
## a phone that is a write to flash rather than to a page cache backed by an
## SSD. The line written is a real encoded command, so its length is the length
## the recorder actually writes.
func _replay_section() -> void:
	print("\n== replay recorder clock — %d appends ==" % _append_count)
	var state := GameState.create(_map, _harness.unit_db, _harness.chart)
	if state == null:
		return
	var line := ReplayCodec.encode_command(state, EndTurnCommand.new())
	var file := ReplayFile.open_at(REPLAY_PROBE)
	if file == null:
		push_error("%s: could not open %s" % [TOOL, REPLAY_PROBE])
		return
	var spents: Array[float] = []
	for i in _append_count:
		var started := Time.get_ticks_usec()
		file.append(line)
		spents.append(float(Time.get_ticks_usec() - started) / 1000.0)
	file.close()
	var bytes := 0
	var written := FileAccess.open(REPLAY_PROBE, FileAccess.READ)
	if written != null:
		bytes = int(written.get_length())
		written.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REPLAY_PROBE))
	print("line bytes: %d   file bytes: %d" % [JSON.stringify(line).length() + 1, bytes])
	print(
		(
			"append ms  mean %.3f  p50 %.3f  p90 %.3f  p99 %.3f  max %.3f"
			% [
				FourArmyLoop.mean(spents),
				_percentile(spents, 0.5),
				_percentile(spents, 0.9),
				_percentile(spents, 0.99),
				_max(spents)
			]
		)
	)


# --- arithmetic --------------------------------------------------------------


func _max(values: Array[float]) -> float:
	var top := 0.0
	for value in values:
		top = maxf(top, value)
	return top


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := int(floor(fraction * float(sorted.size() - 1)))
	return sorted[clampi(index, 0, sorted.size() - 1)]
