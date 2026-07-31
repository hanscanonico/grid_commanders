class_name AIUnitActionPlanner
extends RefCounted
## Chooses the highest-scored action from the current team's ready units.
##
## Greedy, deterministic, and deliberately coarse: combat, capture, diving,
## retreat, and fallback movement stay together because they compete for one
## UnitPlan score. AIController remains the public façade.


class UnitPlan:
	var command: Command
	var score: float = -INF


var profile: AIProfile


func _init(p_profile: AIProfile) -> void:
	profile = p_profile


func plan_next(context: AIPlanningContext) -> Command:
	var best: Command = null
	var best_score := -INF
	for unit in context.ready_units:
		var plan := _best_unit_plan(context, unit)
		if plan.score > best_score:
			best_score = plan.score
			best = plan.command
	return best


func _best_unit_plan(context: AIPlanningContext, unit: Unit) -> UnitPlan:
	var plan := UnitPlan.new()
	var reachable := MovementResolver.reachable(context.state, unit)
	_consider_attacks(context, unit, reachable, plan)
	_consider_captures(context.state, unit, reachable, plan)
	_consider_dive(context, unit, plan)
	if plan.score < profile.min_useful_score:
		plan.command = _advance_command(context, unit, reachable)
		plan.score = profile.advance_score
	return plan


func _consider_attacks(
	context: AIPlanningContext, unit: Unit, reachable: MovementResolver.MoveRange, plan: UnitPlan
) -> void:
	var state := context.state
	if unit.type.max_range <= 0 or state.damage_chart == null:
		return
	var dests: Array[Vector2i] = []
	if AttackRange.is_indirect(unit):
		dests = [unit.cell]  # indirect units cannot move and fire
	else:
		for cell in reachable.cells():
			if reachable.can_stop_at(cell):
				dests.append(cell)
	# One threat map for the whole sweep. Still resolved on first need rather
	# than up front, so a unit with nothing in reach builds nothing.
	var threat: ThreatMap = null
	for dest in dests:
		# The walk to a firing cell and the fire it invites depend only on that
		# cell, so work them out once per destination and only after finding a
		# legal target there.
		var dest_penalty := -1.0
		for enemy in context.visible_enemies:
			if not AttackRange.covers(state, unit, dest, enemy.cell):
				continue
			if not AttackRange.can_fire(state, unit, enemy):
				continue
			if dest_penalty < 0.0:
				if threat == null and profile.threat_aversion > 0.0:
					threat = context.threat_map()
				var step_cost: int = reachable.costs[dest]
				dest_penalty = (
					profile.step_cost_penalty * step_cost
					+ _threat_penalty(state, unit, dest, threat)
				)
			var forecast := CombatResolver.forecast(state, unit, dest, enemy)
			var score: float = (
				_attack_score(unit, enemy, forecast)
				+ _focus_bonus(context, unit, enemy, forecast)
				+ _defend_bonus(state, unit, enemy)
				- dest_penalty
			)
			if score > plan.score:
				plan.score = score
				plan.command = AttackCommand.new(unit, reachable.path_to(dest), enemy.cell)


## Expected damage value (target cost x damage fraction, kill-boosted) minus
## discounted counter risk against our own cost.
func _attack_score(unit: Unit, enemy: Unit, forecast: CombatResolver.Forecast) -> float:
	if not forecast.can_attack:
		return -INF
	var damage := mini(forecast.attack_damage, enemy.hp)
	var value := float(enemy.type.cost) * damage / 100.0
	if forecast.attack_damage >= enemy.hp:
		value *= profile.kill_bonus
	var risk := 0.0
	if forecast.counter_damage > 0:
		var counter := mini(forecast.counter_damage, unit.hp)
		risk = float(unit.type.cost) * counter / 100.0 * profile.counter_weight
		if forecast.counter_damage >= unit.hp:
			risk *= 2.0
	return value - risk


## What firing from `cell` costs `unit` in expected incoming damage next turn,
## in the same cost-scaled currency an attack's value uses.
func _threat_penalty(state: GameState, unit: Unit, cell: Vector2i, threat: ThreatMap) -> float:
	if threat == null:
		return 0.0
	var incoming := threat.incoming_damage(state, unit, cell)
	return profile.threat_aversion * float(unit.type.cost) * incoming / 100.0


