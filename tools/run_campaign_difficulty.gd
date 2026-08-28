extends SceneTree
## How hard every shipped mission is, measured rather than argued: each one
## played to a verdict with **both** armies driven by the planner at the
## mission's own tier, over N seeds, reporting what the verdict was and how many
## days it took.
##
## It is `tests/unit/test_campaign_soak.gd`'s loop at a measurement's seed count
## and day horizon — same `BattleSetup.build(mission.to_request())`, same
## `CampaignSession` boundary order (apply, then the beats due, then the
## verdict), so what is measured is the mission the game ships rather than a
## shape spelled here. The soak asserts **legality**; this reads **winnability**,
## which is why it is a `tools/` instrument and not a gate: it stays out of
## `make verify` and `make test`, and it edits no content.
##
## **The planner is not a player, and the number is a floor.** A human sees the
## whole board, spends the purse deliberately and does not walk a tank into
## three guns, so a mission the planner loses may still be fair and a mission it
## wins comfortably is certainly fair. So read a 0% column as "look at this one",
## never as "this mission is impossible", and read `median_win_day` against a
## deadline as the only hard claim in the table: a clock the planner cannot beat
## on the seat it is playing is a clock authored against a stopwatch nobody
## measured.
##
## Usage (headless; see `make campaign-difficulty`):
##   Godot --headless --path . -s res://tools/run_campaign_difficulty.gd -- [flags]
##     --campaign=six_marshals   one war rather than all six (repeatable slug)
##     --mission=sm03_the_long_watch   one mission, for iterating on an edit
##     --seeds=6         matches per mission (default 6)
##     --seed-offset=0   first seed skipped, so a rerun can extend a sample
##     --days=24         day horizon; a mission still running at it is counted
##                       undecided rather than lost
##     --out=reports/campaign_difficulty   output directory (default shown)
##
## Writes missions.csv and summary.json under --out (gitignored) and prints the
## table `docs/campaign_difficulty.md` is written from.

const TOOL := "campaign-difficulty"
const DEFAULT_OUT := "reports/campaign_difficulty"

const CSV_COLUMNS: Array[String] = [
	"campaign",
	"mission",
	"tier",
	"seeds",
	"wins",
	"losses",
	"undecided",
	"win_pct",
	"median_win_day",
	"deadline",
	"par_day",
	"opening_odds",
	"opening_income",
	"top_reason",
]

## The `CampaignSession` autoload, fetched from the tree rather than named.
## A `-s` script is loaded before the project's autoloads are registered as
## script globals, so the identifier does not compile here — the node itself is
## up by `_initialize`, and it is the same singleton the battle scene drives.
var _session: Node

var _terrain_db: TerrainDB
var _unit_db: UnitDB
var _commander_db: CommanderDB
var _db: CampaignDB

var _campaigns: Array[String] = []
var _missions: Array[String] = []
var _seed_count := 6
var _seed_offset := 0
var _days_cap := 24
var _out_dir := ""


func _initialize() -> void:
	if not _parse_args():
		quit(2)
		return
	_session = root.get_node(^"CampaignSession")
	_terrain_db = TerrainDB.load_default()
	_unit_db = UnitDB.load_default()
	_commander_db = CommanderDB.load_default()
	_db = CampaignDB.load_default()
	var rows: Array[Dictionary] = []
	for campaign in _db.all():
		if not _campaigns.is_empty() and not String(campaign.id) in _campaigns:
			continue
		for mission: MissionDefinition in campaign.missions:
			if not _missions.is_empty() and not String(mission.id) in _missions:
				continue
			var row := _measure(campaign, mission)
			if row.is_empty():
				push_error("%s: %s/%s would not build" % [TOOL, campaign.id, mission.id])
				quit(1)
				return
			rows.append(row)
			_print_row(row)
	if rows.is_empty():
		push_error("%s: --campaign / --mission named nothing that ships" % TOOL)
		quit(2)
		return
	_report(rows)
	quit(0)


