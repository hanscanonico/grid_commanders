class_name FourArmyLoop
extends RefCounted
## One headless match on a board with more than two armies, played by the
## planner on every seat. `BalanceMatchEngine` plays exactly two sides by design
## (asymmetric-board plan R4), so the instruments that read a four-army board —
## `tools/run_bulwark_measure.gd`'s win spread and `tools/run_mobile_soak.gd`'s
## planner clock — cannot be presets over it. This is the loop they share, so
## the two cannot drift: the same per-turn safety net, the same refusal, one
## `AIController` per army so no two share a turn's cached threat map.
##
## Node-free like the rest of `tools/balance/`, and it decides nothing about a
## report: it plays a match and hands back what happened.


## Plays one match and returns `{state, commands, rejected, turn_cap_hits,
## cap_stall}` — an empty dictionary when the board cannot be seated at all.
##
## `label` names this match in the refusal a rejected command raises — the
## caller's own run ("alliance", a tier id), since a driver plays several and the
## board alone would not say which one refused.
##
## `on_command` is called once per issued command with the microseconds
## `plan_next_command` spent and whether the command being applied ends the
## turn, which is how the soak reads its clock without a stopwatch in here.
static func play(
	map: MapData,
	harness: BalanceHarness,
	profile: AIProfile,
	sides: Dictionary[int, int],
	seed_val: int,
	days_cap: int,
	label: String,
	on_command: Callable = Callable(),
	fog: bool = false
) -> Dictionary:
	var state := GameState.create(map, harness.unit_db, harness.chart)
	if state == null:
		return {}
	state.sides = sides
	state.fog_enabled = fog
	state.rng.seed = seed_val
	var planners: Dictionary = {}
	for team in state.teams:
		planners[team] = AIController.new(harness.unit_db, profile)
	var cap := BalanceMatchEngine.command_ceiling(days_cap, state.teams.size())
	var commands := 0
	var rejected := 0
	var turn_cap_hits := 0
	var commands_this_turn := 0
	while state.winner == 0 and state.day <= days_cap and commands < cap:
		var team: int = state.current_team
		var ai: AIController = planners[team]
		var started := Time.get_ticks_usec()
		var command := ai.plan_next_command(state)
		var spent := Time.get_ticks_usec() - started
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
					"%s %s seed %d (day %d, team %d): %s"
					% [map.source_path, label, seed_val, state.day, team, error]
				)
			)
			command = EndTurnCommand.new()
			if command.validate(state) != "":
				break
		commands_this_turn = 0 if command is EndTurnCommand else commands_this_turn + 1
		if on_command.is_valid():
			on_command.call(spent, command is EndTurnCommand)
		command.apply(state)
		commands += 1
	return {
		"state": state,
		"commands": commands,
		"rejected": rejected,
		"turn_cap_hits": turn_cap_hits,
		"cap_stall": 1 if (state.winner == 0 and commands >= cap) else 0,
	}


## True when `grouping` reads as a seating this loop can be played under: `ffa`,
## or the `--sides=` grammar such as 1+2+3v4. `options` names the caller's own
## alternatives in the refusal, a board with a named preset having more of them.
static func grouping_readable(tool: String, grouping: String, options: String) -> bool:
	if grouping == "ffa":
		return true
	for token in grouping.split("v", false):
		for seat in token.split("+", false):
			if not seat.strip_edges().is_valid_int():
				push_error("%s: --grouping is %s (got '%s')" % [tool, options, grouping])
				return false
	return true


## Mean and median over the values a run banked — the match lengths that
## resolved, the milliseconds a command took. An empty sample reports 0.0, which
## the count reported beside it is what tells apart from a real average.
static func mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[mid])
	return 0.5 * (float(sorted[mid - 1]) + float(sorted[mid]))