## How much more attractive `enemy` is because other ready friendlies could
## still pile onto it this turn. Zero when focus fire is off or this shot kills.
func _focus_bonus(
	context: AIPlanningContext, unit: Unit, enemy: Unit, forecast: CombatResolver.Forecast
) -> float:
	if profile.focus_fire_bonus <= 0.0:
		return 0.0
	var remaining := enemy.hp - forecast.attack_damage
	if remaining <= 0:
		return 0.0
	var follow_up := mini(remaining, _follow_up_damage(context, unit, enemy))
	if follow_up <= 0:
		return 0.0
	var value := float(enemy.type.cost) * mini(forecast.attack_damage, enemy.hp) / 100.0
	return profile.focus_fire_bonus * value * float(follow_up) / float(remaining)


## Summed forecast damage other ready friendlies could deal `enemy` this turn.
## Reach is the same Manhattan over-estimate commander powers use; forecasts are
## luck-free and draw no RNG.
func _follow_up_damage(context: AIPlanningContext, attacker: Unit, enemy: Unit) -> int:
	var state := context.state
	var total := 0
	for friendly in context.friendly_units:
		if friendly == attacker or friendly.acted or friendly.carrier != null:
			continue
		if friendly.type.max_range <= 0:
			continue
		if not AttackRange.can_fire(state, friendly, enemy):
			continue  # no chart entry, no loaded weapon, or the target is dived
		var reach := AttackRange.maximum(state, friendly)
		if not AttackRange.is_indirect(friendly):
			reach += MovementResolver.move_budget(state, friendly)
		if absi(friendly.cell.x - enemy.cell.x) + absi(friendly.cell.y - enemy.cell.y) > reach:
			continue
		var forecast := CombatResolver.forecast(state, friendly, friendly.cell, enemy)
		if forecast.can_attack:
			total += forecast.attack_damage
	return total


## What shooting `enemy` off ground our own side holds is worth, on top of what
## the shot is worth on its own. Priced off the capture list read backwards (D3):
## the property is worth what taking it is worth, the progress already chipped
## out of us is worth what chipping it is worth, and a home HQ multiplies both
## because losing that one ends the army.
##
## Only a capture-capable enemy counts. A tank parked on our city takes nothing
## from us, and the danger it poses is the threat map's job — paying for it here
## as well would price one fear twice.
func _defend_bonus(state: GameState, unit: Unit, enemy: Unit) -> float:
	if profile.defend_weight <= 0.0 or not enemy.type.can_capture:
		return 0.0
	var cell := enemy.cell
	if not state.map.terrain_at(cell).is_property:
		return 0.0
	# Through the allegiance authority, never `owner == unit.team`: an ally's city
	# is the side's city, and neutral ground is nobody's to lose.
	var owner := state.owner_at(cell)
	if not state.allied(owner, unit.team):
		return 0.0
	var score := profile.capture_score
	# Asked of the home-HQ authority, never of the terrain id: an HQ a survivor
	# conquered fells nobody, so defending it is worth a city and no more.
	if state.home_hq.has(owner) and state.home_hq[owner] == cell:
		score *= profile.hq_capture_multiplier
	var points: int = state.capture_progress.get(cell, GameState.CAPTURE_POINTS)
	score += (GameState.CAPTURE_POINTS - points) * profile.capture_progress_bonus
	return profile.defend_weight * score


func _consider_captures(
	state: GameState, unit: Unit, reachable: MovementResolver.MoveRange, plan: UnitPlan
) -> void:
	if not unit.type.can_capture:
		return
	for cell in reachable.cells():
		if not reachable.can_stop_at(cell):
			continue
		var terrain := state.map.terrain_at(cell)
		# Through the allegiance authority, not `== unit.team`: an ally's ground is
		# already the side's, and `CaptureCommand` turns the attempt down.
		if not terrain.is_property or state.allied(state.owner_at(cell), unit.team):
			continue
		var score := profile.capture_score
		if terrain.id == &"hq":
			score *= profile.hq_capture_multiplier
		var points: int = state.capture_progress.get(cell, GameState.CAPTURE_POINTS)
		var step_cost: int = reachable.costs[cell]
		score += (GameState.CAPTURE_POINTS - points) * profile.capture_progress_bonus
		score -= profile.step_cost_penalty * step_cost
		if score > plan.score:
			plan.score = score
			plan.command = CaptureCommand.new(unit, reachable.path_to(cell))