## Returns false on any bad flag rather than quietly measuring something else,
## the policy every instrument in `tools/` states: a mistyped `--seeds=` here
## costs the whole 108-mission sweep.
func _parse_args() -> bool:
	for arg in CmdArgs.user():
		if arg.begins_with("--campaign="):
			_campaigns.append(arg.get_slice("=", 1))
		elif arg.begins_with("--mission="):
			_missions.append(arg.get_slice("=", 1))
		elif arg.begins_with("--seeds="):
			_seed_count = BalanceHarness.positive_flag(TOOL, "--seeds", arg.get_slice("=", 1))
			if _seed_count < 0:
				return false
		elif arg.begins_with("--seed-offset="):
			_seed_offset = BalanceHarness.count_flag(TOOL, "--seed-offset", arg.get_slice("=", 1))
			if _seed_offset < 0:
				return false
		elif arg.begins_with("--days="):
			_days_cap = BalanceHarness.positive_flag(TOOL, "--days", arg.get_slice("=", 1))
			if _days_cap < 0:
				return false
		elif arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
		else:
			push_error("%s: unknown flag '%s'" % [TOOL, arg])
			return false
	if _out_dir == "":
		_out_dir = DEFAULT_OUT
	_out_dir = BalanceHarness.out_flag(TOOL, _out_dir)
	return _out_dir != ""


## One mission over the whole seed range, folded into the row the table prints.
func _measure(campaign: CampaignDefinition, mission: MissionDefinition) -> Dictionary:
	var wins := 0
	var losses := 0
	var undecided := 0
	var win_days: Array[int] = []
	var reasons: Dictionary[String, int] = {}
	var opening := _opening(mission)
	for i in _seed_count:
		var play := _play(campaign, mission, _seed_offset + i + 1)
		if play.is_empty():
			return {}
		match String(play["status"]):
			"win":
				wins += 1
				win_days.append(int(play["day"]))
			"loss":
				losses += 1
				var reason: String = play["reason"]
				reasons[reason] = reasons.get(reason, 0) + 1
			_:
				undecided += 1
				reasons["(still running)"] = reasons.get("(still running)", 0) + 1
	return {
		"campaign": String(campaign.id),
		"mission": String(mission.id),
		"tier": String(mission.difficulty),
		"seeds": _seed_count,
		"wins": wins,
		"losses": losses,
		"undecided": undecided,
		"win_pct": 100.0 * float(wins) / float(_seed_count),
		"median_win_day": _median(win_days),
		"deadline": _deadline_of(mission),
		"par_day": mission.par_day,
		"opening_odds": float(opening["odds"]),
		"opening_income": float(opening["income"]),
		"top_reason": _top(reasons),
	}


## What the player's side opens with, as a fraction of what stands against it:
## `odds` is army value (`BalanceMatchEngine.army_value`) and `income` is
## property count, both on the board the mission opens on and both read before a
## command.
##
## The two numbers in the row the planner cannot skew: they are the content an
## author typed. A mission the planner never wins **and** that opens at a
## fraction of the enemy's weight is a mission to look at; one that opens level
## and is still lost is far more likely to be the planner playing badly, which is
## what stops this table recommending edits to fair boards. `income` is the
## slower of the two and the one that compounds: a side that opens level and
## earns half as much is behind by the middle of every mission it plays.
func _opening(mission: MissionDefinition) -> Dictionary:
	var built := BattleSetup.build(mission.to_request(), _terrain_db, _unit_db, _commander_db)
	if built == null:
		return {"odds": 0.0, "income": 0.0}
	var game := built.game
	var ours := 0
	var theirs := 0
	var our_props := 0
	var their_props := 0
	for team in game.teams:
		var value := BalanceMatchEngine.army_value(game, team)
		var props := game.properties_of(team).size()
		if game.allied(team, mission.player_team):
			ours += value
			our_props += props
		else:
			theirs += value
			their_props += props
	return {
		"odds": 0.0 if theirs == 0 else float(ours) / float(theirs),
		"income": 0.0 if their_props == 0 else float(our_props) / float(their_props),
	}


