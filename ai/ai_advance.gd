class_name AIAdvance
extends RefCounted
## Where a unit walks when nothing it could do in place is worth doing.
##
## This is the only half of a plan that reads the board past the unit's own
## envelope — the goal it walks to, the column it keeps station with, the claims
## its fellow capturers have already staked — which is why it lives apart from
## AIUnitActionPlanner's scored candidates rather than beside them.
##
## Every read is the planner's own, verbatim: same profile, same comparator
## order, same authorities.

var profile: AIProfile


func _init(p_profile: AIProfile) -> void:
	profile = p_profile


## Fallback when no attack or capture is worthwhile: take the best position
## relative to a goal, waiting in place when nothing better is reachable.
func command_for(
	context: AIPlanningContext, unit: Unit, reachable: MovementResolver.MoveRange
) -> Command:
	var state := context.state
	var goal := goal_for(context, unit)
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


## Fuel-critical units seek refit, damaged units seek repair, a besieged home HQ
## calls everyone else home, capturers seek a non-owned property, and whoever is
## left seeks the nearest visible enemy. Only that last one keeps formation: the
## others are errands sending a unit away from its company on purpose.
func goal_for(context: AIPlanningContext, unit: Unit) -> AIPlanningContext.AdvanceGoal:
	if context.goals.has(unit):
		return context.goals[unit]
	var errand := _cached_errand_goal(context, unit)
	if errand != null:
		return errand
	if unit.type.can_capture:
		# `capturable_properties` is the allegiance authority read once for the
		# whole command: an ally's ground is already held, so `CaptureCommand`
		# would refuse it and a unit is never walked at it.
		var capturable := context.capturable_properties()
		if not capturable.is_empty():
			var capture := AIPlanningContext.AdvanceGoal.new()
			capture.cell = _claimed_property(context, unit, capturable)
			context.goals[unit] = capture
			return capture
	var goal := enemy_goal(context, unit)
	if goal == null:
		goal = AIPlanningContext.AdvanceGoal.new()
		goal.cell = unit.cell
	context.goals[unit] = goal
	return goal


## The advance on the enemy: the nearest one this unit can see, stood off from
## when the unit shoots over distance, and null when it can see nobody. The one
## answer to what a unit is orienting on, so the step forward and the step back
## are measured against the same thing rather than against two readings of it.
##
## `goal_engageability` narrows the list to what this unit could ever fire on,
## asked of the matchup authority: a cruiser handed a land unit walks the coast
## at something it can never shoot. Only a narrowed list with somebody on it is
## used — a unit with nothing to engage anywhere still advances, because standing
## still reads worse than milling.
##
## Memoised in `context.enemy_goals` for the command: the walk below is over every
## visible enemy, and the withdrawal asks it twice per unit on top of the advance.
func enemy_goal(context: AIPlanningContext, unit: Unit) -> AIPlanningContext.AdvanceGoal:
	if context.enemy_goals.has(unit):
		return context.enemy_goals[unit]
	var goal := _scan_enemy_goal(context, unit)
	context.enemy_goals[unit] = goal
	return goal


func _scan_enemy_goal(context: AIPlanningContext, unit: Unit) -> AIPlanningContext.AdvanceGoal:
	var enemy_cells: Array[Vector2i] = []
	var engageable: Array[Vector2i] = []
	for other in context.visible_enemies:
		enemy_cells.append(other.cell)
		if profile.goal_engageability > 0.0 and AttackRange.can_engage(context.state, unit, other):
			engageable.append(other.cell)
	if not engageable.is_empty():
		enemy_cells = engageable
	if enemy_cells.is_empty():
		return null
	var goal := AIPlanningContext.AdvanceGoal.new()
	goal.cell = _nearest(unit.cell, enemy_cells)
	goal.stand_off = AttackRange.is_indirect(unit)
	goal.keeps_formation = true
	return goal


