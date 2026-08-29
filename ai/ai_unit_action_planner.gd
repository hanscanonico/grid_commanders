class_name AIUnitActionPlanner
extends RefCounted
## Chooses the highest-scored action from the current team's ready units.
##
## Greedy, deterministic, and deliberately coarse: combat, capture, diving,
## merging, resupply and withdrawal stay together because they compete for one
## AIUnitPlan score. AIController remains the public façade.
##
## The fallback advance is AIAdvance's — it is the one half of a plan that reads
## the board past the unit's own envelope, so it is asked rather than scored.
##
## One command is returned per call and every survivor is scored again on the
## next one, which is what lets a wounded target's kill reach the next attacker.
## AIPlanCache is what stops that costing a full plan per unit per command; it
## keeps the answers between the commands of a turn and drops the ones the board
## could have moved under, so the planner still answers exactly what it always
## did.

var profile: AIProfile

var _cache: AIPlanCache
var _advance: AIAdvance


func _init(p_profile: AIProfile) -> void:
	profile = p_profile
	_cache = AIPlanCache.new(p_profile)
	_advance = AIAdvance.new(p_profile)


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
	_consider_captures(context, unit, plan.reach, plan)
	_consider_dive(context, unit, plan.reach, plan)
	_consider_join(context, unit, plan.reach, plan)
	_consider_supply(context.state, unit, plan.reach, plan)
	# Last on purpose: every comparison here is strict, so a withdrawal that only
	# ties with a shot loses to it. Running away has to be strictly better.
	_consider_withdraw(context, unit, plan.reach, plan)
	if plan.score < profile.min_useful_score:
		_plan_advance(context, unit, plan)
	return plan


## The fallback, recorded on the plan as one. AIAdvance answers both halves of
## it — where to walk, and whether that goal keeps formation.
func _plan_advance(context: AIPlanningContext, unit: Unit, plan: AIUnitPlan) -> void:
	plan.command = _advance.command_for(context, unit, plan.reach)
	plan.score = profile.advance_score
	plan.advances = true
	plan.keeps_formation = _advance.goal_for(context, unit).keeps_formation


func _consider_attacks(
	context: AIPlanningContext, unit: Unit, reachable: MovementResolver.MoveRange, plan: AIUnitPlan
) -> void:
	var state := context.state
	if unit.type.max_range <= 0 or state.damage_chart == null:
		return
	# Where this unit could shoot from is AttackRange's rule — indirect units cannot
	# move and fire — asked over the fill the plan already holds rather than run again.
	var dests := AttackRange.firing_cells_in(unit, reachable)
	var span := 0
	if not AttackRange.is_indirect(unit):
		span = MovementResolver.move_budget(state, unit)
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
		if Grid.manhattan(unit.cell, enemy.cell) - span <= ring.y:
			candidates.append(enemy)
	# _defend_bonus and the follow-up damage behind _focus_bonus read only the
	# enemy — never the destination — so each is priced once per enemy that
	# turns out to have a legal dest, rather than once per (dest, enemy) pair.
	var defend_bonus: Dictionary[Unit, float] = {}
	var follow_up_damage: Dictionary[Unit, int] = {}
	for dest in dests:
		# The walk to a firing cell and the fire it invites depend only on that
		# cell, so work them out once per destination and only after finding a
		# legal target there.
		var dest_penalty := 0.0
		var dest_priced := false
		var incoming := 0
		for enemy in candidates:
			if not AttackRange.reaches(ring, dest, enemy.cell):
				continue
			if not AttackRange.can_fire(state, unit, enemy):
				continue
			if not dest_priced:
				dest_priced = true
				if threat == null and profile.threat_aversion > 0.0:
					threat = context.threat_map()
				if threat != null:
					incoming = threat.incoming_damage(state, unit, dest)
				var step_cost: int = reachable.costs[dest]
				dest_penalty = (
					profile.step_cost_penalty * step_cost + _threat_penalty(unit, incoming)
				)
			if not defend_bonus.has(enemy):
				defend_bonus[enemy] = _defend_bonus(state, unit, enemy)
			if profile.focus_fire_bonus > 0.0 and not follow_up_damage.has(enemy):
				follow_up_damage[enemy] = _follow_up_damage(context, unit, enemy)
			var forecast := CombatResolver.forecast(state, unit, dest, enemy)
			# The cover is the one term here that belongs to the shot rather than to
			# the destination: the counter it invites is fire this cell has already
			# been priced against, and that counter is this enemy's.
			var score: float = (
				_attack_score(unit, enemy, forecast)
				+ _focus_bonus(enemy, forecast, follow_up_damage.get(enemy, 0))
				+ defend_bonus[enemy]
				+ _cover_score(state, unit, dest, incoming + forecast.counter_damage)
				- dest_penalty
			)
			if score > plan.score:
				plan.score = score
				plan.command = AttackCommand.new(unit, reachable.path_to(dest), enemy.cell)