## One mission, one seed, played the way the live scene plays it: the mission's
## own launch, the carried army stood, the opening board taken as the tally's
## baseline, and every boundary firing the beats due before the verdict.
##
## The player's seat is the planner's too, which is the whole caveat on this
## file. A refused command is a soak failure rather than a difficulty one, so it
## is reported loudly and the match is abandoned — `test_campaign_soak.gd` is
## where that bar is held.
func _play(campaign: CampaignDefinition, mission: MissionDefinition, seed_val: int) -> Dictionary:
	var built := BattleSetup.build(mission.to_request(), _terrain_db, _unit_db, _commander_db)
	if built == null:
		return {}
	var game := built.game
	game.rng.seed = seed_val
	_session.begin(campaign, mission, CampaignState.new())
	_session.deploy_army(game)
	_session.open_board(game)
	_fire_due(game)
	var planners: Dictionary[int, AIController] = {}
	for team in game.teams:
		planners[team] = AIController.new(_unit_db, built.difficulty.profile())
	var ceiling := BalanceMatchEngine.command_ceiling(_days_cap, game.teams.size())
	var commands := 0
	while _session.outcome == null and game.winner == 0 and game.day <= _days_cap:
		if commands >= ceiling:
			break
		var command := planners[game.current_team].plan_next_command(game)
		if command.validate(game) != "":
			push_error(
				(
					"%s: %s/%s seed %d: the planner's command was refused"
					% [TOOL, campaign.id, mission.id, seed_val]
				)
			)
			break
		command.apply(game)
		commands += 1
		_fire_due(game)
		_session.decide(game)
	var result := _verdict(game)
	_session.clear()
	return result


## The verdict as this instrument records it. A mission the runtime never
## decided is "undecided" rather than a loss: the horizon is the instrument's,
## not the mission's, and counting the cap as a defeat would report the flag
## `--days=` was set to.
func _verdict(game: GameState) -> Dictionary:
	var outcome: MissionRuntime.Outcome = _session.outcome
	if outcome == null:
		return {"status": "undecided", "day": game.day, "reason": ""}
	if outcome.status == MissionRuntime.Status.SUCCESS:
		return {"status": "win", "day": outcome.day, "reason": outcome.reason}
	return {"status": "loss", "day": game.day, "reason": outcome.reason}


func _fire_due(game: GameState) -> void:
	for event: MissionEvent in _session.due_events(game):
		if game.winner != 0:
			return
		var command := MissionEventCommand.new(event, _session.mission.player_team)
		if command.validate(game) != "":
			return
		command.apply(game)
		_session.record_event(command)


## The mission's clock, or 0 for one with none — read off the failure list
## through the objective's own field, never off the briefing copy.
func _deadline_of(mission: MissionDefinition) -> int:
	for failure: MissionObjective in mission.failures:
		if failure is DayDeadlineObjective:
			return (failure as DayDeadlineObjective).last_day
	return 0


func _median(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _top(reasons: Dictionary[String, int]) -> String:
	var best := ""
	var best_count := 0
	for reason: String in reasons:
		if reasons[reason] > best_count:
			best = reason
			best_count = reasons[reason]
	return best


func _print_row(row: Dictionary) -> void:
	print(
		(
			"%-18s %-32s %-7s win %3.0f%%  day %2d  deadline %2d  odds %4.2f  income %4.2f  %s"
			% [
				row["campaign"],
				row["mission"],
				row["tier"],
				row["win_pct"],
				row["median_win_day"],
				row["deadline"],
				row["opening_odds"],
				row["opening_income"],
				row["top_reason"],
			]
		)
	)


func _report(rows: Array[Dictionary]) -> void:
	var flagged: Array[Dictionary] = []
	for row in rows:
		if _is_flagged(row):
			flagged.append(row)
	var summary := {
		"missions": rows.size(),
		"seeds": _seed_count,
		"seed_offset": _seed_offset,
		"days_cap": _days_cap,
		"never_won": rows.filter(func(r: Dictionary) -> bool: return int(r["wins"]) == 0).size(),
		"flagged": flagged.map(func(r: Dictionary) -> String: return r["mission"]),
	}
	var dir := BalanceReportWriter.prepare_dir(_out_dir)
	if dir != "":
		BalanceReportWriter.write_run(TOOL, dir, "missions.csv", rows, CSV_COLUMNS, summary)
	print("")
	print(
		(
			"%s: %d missions, %d seeds each, %d-day horizon"
			% [TOOL, rows.size(), _seed_count, _days_cap]
		)
	)
	print("%s: %d never won by the planner" % [TOOL, summary["never_won"]])
	print(
		(
			"%s: %d flagged (never won, or a deadline at or under the median win)"
			% [TOOL, flagged.size()]
		)
	)
	for row in flagged:
		_print_row(row)


## What the table asks a human to look at: a mission the planner never won, or a
## clock it cannot beat even when it wins. The second is the sharper of the two,
## because it is a claim about the authored number rather than about the planner.
func _is_flagged(row: Dictionary) -> bool:
	if int(row["wins"]) == 0:
		return true
	var deadline := int(row["deadline"])
	return deadline > 0 and deadline <= int(row["median_win_day"])