## A submarine's one decision: whether to be under the water.
func _consider_dive(context: AIPlanningContext, unit: Unit, plan: UnitPlan) -> void:
	var state := context.state
	if not unit.type.can_dive or state.damage_chart == null:
		return
	var threatened := _threatened_by(context, unit, false)
	var wants: bool
	if unit.dived:
		wants = not threatened or unit.running_dry(profile.refuel_margin_turns)
	else:
		var dive_burn := unit.type.dived_fuel_upkeep + unit.type.move_points
		wants = (
			threatened
			and not _threatened_by(context, unit, true)
			and unit.fuel > dive_burn * profile.refuel_margin_turns
		)
	if not wants or profile.dive_score <= plan.score:
		return
	plan.score = profile.dive_score
	plan.command = DiveCommand.new(unit, [unit.cell] as Array[Vector2i], not unit.dived)


## Whether an enemy that could damage `unit` can plausibly reach it next turn.
func _threatened_by(context: AIPlanningContext, unit: Unit, submerged: bool) -> bool:
	var state := context.state
	for enemy in context.visible_enemies:
		if submerged and not enemy.type.can_hit_submerged:
			continue
		if not state.damage_chart.can_attack(enemy.type.id, unit.type.id):
			continue
		var reach := enemy.type.move_points + AttackRange.maximum(state, enemy)
		var dist := absi(enemy.cell.x - unit.cell.x) + absi(enemy.cell.y - unit.cell.y)
		if dist <= reach:
			return true
	return false


## Fallback when no attack or capture is worthwhile: take the best position
## relative to a goal, waiting in place when nothing better is reachable.
func _advance_command(
	context: AIPlanningContext, unit: Unit, reachable: MovementResolver.MoveRange
) -> Command:
	var state := context.state
	var goal := _advance_goal(context, unit)
	var threat: ThreatMap = null
	if profile.advance_threat_tiles > 0.0:
		threat = context.threat_map()
	var best_cell := unit.cell
	var best_value := _advance_value(state, unit, unit.cell, goal, threat)
	var best_cost := 0
	for cell in reachable.cells():
		if not reachable.can_stop_at(cell):
			continue
		var value := _advance_value(state, unit, cell, goal, threat)
		var cost: int = reachable.costs[cell]
		if value > best_value or (is_equal_approx(value, best_value) and cost < best_cost):
			best_value = value
			best_cost = cost
			best_cell = cell
	return MoveCommand.new(unit, reachable.path_to(best_cell))


## Higher is better: closeness to the goal less what standing there invites,
## plus whatever the commander's doctrine thinks of the ground itself.
func _advance_value(
	state: GameState,
	unit: Unit,
	cell: Vector2i,
	goal: AIPlanningContext.AdvanceGoal,
	threat: ThreatMap
) -> float:
	var value := -float(_position_rank(state, unit, cell, goal))
	if threat != null:
		var incoming := threat.incoming_damage(state, unit, cell)
		value -= profile.advance_threat_tiles * incoming / float(maxi(unit.hp, 1))
	if profile.doctrine_weight > 0.0:
		var advice := state.commander_of(unit.team).stand_value(state, unit, cell)
		if advice != 0:
			value += profile.doctrine_weight * float(advice)
	return value