## Direct units close on the goal. Indirect units stop inside their firing ring,
## ideally at maximum standoff. `ring` is `AttackRange.band`'s answer, handed in
## rather than asked for here because every caller weighs many cells against one
## unit's ring and the doctrine's range bonus is the same answer for all of them.
##
## `standoff_band_tolerance` is what makes "ideally" optional: inside the band
## every cell ranks alike, so the caller's own cost tie-break holds the unit
## still rather than walking it to maximum stand-off against a goal that moves
## every turn.
func position_rank(cell: Vector2i, goal: AIPlanningContext.AdvanceGoal, ring: Vector2i) -> int:
	var dist := Grid.manhattan(goal.cell, cell)
	if not goal.stand_off:
		return dist
	var out_of_ring := ring.y - ring.x + 1
	if dist > ring.y:
		return out_of_ring + dist - ring.y
	if dist < ring.x:
		return out_of_ring + ring.x - dist
	if profile.standoff_band_tolerance > 0:
		return 0
	return ring.y - dist


## What the ground under `cell` is worth to `unit` defensively, in the tiles of
## advance `_advance_value` counts in — and nothing at all where a forecast has
## already priced the fire arriving there. Public because the attack path buys
## the same ground in the same tiles and must not price it a second way; what
## converts a tile into that path's currency is the planner's own `_cover_score`.
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
## What cover a unit gets on a cell is asked of CombatResolver rather than read
## off the terrain here, so the planner cannot price ground the damage formula
## does not. That is where the air rule lives — a plane is over the tile rather
## than on it and keeps none of it — and it is answered once, there.
func cover_tiles(state: GameState, unit: Unit, cell: Vector2i, priced_fire: int) -> float:
	if profile.cover_tiles <= 0.0 or priced_fire > 0:
		return 0.0
	return profile.cover_tiles * float(CombatResolver.cover_stars(state, unit, cell))


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
	var value := -float(position_rank(cell, goal, ring))
	var incoming := 0
	if threat != null:
		incoming = threat.incoming_damage(state, unit, cell)
		value -= profile.advance_threat_tiles * incoming / float(maxi(unit.hp, 1))
	value += cover_tiles(state, unit, cell, incoming)
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
	var apart := Grid.manhattan(_nearest(cell, column), cell)
	if apart <= profile.cohesion_radius:
		return 0.0
	return profile.cohesion_tiles * float(apart - profile.cohesion_radius)


## The other units this one marches with: same team, on the board, and in the
## same movement domain. Same domain because an army keeps company with what can
## keep up with it — without that a lone boat is dragged toward a land column it
## can never join, and an aircraft toward ground it does not fight over. Same
## team, and deliberately not the whole side: a unit cannot rely on an army it
## does not command to hold station with it. The asymmetry with the planner's
## defend bonus, which does reach across the alliance through `GameState.allied`,
## is the point — defended ground is the side's, formation is the army's.
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


## The three goals that outrank a capture — refit when fuel-critical, repair when
## wounded, a besieged home HQ — or null when none of them claims this unit. It
## is the question the capture claim asks of every other capturer too, which is
## what keeps a unit an errand has already taken from claiming ground it will
## never walk to.
func _errand_goal(context: AIPlanningContext, unit: Unit) -> AIPlanningContext.AdvanceGoal:
	# One scan for both the refit and repair checks below — a unit that is
	# fuel-critical with nothing servicing it used to run this same scan again
	# for the wound check that follows.
	var servicing := context.servicing_properties(unit.type.domain)
	if not servicing.is_empty():
		if unit.running_dry(profile.refuel_margin_turns):
			var refit := AIPlanningContext.AdvanceGoal.new()
			refit.cell = _nearest(unit.cell, servicing)
			refit.errand = true
			return refit
		if unit.hp <= _retreat_threshold(context.state, unit):
			var repair := AIPlanningContext.AdvanceGoal.new()
			repair.cell = _nearest(unit.cell, servicing)
			repair.errand = true
			return repair
	var besieged := _besieged_home_hqs(context)
	if not besieged.is_empty():
		var goal := AIPlanningContext.AdvanceGoal.new()
		goal.cell = _nearest(unit.cell, besieged)
		goal.stand_off = AttackRange.is_indirect(unit)
		goal.errand = true
		return goal
	return null