## Expected damage value (target cost x damage fraction, kill-boosted) minus
## discounted counter risk against our own cost.
func _attack_score(unit: Unit, enemy: Unit, forecast: CombatSnapshot.Forecast) -> float:
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
## cell risks, what stepping out of one saves and what refilling a friendly is
## worth are each this number times the HP — or the shortfall — that changes
## hands.
##
## `condition_weight` interpolates it toward what is left of the unit over its
## defined range of 0 to 1, and that far end is the board's own rate rather than
## a guess:
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
##
## The interpolation factor is clamped rather than trusted: past 1.0 it
## extrapolates past what is left of the unit and turns the price NEGATIVE, and
## every reader of this number — the shot's value, the counter's risk, the
## threatened cell, the withdrawal — then has its sign inverted and the planner
## seeks the death it was pricing against. A weight the range does not define is
## a bug in whatever set it, and this is the floor under it, not the report of
## it: the export declares the range where the value enters.
func _unit_value(unit: Unit) -> float:
	if profile.condition_weight <= 0.0:
		return float(unit.type.cost)
	var condition := clampf(profile.condition_weight, 0.0, 1.0)
	return float(unit.type.cost) * lerpf(1.0, float(unit.hp) / 100.0, condition)


## What firing from a cell costs `unit` in expected incoming damage next turn, in
## the same cost-scaled currency an attack's value uses. `incoming` is the threat
## map's reading of that cell, and zero wherever no dial built a map.
func _threat_penalty(unit: Unit, incoming: int) -> float:
	return profile.threat_aversion * _unit_value(unit) * incoming / 100.0


## The same worth in what the attack path scores in. A tile of walking costs
## `step_cost_penalty` there, so the conversion is the planner's own price of a
## tile rather than a second dial — and "one tile further for a star" means the
## same thing on both paths.
func _cover_score(state: GameState, unit: Unit, cell: Vector2i, priced_fire: int) -> float:
	return profile.step_cost_penalty * _advance.cover_tiles(state, unit, cell, priced_fire)


## How much more attractive `enemy` is because other ready friendlies could
## still pile onto it this turn. Zero when focus fire is off or this shot kills.
##
## `raw_follow_up` is `_follow_up_damage`'s answer for `(unit, enemy)` — a
## function of neither `dest` nor the forecast — so the caller prices it once
## per enemy rather than asking again for every destination this unit could
## fire from.
func _focus_bonus(enemy: Unit, forecast: CombatSnapshot.Forecast, raw_follow_up: int) -> float:
	if profile.focus_fire_bonus <= 0.0:
		return 0.0
	var remaining := enemy.hp - forecast.attack_damage
	if remaining <= 0:
		return 0.0
	var follow_up := mini(remaining, raw_follow_up)
	if follow_up <= 0:
		return 0.0
	var value := _unit_value(enemy) * mini(forecast.attack_damage, enemy.hp) / 100.0
	return profile.focus_fire_bonus * value * float(follow_up) / float(remaining)


## Summed forecast damage other ready friendlies could deal `enemy` this turn.
## Reach is AttackRange's one Manhattan over-estimate, the same one the commander
## powers weigh with; forecasts are luck-free and draw no RNG.
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
		if Grid.manhattan(friendly.cell, enemy.cell) > AttackRange.strike_reach(state, friendly):
			continue
		# Priced from friendly.cell, not the cell the follow-up would actually fire
		# from — the same enemy.cell approximation ThreatMap.incoming_damage makes,
		# and exact for every doctrine but Alina Ward's combined_arms_pct. Inert
		# today (focus_fire_bonus ships at 0.0).
		var forecast := CombatResolver.forecast(state, friendly, friendly.cell, enemy)
		if forecast.can_attack:
			total += forecast.attack_damage
	return total


