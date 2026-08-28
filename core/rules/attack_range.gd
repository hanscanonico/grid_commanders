class_name AttackRange
extends RefCounted
## Who a unit may shoot and how far, doctrine included. The single authority on
## both.
##
## Three places used to work the distance out independently from
## min_range/max_range: AttackCommand's validation, the AI's target search, and
## the targeting overlay the player aims with. That was harmless while the answer
## was fixed and a liability the moment a commander could change it — a range
## bonus applied to two of the three means the rules, the AI and the UI disagree
## about the same shot, and the one that disagrees is whichever was forgotten.
##
## The same three then asked the damage chart directly about *whether* a target
## could be engaged, which was fine while the chart was the whole answer. A
## submerged submarine made it two answers, so that question moved here as
## can_engage rather than being pattern-matched into three files.
##
## So they all ask here instead. Countering is the deliberate exception; see
## CombatResolver._counter_shot.


## The closest tile this unit can fire at. No doctrine changes it: a minimum
## range is the dead zone a weapon cannot shoot inside, not a bonus to hand out.
static func minimum(_state: GameState, unit: Unit) -> int:
	return unit.type.min_range


## The furthest tile this unit can fire at, after its commander's doctrine.
static func maximum(state: GameState, unit: Unit) -> int:
	if unit.type.max_range <= 0:
		return 0  # unarmed: no doctrine may hand an APC a weapon
	return unit.type.max_range + state.commander_of(unit.team).range_bonus(state, unit)


## The ring this unit shoots in as [minimum, maximum], for a caller about to
## test many cells against it: the planner weighs every cell it could stand on
## against every enemy it can see, and both ends of the ring are the same answer
## for all of them. Asking once is what keeps the doctrine's range bonus from
## being resolved a few hundred times a unit.
static func band(state: GameState, unit: Unit) -> Vector2i:
	return Vector2i(minimum(state, unit), maximum(state, unit))


## True when a shot fired from `from` reaches `target`, given a band already
## asked for. `covers` is this with the band asked for on the spot, so the two
## cannot disagree about a shot.
static func reaches(ring: Vector2i, from: Vector2i, target: Vector2i) -> bool:
	var dist := Grid.manhattan(target, from)
	return dist >= ring.x and dist <= ring.y


## True when a shot fired from `from` reaches `target`.
static func covers(state: GameState, unit: Unit, from: Vector2i, target: Vector2i) -> bool:
	if unit.type.max_range <= 0:
		return false
	return reaches(band(state, unit), from, target)


## Whether `attacker`'s weapon can touch `target` at all, distance aside: the
## damage chart's answer, and then whether the target is somewhere the weapon can
## reach it.
##
## Today that second half is the sea's surface. A submerged submarine is engaged
## only by something built to hunt one, which is what the dive is for — and the
## rule has to hold in the command that validates the shot, the planner that picks
## it and the overlay that offers it, so all three ask this.
static func can_engage(state: GameState, attacker: Unit, target: Unit) -> bool:
	return can_engage_dived(state, attacker, target, target.dived)


## The same answer with the target's depth named rather than read off it, for the
## one caller weighing a depth the target is not at yet: a submarine decides
## whether to dive by asking what would still be able to shoot it once it was
## under. One body, so the hypothetical and the live shot cannot come apart.
static func can_engage_dived(state: GameState, attacker: Unit, target: Unit, dived: bool) -> bool:
	if state.damage_chart == null:
		return false
	if not state.damage_chart.can_attack(attacker.type.id, target.type.id):
		return false
	return _reaches_depth(attacker, dived)


## Whether the attacker's weapon reaches the depth the target is at. One
## statement of the dive rule, shared by can_engage and ready_shot, so the two
## cannot come apart over it.
static func _reaches_depth(attacker: Unit, dived: bool) -> bool:
	return not dived or attacker.type.can_hit_submerged


## The weapon `attacker` would fire at `target` right now, or null when none is
## ready. Weapon choice and ammo ownership stay in DamageChart; this adds only
## the submerged target rule.
##
## It shares that rule with can_engage through _reaches_depth rather than routing
## through it: can_engage's other half — the chart covering the pair — is already
## implied by select_shot returning a weapon, the selector answering null exactly
## when neither matrix covers the pair or the primary is dry with no secondary.
## can_engage stays the who-may-shoot authority; this is its answer with the
## chart read once.
##
## Returned rather than merely counted so a caller that needs the slot or its
## base damage — the resolver, on every shot and every counter — pays for the
## selection once instead of asking whether it exists and then asking again what
## it was.
static func ready_shot(state: GameState, attacker: Unit, target: Unit) -> DamageChart.Shot:
	if state.damage_chart == null or not _reaches_depth(attacker, target.dived):
		return null
	return state.damage_chart.select_shot(
		attacker.type.id, target.type.id, attacker.ammo, attacker.type.max_ammo
	)


## Whether one of `attacker`'s target-compatible weapons is ready now, for the
## callers that only need the yes or no.
static func can_fire(state: GameState, attacker: Unit, target: Unit) -> bool:
	return ready_shot(state, attacker, target) != null


