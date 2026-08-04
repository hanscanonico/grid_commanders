class_name AIController
extends RefCounted
## Public façade for an AI-controlled team, one command per call.
##
## The planner is pure simulation logic with no Node dependency. Command Powers
## stay here because they precede every ordinary action; ready-unit competition
## and production are delegated to two coarse collaborators that share one
## scan-stable AIPlanningContext.
##
## Deterministic for a given state: candidate order and strict comparisons are
## preserved by the collaborators, so ties still break by scan order.

var unit_db: UnitDB
## Every number the planners weigh. Never null: an omitted profile falls back to
## the shipped default.
var profile: AIProfile

var _context: AIPlanningContext
var _unit_actions: AIUnitActionPlanner
var _production: AIProductionPlanner


func _init(p_unit_db: UnitDB, p_profile: AIProfile = null) -> void:
	unit_db = p_unit_db
	profile = p_profile if p_profile != null else AIProfile.load_default()
	_context = AIPlanningContext.new(unit_db)
	_unit_actions = AIUnitActionPlanner.new(profile)
	_production = AIProductionPlanner.new(profile)


## The next best command for the current team: an early Command Power,
## highest-scored ready-unit action, production, a late Command Power, then end.
func plan_next_command(state: GameState) -> Command:
	var power := _plan_power(state, CommanderType.Timing.BEFORE_ACTIONS)
	if power != null:
		return power
	_context.begin(state)
	var unit_action := _unit_actions.plan_next(_context)
	if unit_action != null:
		return unit_action
	var build := _production.plan(_context)
	if build != null:
		return build
	power = _plan_power(state, CommanderType.Timing.AFTER_ACTIONS)
	if power != null:
		return power
	return EndTurnCommand.new()


## Fires the Command Power when the meter is full and the commander says the
## moment is right. The timing remains doctrine-owned because each commander
## asks a different board question. Where an aimed power lands is doctrine-owned
## for the same reason and asked here for one more (plan D5): a meteor is not a
## unit, so the planner that scores moves for units never sees it.
func _plan_power(state: GameState, timing: CommanderType.Timing) -> Command:
	var command := PowerCommand.new()
	if command.validate(state) != "":
		return null
	var team := state.current_team
	var commander := state.commander_of(team)
	if commander.power_timing != timing or not commander.wants_power(state, team):
		return null
	if commander.aims_power():
		command.target = commander.power_target(state, team)
	return command
