class_name AIUnitActionPlanner
extends RefCounted
## Chooses the highest-scored action from the current team's ready units.
##
## Greedy, deterministic, and deliberately coarse: combat, capture, diving,
## withdrawal, and fallback movement stay together because they compete for one
## AIUnitPlan score. AIController remains the public façade.
##
## One command is returned per call and every survivor is scored again on the
## next one, which is what lets a wounded target's kill reach the next attacker.
## AIPlanCache is what stops that costing a full plan per unit per command; it
## keeps the answers between the commands of a turn and drops the ones the board
## could have moved under, so the planner still answers exactly what it always
## did.

var profile: AIProfile

var _cache: AIPlanCache


func _init(p_profile: AIProfile) -> void:
	profile = p_profile
	_cache = AIPlanCache.new(p_profile)


func plan_next(context: AIPlanningContext) -> Command:
	_cache.sync(context)
	var best: Command = null
	var best_score := -INF
	for unit in context.ready_units:
		var plan := _plan_for(context, unit)
		if plan.score > best_score:
			best_score = plan.score
			best = plan.command
	return best


## This unit's plan, scored from scratch unless the cache still holds a good
## one. A plan whose actions hold but whose fallback advance moved under it —
## the column marched, the claims were re-dealt — has that half alone redone, on
## the fill already in hand.
func _plan_for(context: AIPlanningContext, unit: Unit) -> AIUnitPlan:
	var kept := _cache.plan_for(unit)
	if kept == null:
		var plan := _best_unit_plan(context, unit)
		_cache.keep(unit, plan)
		return plan
	if _cache.advance_is_stale(unit):
		_plan_advance(context, unit, kept)
	return kept


func _best_unit_plan(context: AIPlanningContext, unit: Unit) -> AIUnitPlan:
	var plan := AIUnitPlan.new()
	plan.reach = MovementResolver.reachable(context.state, unit)
	_consider_attacks(context, unit, plan.reach, plan)
	_consider_captures(context.state, unit, plan.reach, plan)
	_consider_dive(context, unit, plan)
	# Last on purpose: every comparison here is strict, so a withdrawal that only
	# ties with a shot loses to it. Running away has to be strictly better.
	_consider_withdraw(context, unit, plan.reach, plan)
	if plan.score < profile.min_useful_score:
		_plan_advance(context, unit, plan)
	return plan


## The fallback, recorded on the plan as one: it is the only half of a plan that
## reads the board past the unit's own envelope — the goal it walks to, and the
## column it keeps station with.
func _plan_advance(context: AIPlanningContext, unit: Unit, plan: AIUnitPlan) -> void:
	plan.command = _advance_command(context, unit, plan.reach)
	plan.score = profile.advance_score
	plan.advances = true
	plan.keeps_formation = _advance_goal(context, unit).keeps_formation


