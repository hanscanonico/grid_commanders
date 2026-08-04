class_name PowerCommand
extends Command
## Fires the current team's Command Power: spends the meter, raises the power,
## and runs its one-shot effects.
##
## Deliberately just another command. It validates and applies like Move or
## Attack, so it lands in the same command log — which means saves, replays and
## the AI pick it up with no special case anywhere.
##
## The power comes down again in one of two places, never here:
## EndTurnCommand for an OWNER_TURN power, TurnRules.begin_turn for a ROUND one.

## The cell an aimed power is pointed at (plan D2) — Hammerfall's square of
## ground, and nothing at all to the powers that fire at the board, which is every
## other one. Set by whoever issues the command: the player through the battle
## scene's aiming state, the computer through `CommanderType.power_target`.
var target: Vector2i = Vector2i.ZERO

## Populated by apply() so the presentation layer can name what just went off.
var team: int = 0
var commander: CommanderType


func validate(state: GameState) -> String:
	if state.winner != 0:
		return "the match is over"
	var co_state := state.commander_state(state.current_team)
	if not co_state.type.has_power():
		return "this commander has no Command Power"
	if co_state.power_active:
		return "a Command Power is already active"
	if co_state.charge < co_state.type.power_cost:
		return "the Command Power is not charged"
	# The only thing an aim can get wrong. Every cell of the board is legal, fog or
	# no fog (plan D3): the sim stays permissive and fog is the presentation's to
	# enforce, so a player may drop a meteor into the dark and hope.
	if not state.map.in_bounds(target):
		return "that target is off the board"
	return ""


func apply(state: GameState) -> void:
	team = state.current_team
	var co_state := state.commander_state(team)
	commander = co_state.type
	# The whole cost, not the whole meter: they are equal today because charge is
	# capped at the cost, but spending the price keeps that a cap rather than a
	# rule the economy quietly depends on.
	co_state.charge = maxi(0, co_state.charge - co_state.type.power_cost)
	co_state.power_active = true
	co_state.type.on_power_activated(state, team, target)