## Target-agnostic readiness for callers that are about to build firing
## geometry. Target cells still have to pass can_fire before damage is priced.
static func has_ready_weapon(state: GameState, unit: Unit) -> bool:
	if state.damage_chart == null:
		return false
	return state.damage_chart.has_ready_weapon(unit.type.id, unit.ammo, unit.type.max_ammo)


## True for a unit that shoots over distance: it cannot move and fire, never
## counters, and is never countered. A property of the weapon, so it is read
## from the type and no doctrine turns a direct unit into an indirect one.
static func is_indirect(unit: Unit) -> bool:
	return is_indirect_type(unit.type)


## The same answer asked of the type alone, for callers weighing a unit that
## does not exist yet — production advice, not a live shot.
static func is_indirect_type(type: UnitType) -> bool:
	return type.min_range > 1


## How far this unit could bring something under fire in one turn: its gun, plus
## the ground it can cross first — and an indirect unit cannot move and fire, so
## that one reaches only as far as the gun.
##
## Manhattan distance against MovementResolver's budget, so it deliberately
## over-estimates: it ignores what the ground costs and who is standing on it. It
## is the cheap screen a caller takes before the real work — the doctrines
## weighing a Command Power, the planner's focus fire, and a submarine deciding
## whether to go under — and each of the three used to guess it from
## `type.move_points`, which is blind to a commander's move bonus and to an empty
## tank alike.
static func strike_reach(state: GameState, unit: Unit) -> int:
	var reach := maximum(state, unit)
	if reach <= 0:
		return 0  # unarmed: it brings nothing under fire, however far it walks
	if is_indirect(unit):
		return reach
	return reach + MovementResolver.move_budget(state, unit)


## The cells `unit` could fire *from* this turn. An indirect unit cannot move and
## fire, so it shoots only from where it stands; a direct unit may fire from any
## cell it can stop on, its current one included.
##
## Promoted here from the AI's threat map so the planner and the range overlay
## share one definition of a firing position — a red cell the player sees and a
## cell the AI fears are then the same math, not two that agree until someone
## edits one. The movement-overlay lesson (MoveCommand.validate) applied before
## the second opinion, not after.
##
## `sight_team` is handed straight to the fill underneath — see
## MovementResolver.reachable — so a caller drawing somebody else's ring works its
## firing positions out with the knowledge it actually has.
static func firing_cells(
	state: GameState, unit: Unit, sight_team: int = MovementResolver.MOVER_SIGHT
) -> Array[Vector2i]:
	if is_indirect(unit):
		return [unit.cell]  # no fill is needed, so none is run
	return firing_cells_in(unit, MovementResolver.reachable(state, unit, 0, sight_team))


## The same answer over a fill the caller already has, for the planner: it holds
## every ready unit's reach on its plan already, and letting firing_cells run its
## own would be a second flood fill per unit per command.
##
## It takes no `sight_team`, because the fill it is handed *is* that decision —
## there is no parameter here to disagree with the one `reachable` was called
## with. Which is also why the two entry points are one body: the rule that an
## indirect unit fires only from where it stands has to be the same rule the range
## overlay paints, or the planner is exactly the second opinion this file exists
## to retire.
static func firing_cells_in(unit: Unit, reach: MovementResolver.MoveRange) -> Array[Vector2i]:
	if is_indirect(unit):
		return [unit.cell]
	var cells: Array[Vector2i] = []
	for cell in reach.cells():
		if reach.can_stop_at(cell):
			cells.append(cell)
	return cells


## Every in-bounds cell in the [low, high] Manhattan ring around `from`. The one
## ring walk both the threat map's per-enemy attribution and threat_cells' union
## draw on, so the two cannot disagree about the shape of a shot.
static func ring_cells(state: GameState, from: Vector2i, low: int, high: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in Grid.ring_offsets(low, high):
		var cell: Vector2i = from + offset
		if state.map.terrain_at(cell) != null:
			cells.append(cell)
	return cells


## Every board cell this unit could bring under fire this turn: the deduped union
## of its [minimum, maximum] firing ring taken over every cell it could fire from.
## Unarmed units (max_range <= 0) reach nowhere and return []. Ammo is *not*
## consulted — this answers "what does the weapon reach", the capability a dry gun
## keeps one resupply from firing; the threat map layers its own dry filter on top
## for the different question of damage expected this turn.
##
## A pure read: no RNG, no mutation. The single authority the range overlay asks
## and the AI's ThreatMap is built from.
static func threat_cells(
	state: GameState, unit: Unit, sight_team: int = MovementResolver.MOVER_SIGHT
) -> Array[Vector2i]:
	if unit.type.max_range <= 0:
		return []
	var low := minimum(state, unit)
	var high := maximum(state, unit)
	var seen: Dictionary[Vector2i, bool] = {}
	for from in firing_cells(state, unit, sight_team):
		for cell in ring_cells(state, from, low, high):
			seen[cell] = true
	var result: Array[Vector2i] = []
	for cell: Vector2i in seen:
		result.append(cell)
	return result