## Direct units close on the goal. Indirect units stop inside their firing ring,
## ideally at maximum standoff.
static func _position_rank(
	state: GameState, unit: Unit, cell: Vector2i, goal: AIPlanningContext.AdvanceGoal
) -> int:
	var dist := absi(goal.cell.x - cell.x) + absi(goal.cell.y - cell.y)
	if not goal.stand_off:
		return dist
	var low := AttackRange.minimum(state, unit)
	var high := AttackRange.maximum(state, unit)
	var out_of_ring := high - low + 1
	if dist > high:
		return out_of_ring + dist - high
	if dist < low:
		return out_of_ring + low - dist
	return high - dist


## Fuel-critical units seek refit, damaged units seek repair, a besieged home HQ
## calls everyone else home, capturers seek a non-owned property, and whoever is
## left seeks the nearest visible enemy.
func _advance_goal(context: AIPlanningContext, unit: Unit) -> AIPlanningContext.AdvanceGoal:
	if context.goals.has(unit):
		return context.goals[unit]
	var state := context.state
	var goal := AIPlanningContext.AdvanceGoal.new()
	goal.cell = unit.cell
	if unit.running_dry(profile.refuel_margin_turns):
		var refits := _servicing_properties(context, unit)
		if not refits.is_empty():
			goal.cell = _nearest(unit.cell, refits)
			context.goals[unit] = goal
			return goal
	if unit.hp <= _retreat_threshold(state, unit):
		var repairs := _servicing_properties(context, unit)
		if not repairs.is_empty():
			goal.cell = _nearest(unit.cell, repairs)
			context.goals[unit] = goal
			return goal
	var besieged := _besieged_home_hqs(context, unit)
	if not besieged.is_empty():
		goal.cell = _nearest(unit.cell, besieged)
		context.goals[unit] = goal
		return goal
	if unit.type.can_capture:
		var capturable: Array[Vector2i] = []
		for cell in state.map.property_cells():
			# Through the allegiance authority, so the planner never walks a unit at
			# a capture `CaptureCommand` would refuse: an ally's ground is held.
			if not state.allied(state.owner_at(cell), unit.team):
				capturable.append(cell)
		if not capturable.is_empty():
			goal.cell = _nearest(unit.cell, capturable)
			context.goals[unit] = goal
			return goal
	var enemy_cells: Array[Vector2i] = []
	for other in context.visible_enemies:
		enemy_cells.append(other.cell)
	if not enemy_cells.is_empty():
		goal.cell = _nearest(unit.cell, enemy_cells)
		goal.stand_off = AttackRange.is_indirect(unit)
	context.goals[unit] = goal
	return goal


## Home HQs of our own side with a capture-capable enemy standing on them, in
## enemy scan order. The one property kind that pulls a unit off the front: a
## city changes hands and can be taken back, a home HQ ends the army that loses
## it. Defending anything smaller is left to units that already had a shot.
func _besieged_home_hqs(context: AIPlanningContext, unit: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if profile.defend_weight <= 0.0:
		return cells
	var state := context.state
	for enemy in context.visible_enemies:
		if not enemy.type.can_capture:
			continue
		var owner := state.owner_at(enemy.cell)
		if not state.allied(owner, unit.team):
			continue
		if state.home_hq.has(owner) and state.home_hq[owner] == enemy.cell:
			cells.append(enemy.cell)
	return cells


## The profile's retreat line, moved by the commander's doctrine — a general
## who repairs cheaply rotates wounded units home earlier than the neutral one.
func _retreat_threshold(state: GameState, unit: Unit) -> int:
	var threshold := profile.retreat_hp
	if profile.doctrine_weight > 0.0:
		var delta := state.commander_of(unit.team).retreat_hp_delta(state, unit)
		if delta != 0:
			threshold += int(roundf(profile.doctrine_weight * float(delta)))
	return threshold


## Owned properties that refuel and repair this unit's movement domain.
func _servicing_properties(context: AIPlanningContext, unit: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in context.owned_properties:
		if context.state.map.terrain_at(cell).services_domain(unit.type.domain):
			cells.append(cell)
	return cells


static func _nearest(from: Vector2i, cells: Array[Vector2i]) -> Vector2i:
	var best := cells[0]
	var best_dist := absi(best.x - from.x) + absi(best.y - from.y)
	for cell in cells:
		var dist := absi(cell.x - from.x) + absi(cell.y - from.y)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best