## What a property is worth to take or to hold: the base price, multiplied for a
## home HQ (losing that one ends the army) and again for ground that builds (AI
## Economy D4), with the progress chipped out of its owner on top unscaled. The
## one arithmetic the capture list and the denial bonus are both priced in (AI
## Judgement D3); the step cost stays outside it, pricing the walk not the ground.
## The home HQ is the authority's answer, never the terrain id.
func _property_score(state: GameState, cell: Vector2i, owner: int, produces: bool) -> float:
	var score := profile.capture_score
	if Seating.is_home(state.home_hq, owner, cell):
		score *= profile.hq_capture_multiplier
	if produces:
		score *= profile.production_capture_multiplier
	var points: int = state.capture_progress.get(cell, state.rules_config.capture_points)
	return score + (state.rules_config.capture_points - points) * profile.capture_progress_bonus


## What shooting `enemy` off ground our own side holds is worth, on top of what
## the shot is worth on its own. Priced at what taking that ground would be worth
## (D3), read backwards.
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
	# A factory is priced as a city here: what the enemy takes is the ground.
	return profile.defend_weight * _property_score(state, cell, owner, false)


## What taking ground is worth, and — under `capture_threat_aversion` — what
## walking onto it invites. The map is resolved on the first capturable cell the
## way `_consider_attacks` resolves it, so a unit with nothing to take builds
## nothing.
func _consider_captures(
	context: AIPlanningContext, unit: Unit, reachable: MovementResolver.MoveRange, plan: AIUnitPlan
) -> void:
	if not unit.type.can_capture:
		return
	var state := context.state
	var threat: ThreatMap = null
	for cell in reachable.cells():
		if not reachable.can_stop_at(cell):
			continue
		var terrain := state.map.terrain_at(cell)
		var owner := state.owner_at(cell)
		# Through the allegiance authority, not `== unit.team`: an ally's ground is
		# already the side's, and `CaptureCommand` turns the attempt down.
		if not terrain.is_property or state.allied(owner, unit.team):
			continue
		var produces := profile.production_capture_multiplier != 1.0 and AIAdvance.produces(terrain)
		var score := _property_score(state, cell, owner, produces)
		var step_cost: int = reachable.costs[cell]
		score -= profile.step_cost_penalty * step_cost
		if profile.capture_threat_aversion > 0.0:
			if threat == null:
				threat = context.threat_map()
			var incoming := threat.incoming_damage(state, unit, cell)
			score -= profile.capture_threat_aversion * _unit_value(unit) * incoming / 100.0
		if score > plan.score:
			plan.score = score
			plan.command = CaptureCommand.new(unit, reachable.path_to(cell))


## Whether folding this unit into a damaged one of its own kind beats everything
## else it could do this turn.
##
## A scored candidate rather than a rule, and weighed after the attacks and the
## captures so that a merge which merely ties with a shot loses to it — the dive
## is the precedent for a non-attack action that may outbid one (AI Judgement
## D4), and this is placed ahead of the withdrawal for the same reason the
## withdrawal is last: it must be strictly better than running away, not equal.
##
## What a join is legal at all is JoinCommand's to say, and it is asked rather
## than re-listed here: same type, same team, a target that is damaged and
## carrying nothing. What this weighs is only which of the legal ones is
## worth doing.
func _consider_join(
	context: AIPlanningContext, unit: Unit, reachable: MovementResolver.MoveRange, plan: AIUnitPlan
) -> void:
	if profile.join_weight <= 0.0:
		return
	var state := context.state
	for other in context.friendly_units:
		if other == unit or other.carrier != null or other.type != unit.type:
			continue
		if not reachable.has(other.cell):
			continue
		var command := JoinCommand.new(unit, reachable.path_to(other.cell))
		if command.validate(state) != "":
			continue
		var score := _join_score(unit, other, reachable.costs[other.cell])
		if score > plan.score:
			plan.score = score
			plan.command = command


## What merging `unit` into `other` is worth: the HP that lands, at the premium
## `join_weight` puts on having it all on one unit, less the HP the cap destroys
## and the walk it takes to get there.
##
## The two halves are weighed differently on purpose. What overflows the merge is
## gone — JoinCommand caps at 100 and refunds nothing — so it is a plain loss and
## is charged at the same rate every other point of HP in this file is, needing
## no dial to say so. What concentration is worth is the judgement, and it is the
## only part the dial answers for.
func _join_score(unit: Unit, other: Unit, step_cost: int) -> float:
	var carried := mini(100 - other.hp, unit.hp)
	var price := _unit_value(unit)
	return (
		profile.join_weight * price * carried / 100.0
		- price * (unit.hp - carried) / 100.0
		- profile.step_cost_penalty * step_cost
	)


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
	var refuge := _best_refuge(context, unit, reachable, threat)
	var avoided := staying - threat.incoming_damage(state, unit, refuge)
	if avoided <= 0:
		return  # nowhere we can reach is safer than standing still
	var score := profile.withdraw_weight * _unit_value(unit) * float(avoided) / 100.0
	if score > plan.score:
		plan.score = score
		plan.command = MoveCommand.new(unit, reachable.path_to(refuge))