func _consider_attacks(
	context: AIPlanningContext, unit: Unit, reachable: MovementResolver.MoveRange, plan: AIUnitPlan
) -> void:
	var state := context.state
	if unit.type.max_range <= 0 or state.damage_chart == null:
		return
	var dests: Array[Vector2i] = []
	var span := 0
	if AttackRange.is_indirect(unit):
		dests = [unit.cell]  # indirect units cannot move and fire
	else:
		span = MovementResolver.move_budget(state, unit)
		for cell in reachable.cells():
			if reachable.can_stop_at(cell):
				dests.append(cell)
	# One threat map for the whole sweep. Still resolved on first need rather
	# than up front, so a unit with nothing in reach builds nothing.
	var threat: ThreatMap = null
	# One ring for it too, asked of the same authority `covers` asks: every cell
	# this unit could stand on is tested against every enemy it can see, and the
	# doctrine's range bonus is the same answer for all of them.
	var ring := AttackRange.band(state, unit)
	# And the enemies out of reach of every one of those cells are dropped once
	# rather than per cell: a walk of `span` tiles closes at most `span` tiles of
	# the distance, so anything further off than that plus the ring is a target
	# this unit could not fire on from anywhere, whichever cell it stopped at.
	var candidates: Array[Unit] = []
	for enemy in context.visible_enemies:
		if _steps(unit.cell, enemy.cell) - span <= ring.y:
			candidates.append(enemy)
	for dest in dests:
		# The walk to a firing cell and the fire it invites depend only on that
		# cell, so work them out once per destination and only after finding a
		# legal target there.
		var dest_penalty := -1.0
		var incoming := 0
		for enemy in candidates:
			if not AttackRange.reaches(ring, dest, enemy.cell):
				continue
			if not AttackRange.can_fire(state, unit, enemy):
				continue
			if dest_penalty < 0.0:
				if threat == null and profile.threat_aversion > 0.0:
					threat = context.threat_map()
				if threat != null:
					incoming = threat.incoming_damage(state, unit, dest)
				var step_cost: int = reachable.costs[dest]
				dest_penalty = (
					profile.step_cost_penalty * step_cost + _threat_penalty(unit, incoming)
				)
			var forecast := CombatResolver.forecast(state, unit, dest, enemy)
			# The cover is the one term here that belongs to the shot rather than to
			# the destination: the counter it invites is fire this cell has already
			# been priced against, and that counter is this enemy's.
			var score: float = (
				_attack_score(unit, enemy, forecast)
				+ _focus_bonus(context, unit, enemy, forecast)
				+ _defend_bonus(state, unit, enemy)
				+ _cover_score(state, unit, dest, incoming + forecast.counter_damage)
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
	var value := _unit_value(enemy) * damage / 100.0
	if forecast.attack_damage >= enemy.hp:
		value *= profile.kill_bonus
	var risk := 0.0
	if forecast.counter_damage > 0:
		var counter := mini(forecast.counter_damage, unit.hp)
		risk = _unit_value(unit) * counter / 100.0 * profile.counter_weight
		if forecast.counter_damage >= unit.hp:
			risk *= 2.0
	return value - risk


## What `unit` is worth as a thing to have, in funds. The one valuation in this
## file: what a shot is worth taking, what the counter costs, what a threatened
## cell risks and what stepping out of one saves are each this number times the
## HP that changes hands.
##
## `condition_weight` interpolates it toward what is left of the unit, and that
## end of the interpolation is the board's own rate rather than a guess:
## TurnRules._repair sells the missing HP back at `cost * heal / 100`, so a 30-HP
## md tank is three tenths of an md tank and the other seven tenths are a bill.
## What the interpolation buys is the part no funds figure holds — the unit is on
## the board *now*, holding the tile it holds, and repair costs turns as well as
## money.
##
## Whose unit it is is deliberately not asked. A wounded unit is worth less to
## kill and less to lose by the same arithmetic, and the appetite for that trade
## already has its own dials in counter_weight, threat_aversion and
## withdraw_weight.
func _unit_value(unit: Unit) -> float:
	if profile.condition_weight <= 0.0:
		return float(unit.type.cost)
	return float(unit.type.cost) * lerpf(1.0, float(unit.hp) / 100.0, profile.condition_weight)


## What firing from a cell costs `unit` in expected incoming damage next turn, in
## the same cost-scaled currency an attack's value uses. `incoming` is the threat
## map's reading of that cell, and zero wherever no dial built a map.
func _threat_penalty(unit: Unit, incoming: int) -> float:
	return profile.threat_aversion * _unit_value(unit) * incoming / 100.0


## What the ground under `cell` is worth to `unit` defensively, in the tiles of
## advance _advance_value counts in — and nothing at all where a forecast has
## already priced the fire arriving there.
##
## `priced_fire` is that fire: the counter the shot invites, the threat map's
## reading of the cell, or the two together. Every one of those numbers is
## CombatResolver's, resolved *through this same terrain*, so wherever there is
## any of it the cover is already in the score — in value, against the actual
## weapons aimed at this actual unit, which is the better of the two readings.
## Stars on top would price one wood twice, which is AI Judgement's R3 in a new
## place. Where there is none nothing else speaks for the ground: on Normal that
## is every cell, since no dial there builds a threat map at all.
##
## Air units are worth nothing here whatever they stand over. The ground under a
## plane is not cover it keeps — UnitType's domain note says so and
## CombatResolver is where the rule lives — so paying for it would buy a discount
## the damage formula does not give.
func _cover_tiles(state: GameState, unit: Unit, cell: Vector2i, priced_fire: int) -> float:
	if profile.cover_tiles <= 0.0 or priced_fire > 0 or unit.type.domain == UnitType.AIR:
		return 0.0
	return profile.cover_tiles * float(state.map.terrain_at(cell).defense_stars)


## The same worth in what the attack path scores in. A tile of walking costs
## `step_cost_penalty` there, so the conversion is the planner's own price of a
## tile rather than a second dial — and "one tile further for a star" means the
## same thing on both paths.
func _cover_score(state: GameState, unit: Unit, cell: Vector2i, priced_fire: int) -> float:
	return profile.step_cost_penalty * _cover_tiles(state, unit, cell, priced_fire)


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
	var value := _unit_value(enemy) * mini(forecast.attack_damage, enemy.hp) / 100.0
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
## the shot is worth on its own. Priced off the capture list read backwards (D3),
## in its arithmetic and its order: the property is worth what taking it is worth,
## a home HQ multiplies that price because losing that one ends the army, and the
## progress already chipped out of us rides on top unscaled, exactly as the
## progress term does in the capture list.
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
	state: GameState, unit: Unit, reachable: MovementResolver.MoveRange, plan: AIUnitPlan
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
		if _produces(terrain):
			score *= profile.production_capture_multiplier
		var points: int = state.capture_progress.get(cell, GameState.CAPTURE_POINTS)
		var step_cost: int = reachable.costs[cell]
		score += (GameState.CAPTURE_POINTS - points) * profile.capture_progress_bonus
		score -= profile.step_cost_penalty * step_cost
		if score > plan.score:
			plan.score = score
			plan.command = CaptureCommand.new(unit, reachable.path_to(cell))


## Whether stepping out of what the enemy can reach beats everything else this
## unit could do this turn.
##
## Deliberately a *candidate* rather than the fallback retreat_hp steers. Retreat
## only ever reached a unit with nothing better to do — it lives past the
## min_useful_score gate — so a wounded tank holding any half-decent shot took
## the shot and died. Here survival competes for the same AIUnitPlan score the shot
## does, which is the only place it can win.
func _consider_withdraw(
	context: AIPlanningContext, unit: Unit, reachable: MovementResolver.MoveRange, plan: AIUnitPlan
) -> void:
	if profile.withdraw_weight <= 0.0:
		return
	var state := context.state
	var threat := context.threat_map()
	var staying := threat.incoming_damage(state, unit, unit.cell)
	if staying <= 0:
		return  # nothing is aiming at us, so there is nothing to buy
	var refits := _repair_cells(context, unit)
	# The enemy this unit is orienting on, and its own ring, both asked for once
	# for the whole sweep — see _standoff_rank for why the goal is asked for here
	# rather than taken off the unit's advance.
	var goal := _enemy_goal(context, unit)
	var ring := AttackRange.band(state, unit)
	var best_cell := unit.cell
	var best_incoming := staying
	var best_stand := _standoff_rank(unit.cell, goal, ring)
	var best_repairs := refits.has(unit.cell)
	var best_cost := 0
	for cell in reachable.cells():
		if not reachable.can_stop_at(cell):
			continue
		var incoming := threat.incoming_damage(state, unit, cell)
		var stand := _standoff_rank(cell, goal, ring)
		var repairs := refits.has(cell)
		var cost: int = reachable.costs[cell]
		if _better_refuge(
			incoming, stand, repairs, cost, best_incoming, best_stand, best_repairs, best_cost
		):
			best_cell = cell
			best_incoming = incoming
			best_stand = stand
			best_repairs = repairs
			best_cost = cost
	var avoided := staying - best_incoming
	if avoided <= 0:
		return  # nowhere we can reach is safer than standing still
	var score := profile.withdraw_weight * _unit_value(unit) * float(avoided) / 100.0
	if score > plan.score:
		plan.score = score
		plan.command = MoveCommand.new(unit, reachable.path_to(best_cell))


## Safety first, then the unit's own weapon, then ground that puts it back
## together, then the shortest walk. Four keys in priority order, which is why
## this is a function rather than a condition inside the loop: each one is a
## decision. Standing still enters the comparison at cost zero, so a cell that is
## merely as safe never pulls a unit off its own square.
##
## The weapon sits *under* safety and over repair, and both halves of that are
## the decision. Over safety it would be a general reluctance to retreat — a unit
## preferring a cell it can shoot from while it is being shot at is the very
## behaviour the dial exists to end, and it would leave `withdraw_weight` as
## useless as the defect that pinned it at zero. Under repair it would be the
## same defect one step removed: a refuge that puts the unit back together and
## takes its weapon out of the fight has still removed it from the match, and
## repair is only ever worth what the shots it buys later are worth. The two
## rarely meet in any case — a healthy unit has no repair cells at all.
static func _better_refuge(
	incoming: int,
	stand: int,
	repairs: bool,
	cost: int,
	best_incoming: int,
	best_stand: int,
	best_repairs: bool,
	best_cost: int
) -> bool:
	if incoming != best_incoming:
		return incoming < best_incoming
	if stand != best_stand:
		return stand < best_stand
	if repairs != best_repairs:
		return repairs
	return cost < best_cost


## What standing on `cell` costs this unit's own weapon, as a rank to minimise —
## and zero for a unit whose usefulness a refuge cannot take away.
##
## It is `_position_rank`'s answer, because "where does this unit want to stand
## relative to what it shoots" has one owner and a withdrawal must not be a second
## opinion on it: an indirect unit that steps back to a cell its own advance would
## walk it out of next turn is dithering, not retreating. That rank is what prices
## the defect this milestone exists for — it is the difference between a cell
## inside the firing ring and one outside it, *and* between maximum standoff and
## one tile short of it, which is where the artillery actually stopped.
##
## The goal is the advance on the enemy, asked for directly rather than taken off
## whatever `_advance_goal` currently answers, because that is an errand as often
## as it is the enemy: a wounded gun's goal is the workshop that repairs it, and
## ranking standoff against *that* would have the gun holding two tiles off its
## own repair shop — while leaving every unit an errand had claimed ranked at
## zero, which is the whole case a refuge exists for.
##
## Only a stand-off goal is ranked, so this reaches an indirect unit and nothing
## else. A direct unit is deliberately untouched: its rank would be plain
## distance to the enemy, which would pull a retreat back toward the thing it is
## retreating from — and there is no cell both outside a direct enemy's reach and
## inside its own one-tile ring anyway, so there is nothing here to save. A unit
## that can see nobody is ranked at zero for the same reason: there is nothing to
## stand off from.
static func _standoff_rank(
	cell: Vector2i, goal: AIPlanningContext.AdvanceGoal, ring: Vector2i
) -> int:
	if goal == null or not goal.stand_off:
		return 0
	return _position_rank(cell, goal, ring)


## Our own properties that would repair this unit, empty while it is unhurt: a
## healthy unit has no reason to prefer a workshop to any other safe cell.
## Infrastructure is `owner == unit.team` and never `allied` (four-players D2),
## which is the question _servicing_properties already asks.
func _repair_cells(context: AIPlanningContext, unit: Unit) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if unit.hp >= 100:
		return none
	return _servicing_properties(context, unit)


## A submarine's one decision: whether to be under the water.
func _consider_dive(context: AIPlanningContext, unit: Unit, plan: AIUnitPlan) -> void:
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
	# Worked out once for the whole sweep rather than per candidate cell: who this
	# unit travels with does not depend on where it is thinking of standing.
	var column := _column_cells(context, unit)
	# The doctrine is asked about every candidate cell, so it is looked up once
	# rather than per cell: which commander an army has cannot change mid-sweep.
	var doctrine := state.commander_of(unit.team)
	# And so is the ring the stand-off rank is measured in, for the same reason:
	# both its ends are one answer for every cell this unit could stop on.
	var ring := AttackRange.band(state, unit)
	var best_cell := unit.cell
	var best_value := _advance_value(state, unit, unit.cell, goal, ring, threat, column, doctrine)
	var best_cost := 0
	for cell in reachable.cells():
		if not reachable.can_stop_at(cell):
			continue
		var value := _advance_value(state, unit, cell, goal, ring, threat, column, doctrine)
		var cost: int = reachable.costs[cell]
		if value > best_value or (is_equal_approx(value, best_value) and cost < best_cost):
			best_value = value
			best_cost = cost
			best_cell = cell
	return MoveCommand.new(unit, reachable.path_to(best_cell))


## Higher is better: closeness to the goal less what standing there invites and
## what running ahead of the column costs, plus what the ground itself is worth —
## its cover, and whatever the commander's doctrine thinks of it.
func _advance_value(
	state: GameState,
	unit: Unit,
	cell: Vector2i,
	goal: AIPlanningContext.AdvanceGoal,
	ring: Vector2i,
	threat: ThreatMap,
	column: Array[Vector2i],
	doctrine: CommanderType
) -> float:
	var value := -float(_position_rank(cell, goal, ring))
	var incoming := 0
	if threat != null:
		incoming = threat.incoming_damage(state, unit, cell)
		value -= profile.advance_threat_tiles * incoming / float(maxi(unit.hp, 1))
	value += _cover_tiles(state, unit, cell, incoming)
	value -= _cohesion_penalty(cell, goal, column)
	if profile.doctrine_weight > 0.0:
		var advice := doctrine.stand_value(state, unit, cell)
		if advice != 0:
			value += profile.doctrine_weight * float(advice)
	return value


## Tiles of forward progress standing at `cell` costs for being adrift of the
## column. Free inside cohesion_radius, then linear — so a fast unit is pulled
## back toward its slower company without any of them ever entering a waiting
## state: the goal term still pulls forward, and the column advances at the speed
## of its rear because that is where the equilibrium sits. Only the advance on
## the enemy is taxed: both terms are in tiles and an errand's is the smaller
## pull, so charging one would stall a unit at the column's edge — walking
## neither home to repair, back to a besieged HQ, nor out to the property that
## pays for the war, which is routinely nowhere near the column.
func _cohesion_penalty(
	cell: Vector2i, goal: AIPlanningContext.AdvanceGoal, column: Array[Vector2i]
) -> float:
	if profile.cohesion_tiles <= 0.0 or column.is_empty() or not goal.keeps_formation:
		return 0.0
	var apart := _nearest_distance(cell, column)
	if apart <= profile.cohesion_radius:
		return 0.0
	return profile.cohesion_tiles * float(apart - profile.cohesion_radius)


## The other units this one marches with: same team, on the board, and in the
## same movement domain. Same domain because an army keeps company with what can
## keep up with it — without that a lone boat is dragged toward a land column it
## can never join, and an aircraft toward ground it does not fight over. Same
## team, and deliberately not the whole side: a unit cannot rely on an army it
## does not command to hold station with it. The asymmetry with `_defend_bonus`,
## which does reach across the alliance through `GameState.allied`, is the point
## — defended ground is the side's, formation is the army's.
func _column_cells(context: AIPlanningContext, unit: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if profile.cohesion_tiles <= 0.0:
		return cells
	for other in context.friendly_units:
		if other == unit or other.carrier != null:
			continue
		if other.type.domain != unit.type.domain:
			continue
		cells.append(other.cell)
	return cells


static func _nearest_distance(from: Vector2i, cells: Array[Vector2i]) -> int:
	var best := absi(cells[0].x - from.x) + absi(cells[0].y - from.y)
	for cell in cells:
		best = mini(best, absi(cell.x - from.x) + absi(cell.y - from.y))
	return best


## Direct units close on the goal. Indirect units stop inside their firing ring,
## ideally at maximum standoff. `ring` is `AttackRange.band`'s answer, handed in
## rather than asked for here because every caller weighs many cells against one
## unit's ring and the doctrine's range bonus is the same answer for all of them.
static func _position_rank(
	cell: Vector2i, goal: AIPlanningContext.AdvanceGoal, ring: Vector2i
) -> int:
	var dist := absi(goal.cell.x - cell.x) + absi(goal.cell.y - cell.y)
	if not goal.stand_off:
		return dist
	var out_of_ring := ring.y - ring.x + 1
	if dist > ring.y:
		return out_of_ring + dist - ring.y
	if dist < ring.x:
		return out_of_ring + ring.x - dist
	return ring.y - dist


## Fuel-critical units seek refit, damaged units seek repair, a besieged home HQ
## calls everyone else home, capturers seek a non-owned property, and whoever is
## left seeks the nearest visible enemy. Only that last one keeps formation: the
## others are errands sending a unit away from its company on purpose.
func _advance_goal(context: AIPlanningContext, unit: Unit) -> AIPlanningContext.AdvanceGoal:
	if context.goals.has(unit):
		return context.goals[unit]
	var state := context.state
	var errand := _errand_goal(context, unit)
	if errand != null:
		context.goals[unit] = errand
		return errand
	if unit.type.can_capture:
		var capturable: Array[Vector2i] = []
		for cell in state.map.property_cells():
			# Through the allegiance authority, so the planner never walks a unit at
			# a capture `CaptureCommand` would refuse: an ally's ground is held.
			if not state.allied(state.owner_at(cell), unit.team):
				capturable.append(cell)
		if not capturable.is_empty():
			var capture := AIPlanningContext.AdvanceGoal.new()
			capture.cell = _claimed_property(context, unit, capturable)
			context.goals[unit] = capture
			return capture
	var goal := _enemy_goal(context, unit)
	if goal == null:
		goal = AIPlanningContext.AdvanceGoal.new()
		goal.cell = unit.cell
	context.goals[unit] = goal
	return goal


## The advance on the enemy: the nearest one this unit can see, stood off from
## when the unit shoots over distance, and null when it can see nobody. The one
## answer to what a unit is orienting on, so the step forward and the step back
## are measured against the same thing rather than against two readings of it.
func _enemy_goal(context: AIPlanningContext, unit: Unit) -> AIPlanningContext.AdvanceGoal:
	var enemy_cells: Array[Vector2i] = []
	for other in context.visible_enemies:
		enemy_cells.append(other.cell)
	if enemy_cells.is_empty():
		return null
	var goal := AIPlanningContext.AdvanceGoal.new()
	goal.cell = _nearest(unit.cell, enemy_cells)
	goal.stand_off = AttackRange.is_indirect(unit)
	goal.keeps_formation = true
	return goal


## The three goals that outrank a capture — refit when fuel-critical, repair when
## wounded, a besieged home HQ — or null when none of them claims this unit. It
## is the question the capture claim asks of every other capturer too, which is
## what keeps a unit an errand has already taken from claiming ground it will
## never walk to.
func _errand_goal(context: AIPlanningContext, unit: Unit) -> AIPlanningContext.AdvanceGoal:
	var goal := AIPlanningContext.AdvanceGoal.new()
	if unit.running_dry(profile.refuel_margin_turns):
		var refits := _servicing_properties(context, unit)
		if not refits.is_empty():
			goal.cell = _nearest(unit.cell, refits)
			return goal
	if unit.hp <= _retreat_threshold(context.state, unit):
		var repairs := _servicing_properties(context, unit)
		if not repairs.is_empty():
			goal.cell = _nearest(unit.cell, repairs)
			return goal
	var besieged := _besieged_home_hqs(context, unit)
	if not besieged.is_empty():
		goal.cell = _nearest(unit.cell, besieged)
		goal.stand_off = AttackRange.is_indirect(unit)
		return goal
	return null


## Which of `cells` this unit walks to once capture goals are claimed, so that
## three infantry near three properties take three of them instead of following
## each other onto the nearest (AI Economy D3).
##
## The claim is an assignment, settled once per command and cleared by
## `AIPlanningContext.begin` — exactly `goals`' lifetime, so D3's rejected
## cross-decision claims registry stays rejected. The closest unit-property pair
## is settled first, then the next, and a property stops accepting once
## `capture_claim_depth` units hold it. That is what makes "the nearest unit still
## takes the nearest property; the second one is pushed to the next" true — D3's
## own sentence, and the arithmetic it offered for it (drop a property when that
## many rivals are closer to it) cannot produce it: a unit at the front of a
## column is closest to every property at once, so the units behind it keep
## nothing and converge exactly as they do today. The decision D3 locks — nothing
## carried between commands, ties by scan order — is untouched; only its formula
## is superseded.
##
## Every tie is settled by scan order, over the whole triple, because two units
## exactly equidistant from one property have to be separated by something: a tie
## broken any other way lets them swap goals between replans so both walk and
## neither arrives. A unit left unplaced — the board holds more capturers than
## `capture_claim_depth` places — walks to the same priced goal an unclaimed
## capturer walks to (`_worth_walking_to`), which is why claiming can never send
## a capturer at the enemy instead.
func _claimed_property(context: AIPlanningContext, unit: Unit, cells: Array[Vector2i]) -> Vector2i:
	if profile.capture_claim_depth <= 0:
		return _worth_walking_to(context.state, unit.cell, cells)
	if not context.capture_claims.has(unit):
		_assign_capture_claims(context, unit, cells)
	if context.capture_claims.has(unit):
		return context.capture_claims[unit]
	return _worth_walking_to(context.state, unit.cell, cells)


## Whether this ground makes units, asked of the one authority for it:
## `TerrainType.builds`, the same field `BuildCommand`, the build menu and the
## production planner's facility scan read. So a base, a port and an airport are
## production and a city is not, and no terrain id is spelled out here to say so.
static func _produces(terrain: TerrainType) -> bool:
	return not terrain.builds.is_empty()


## The property to head for: the nearest one, less however many tiles a
## production property is worth going out of the way for (AI Economy D4).
##
## The detour is the same judgement `_consider_captures` prices the arrival with,
## converted into the currency a goal is chosen in — so "worth taking" and "worth
## walking to" cannot disagree, and a unit does not walk to a factory only to turn
## around when it gets there. Zero at either dial's inert value, and at
## `capture_goal_value_tiles` 0 the whole reading is the shipped `_nearest` call.
func _worth_walking_to(state: GameState, from: Vector2i, cells: Array[Vector2i]) -> Vector2i:
	if profile.capture_goal_value_tiles <= 0.0:
		return _nearest(from, cells)
	var best := cells[0]
	var best_reach := _goal_steps(state, from, best)
	for cell in cells:
		var reach := _goal_steps(state, from, cell)
		if reach < best_reach:
			best_reach = reach
			best = cell
	return best


## How far `cell` counts as, for choosing a goal: the walk, less the detour what
## it produces is worth. One function, so the plain walk and the claimed
## assignment price a property identically.
func _goal_steps(state: GameState, from: Vector2i, cell: Vector2i) -> float:
	var reach := float(_steps(from, cell))
	if profile.capture_goal_value_tiles <= 0.0 or not _produces(state.map.terrain_at(cell)):
		return reach
	return reach - profile.capture_goal_value_tiles * (profile.production_capture_multiplier - 1.0)


## Settles the whole assignment at once and writes every seeker's answer into the
## context, because one command's board gives every one of them the same answer.
##
## The seekers are the capture units that reach the capture clause at all: one an
## errand has already claimed never walks to the property it would take here, so
## it would leave the ground it stood on unvisited and push the unit behind it
## off. The asking unit is always a seeker — it passed those same clauses on the
## way in — and so is one standing on a cell of `cells`, which is taking that
## property rather than walking anywhere. A wounded capturer one tile short of a
## property is the accepted residual: it is dropped until it stands on the tile.
func _assign_capture_claims(context: AIPlanningContext, unit: Unit, cells: Array[Vector2i]) -> void:
	var seekers: Array[Unit] = []
	for other in context.friendly_units:
		if not other.type.can_capture or other.carrier != null:
			continue
		if other == unit or cells.has(other.cell) or _errand_goal(context, other) == null:
			seekers.append(other)
	var bids: Array = []
	for u in seekers.size():
		for c in cells.size():
			bids.append([_goal_steps(context.state, seekers[u].cell, cells[c]), u, c])
	bids.sort_custom(_by_distance_then_scan_order)
	var held: Dictionary = {}
	var placed: Dictionary = {}
	for bid in bids:
		var u: int = bid[1]
		var c: int = bid[2]
		if placed.has(u) or int(held.get(c, 0)) >= profile.capture_claim_depth:
			continue
		placed[u] = c
		held[c] = int(held.get(c, 0)) + 1
	for u in seekers.size():
		var seeker := seekers[u]
		var claim := (
			cells[placed[u]]
			if placed.has(u)
			else _worth_walking_to(context.state, seeker.cell, cells)
		)
		context.capture_claims[seeker] = claim


## Shortest walk first, every tie broken by scan order — of the unit, then of the
## property. A total order, so the assignment cannot depend on the sort being
## stable and replans off one board always agree.
static func _by_distance_then_scan_order(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	if a[1] != b[1]:
		return a[1] < b[1]
	return a[2] < b[2]


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
	var best_dist := _steps(from, best)
	for cell in cells:
		var dist := _steps(from, cell)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best


## Manhattan tiles between two cells — the goal-side measure of "how far", used
## by the nearest-goal walk and by the claim that filters its candidates, so the
## two cannot disagree about which unit is closer.
static func _steps(from: Vector2i, to: Vector2i) -> int:
	return absi(to.x - from.x) + absi(to.y - from.y)