## `_errand_goal`'s answer, shared with `goal_for`'s own memo. A unit
## `_assign_capture_claims` inspects while filtering seekers, and that same
## unit's own `goal_for` call later — this is the one path both walk,
## caching a real errand so the second call finds it rather than re-running
## the scan. A null errand is never cached: it is not itself a fact about the
## unit's final goal, only that this branch found nothing.
##
## The memo it reads holds captures and advances too, so a cached goal answers
## here only when it is flagged an errand. Without that the seeker filter would
## invert for any unit whose `goal_for` had already run — "has an errand"
## and "has any goal" would be the same test — and drop from the seekers exactly
## the units it exists to keep.
func _cached_errand_goal(context: AIPlanningContext, unit: Unit) -> AIPlanningContext.AdvanceGoal:
	if context.goals.has(unit):
		var cached := context.goals[unit]
		return cached if cached.errand else null
	var errand := _errand_goal(context, unit)
	if errand != null:
		context.goals[unit] = errand
	return errand


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
## Public because the capture score asks the same question of the arrival that
## `_goal_steps` asks of the walk, and one answer is what keeps them agreeing.
static func produces(terrain: TerrainType) -> bool:
	return not terrain.builds.is_empty()


## The property to head for: the nearest one, less however many tiles a
## production property is worth going out of the way for (AI Economy D4).
##
## The detour is the same judgement the planner prices the arrival with, converted
## into the currency a goal is chosen in — so "worth taking" and "worth walking
## to" cannot disagree, and a unit does not walk to a factory only to turn around
## when it gets there. At either dial's inert value `_goal_steps` is the
## plain walk, so this reads as the nearest property.
func _worth_walking_to(state: GameState, from: Vector2i, cells: Array[Vector2i]) -> Vector2i:
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
	var reach := float(Grid.manhattan(from, cell))
	if profile.capture_goal_value_tiles <= 0.0 or not produces(state.map.terrain_at(cell)):
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
		if other == unit or cells.has(other.cell) or _cached_errand_goal(context, other) == null:
			seekers.append(other)
	var bids: Array[Array] = []
	for u in seekers.size():
		for c in cells.size():
			bids.append([_goal_steps(context.state, seekers[u].cell, cells[c]), u, c])
	bids.sort_custom(_by_distance_then_scan_order)
	var held: Dictionary[int, int] = {}
	var placed: Dictionary[int, int] = {}
	for bid in bids:
		var u: int = bid[1]
		var c: int = bid[2]
		if placed.has(u) or held.get(c, 0) >= profile.capture_claim_depth:
			continue
		placed[u] = c
		held[c] = held.get(c, 0) + 1
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


## Home HQs of our own side with a capture-capable enemy standing on them. The
## one property kind that pulls a unit off the front: a city changes hands and
## can be taken back, a home HQ ends the army that loses it. Defending anything
## smaller is left to units that already had a shot.
##
## The scan itself is `context.besieged_home_hqs()`'s, asked only while
## `defend_weight` is live — the gate stays here rather than in the context, so
## a tier with the dial off never pays for the scan at all.
func _besieged_home_hqs(context: AIPlanningContext) -> Array[Vector2i]:
	if profile.defend_weight <= 0.0:
		return []
	return context.besieged_home_hqs()


## The profile's retreat line, moved by the commander's doctrine — a general
## who repairs cheaply rotates wounded units home earlier than the neutral one.
func _retreat_threshold(state: GameState, unit: Unit) -> int:
	var threshold := profile.retreat_hp
	if profile.doctrine_weight > 0.0:
		var delta := state.commander_of(unit.team).retreat_hp_delta(state, unit)
		if delta != 0:
			threshold += int(roundf(profile.doctrine_weight * float(delta)))
	return threshold


static func _nearest(from: Vector2i, cells: Array[Vector2i]) -> Vector2i:
	var best := cells[0]
	var best_dist := Grid.manhattan(from, best)
	for cell in cells:
		var dist := Grid.manhattan(from, cell)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best