## Where this unit would rather be standing, by `_better_refuge`'s keys over
## everywhere it can stop. Its own cell is in the comparison at no cost, so a cell
## that is merely as good never pulls it off its square.
##
## One answer for the two things that step out of trouble, the withdrawal and the
## dive: where it is safer is one question, and a second walk over the same threat
## map would be a second opinion on it. `threat` is null on a tier with every
## threat dial at zero — the dive is the one caller that can reach here without
## one, since `dive_score` is live everywhere (see AIProfile.builds_threat_map) —
## and `_incoming` reads a null map as the same non-answer everywhere, which
## folds the first key out of `_better_refuge` and ranks purely by stand-off,
## repair and cost.
func _best_refuge(
	context: AIPlanningContext, unit: Unit, reachable: MovementResolver.MoveRange, threat: ThreatMap
) -> Vector2i:
	var state := context.state
	var refits := _repair_cells(context, unit)
	# The enemy this unit is orienting on, and its own ring, both asked for once
	# for the whole sweep — see _standoff_rank for why the goal is asked for here
	# rather than taken off the unit's advance.
	var goal := _advance.enemy_goal(context, unit)
	var ring := AttackRange.band(state, unit)
	var best_cell := unit.cell
	var best_incoming := _incoming(threat, state, unit, unit.cell)
	var best_stand := _standoff_rank(unit.cell, goal, ring)
	var best_repairs := refits.has(unit.cell)
	var best_cost := 0
	for cell in reachable.cells():
		if not reachable.can_stop_at(cell):
			continue
		var incoming := _incoming(threat, state, unit, cell)
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
	return best_cell


## `threat`'s reading of `cell`, or every cell held equal when there is no map to
## ask — the honest answer for a tier that has not paid to build one.
static func _incoming(threat: ThreatMap, state: GameState, unit: Unit, cell: Vector2i) -> int:
	if threat == null:
		return 0
	return threat.incoming_damage(state, unit, cell)


## Safety first, then the unit's own weapon, then ground that puts it back
## together, then the shortest walk. Four keys in priority order, which is why
## this is a function rather than a condition inside the loop: each one is a
## decision, and every comparison is strict, which is what lets `_best_refuge`
## hold its incumbent through a tie.
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
## It is `AIAdvance.position_rank`'s answer, because "where does this unit want to
## stand relative to what it shoots" has one owner and a withdrawal must not be a second
## opinion on it: an indirect unit that steps back to a cell its own advance would
## walk it out of next turn is dithering, not retreating. That rank is what prices
## the defect this milestone exists for — it is the difference between a cell
## inside the firing ring and one outside it, *and* between maximum standoff and
## one tile short of it, which is where the artillery actually stopped.
##
## The goal is the advance on the enemy, asked for directly rather than taken off
## whatever `AIAdvance.goal_for` currently answers, because that is an errand as often
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
func _standoff_rank(cell: Vector2i, goal: AIPlanningContext.AdvanceGoal, ring: Vector2i) -> int:
	if goal == null or not goal.stand_off:
		return 0
	return _advance.position_rank(cell, goal, ring)


## Our own properties that would repair this unit, empty while it is unhurt: a
## healthy unit has no reason to prefer a workshop to any other safe cell.
## Infrastructure is `owner == unit.team` and never `allied` (four-players D2),
## which is the question `context.servicing_properties` already asks.
func _repair_cells(context: AIPlanningContext, unit: Unit) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if unit.hp >= 100:
		return none
	return context.servicing_properties(unit.type.domain)


## A submarine's two decisions: whether to be under the water, and where to be it.
##
## Diving is a whole turn, so the boat spends the movement half of it too, at the
## refuge the withdrawal already picks. Its own cell holds every tie there, so a
## boat with nowhere safer goes under exactly where it stood.
func _consider_dive(
	context: AIPlanningContext, unit: Unit, reachable: MovementResolver.MoveRange, plan: AIUnitPlan
) -> void:
	var state := context.state
	if not unit.type.can_dive or state.damage_chart == null:
		return
	var threatened := _threatened_by(context, unit, false)
	var wants: bool
	if unit.dived:
		wants = not threatened or unit.running_dry(profile.refuel_margin_turns)
	else:
		wants = (
			threatened
			and not _threatened_by(context, unit, true)
			and not unit.running_dry_if_dived(profile.refuel_margin_turns)
		)
	if not wants or profile.dive_score <= plan.score:
		return
	plan.score = profile.dive_score
	# dive_score is live on every tier, unlike the dials that build the map — so a
	# lone submarine on a threat-blind tier must not be what turns ThreatMap.build
	# on for the whole turn. Asked here of a plan being built *fresh*, so it only
	# skips a cost; AIPlanCache asks the same authority of a plan it would keep.
	var threat: ThreatMap = null
	if profile.builds_threat_map():
		threat = context.threat_map()
	var refuge := _best_refuge(context, unit, reachable, threat)
	plan.command = DiveCommand.new(unit, reachable.path_to(refuge), not unit.dived)


## Whether an enemy that could damage `unit` can plausibly reach it next turn,
## with `unit` at the depth named — which is the question a boat weighing the dive
## asks twice, once for each side of the hatch.
##
## Both halves are the authorities': who may shoot what is AttackRange.can_engage
## dived and surfaced alike, and how far an enemy reaches is AttackRange's one
## over-estimate. Spelled out here, it read the movement off the type — blind to a
## doctrine's move bonus and to a dry tank — and credited an indirect enemy with a
## move and a shot it cannot take in the same turn.
func _threatened_by(context: AIPlanningContext, unit: Unit, submerged: bool) -> bool:
	var state := context.state
	for enemy in context.visible_enemies:
		if not AttackRange.can_engage_dived(state, enemy, unit, submerged):
			continue
		if Grid.manhattan(enemy.cell, unit.cell) <= AttackRange.strike_reach(state, enemy):
			return true
	return false


## Whether standing where it can refill the army beats moving this unit on. Only
## a unit that carries supplies gets past the guard, which on shipped data is the
## APC and nothing else.
func _consider_supply(
	state: GameState, unit: Unit, reachable: MovementResolver.MoveRange, plan: AIUnitPlan
) -> void:
	if profile.supply_weight <= 0.0 or not unit.type.can_resupply:
		return
	# Who a top-up would reach is SupplyCommand's own answer, and it is asked
	# rather than re-derived because the radius is the commander's: Gideon Holt
	# supplies two tiles out, and adjacency spelled here would miss the second. It
	# takes the cell it is asked about, so one command answers for every cell.
	# The team roster is fetched once here rather than once per reachable cell
	# (~45 for an APC) and handed to `friendlies_in_reach`, which still owns the
	# rule and every `from` still runs through it — a scoring cache, not a
	# second opinion.
	var standing: Array[Vector2i] = [unit.cell]
	var probe := SupplyCommand.new(unit, standing)
	var team_units := state.units_of(unit.team)
	var best_score := plan.score
	var best_cell := unit.cell
	var found := false
	for cell in reachable.cells():
		if not reachable.can_stop_at(cell):
			continue
		var value := _supply_value(probe.friendlies_in_reach(state, cell, team_units))
		if value <= 0.0:
			continue
		var score := (
			profile.supply_weight * value - profile.step_cost_penalty * float(reachable.costs[cell])
		)
		if score > best_score:
			best_score = score
			best_cell = cell
			found = true
	if not found:
		return
	plan.score = best_score
	plan.command = SupplyCommand.new(unit, reachable.path_to(best_cell))


## What refilling these friendlies is worth: each one's value against the pool it
## is emptiest in, so a top-up is never worth more than the unit it tops up.
## The value is `_unit_value`'s, so a refill prices a friendly exactly as the
## shot, the counter and the withdrawal competing with it in the same plan do.
##
## Ammo is graded — half a rack is half of what that unit can put out — while
## fuel is the yes-or-no `running_dry` already answers, the one authority for a
## tank low enough to matter. That leaves a land unit's half-empty tank worth
## nothing here, which is right twice over: an empty tank parks it rather than
## killing it, and anyone still standing beside the APC next turn is refilled by
## the turn-start tick anyway.
func _supply_value(friendlies: Array[Unit]) -> float:
	var value := 0.0
	for friendly in friendlies:
		var short := 0.0
		if friendly.type.max_ammo > 0:
			short = float(friendly.type.max_ammo - friendly.ammo) / float(friendly.type.max_ammo)
		if friendly.running_dry(profile.refuel_margin_turns):
			short = 1.0
		value += _unit_value(friendly) * short
	return value
