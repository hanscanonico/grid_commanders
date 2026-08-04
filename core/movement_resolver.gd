class_name MovementResolver
extends RefCounted
## Dijkstra flood-fill of the cells a unit can reach this turn.
##
## Rules (Advance Wars):
## - Edge cost is the destination terrain's cost for the unit's move class.
## - A cell held by an enemy the sighting team can SEE cannot be entered at all.
## - A cell held by a unit the sighting team cannot see (fogged, dived, or
##   doctrine-cloaked) is planned through as if empty — nobody planning the move
##   knows it is there; the ambush springs on commit (see GameState.advance_unit).
## - Friendly-occupied cells can be passed through but not stopped on.
##
## The sighting team is the mover's own unless a caller names another; see
## `reachable`'s `sight_team`.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.DOWN,
]

## `sight_team`'s default: fill with the mover's own knowledge. Not a team id —
## GameState.TEAMS starts at 1 and 0 is the neutral owner — so no arithmetic on a
## team can land on it by accident.
const MOVER_SIGHT := -1


class MoveRange:
	var origin: Vector2i
	var costs: Dictionary[Vector2i, int] = {}  # movement spent to enter
	var parents: Dictionary[Vector2i, Vector2i] = {}  # previous cell on the cheapest path
	var stoppable: Dictionary[Vector2i, bool] = {}  # may end movement here

	func has(cell: Vector2i) -> bool:
		return costs.has(cell)

	func can_stop_at(cell: Vector2i) -> bool:
		return stoppable.get(cell, false)

	func cells() -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		for cell: Vector2i in costs:
			result.append(cell)
		return result

	## Cheapest path origin..cell inclusive; [] if the cell is unreachable.
	func path_to(cell: Vector2i) -> Array[Vector2i]:
		if not costs.has(cell):
			return []
		var path: Array[Vector2i] = [cell]
		var current := cell
		while current != origin:
			current = parents[current]
			path.push_front(current)
		return path


## How far `unit` may travel this turn: its type's movement points plus whatever
## its commander's doctrine adds, capped by fuel — an empty tank keeps a unit
## where it stands however generous the doctrine.
##
## `extra` is a hypothetical allowance on top, for asking "how far would this
## unit get with one more point?" without touching match state. The AI weighs a
## power that grants movement with it, since such a power has to be judged by
## the reach it *would* create rather than the reach the unit has without it.
## Fuel still caps the total: no allowance conjures range out of an empty tank.
static func move_budget(state: GameState, unit: Unit, extra: int = 0) -> int:
	var bonus := state.commander_of(unit.team).move_bonus(state, unit)
	return mini(unit.type.move_points + bonus + extra, unit.fuel)


## What one step onto `terrain` actually costs `unit`, after its commander's
## doctrine. The sole place terrain cost is read, so the flood fill below and
## the fuel spend in GameState.advance_unit cannot disagree.
##
## Three invariants no doctrine may break. IMPASSABLE passes straight through — a
## doctrine may discount terrain, never open terrain its units cannot cross — and
## every other result is floored at 1, so a zero-cost step can never stall the
## flood fill in a loop it keeps finding cheaper.
##
## And the answer is a function of the unit and the terrain and of nothing else:
## *which* cell that terrain is on may not change it. `terrain_cost` is handed no
## cell for exactly this reason, and the fill below memoises one answer per kind
## of ground per fill — a doctrine that reached around the hook for a cell would
## get whichever cell it happened to be asked about first.
static func step_cost(state: GameState, unit: Unit, terrain: TerrainType) -> int:
	var base := terrain.move_cost(unit.type.move_class)
	if base == TerrainType.IMPASSABLE:
		return base
	return maxi(1, state.commander_of(unit.team).terrain_cost(state, unit, terrain, base))


## May `unit` end its move on `cell`? The fill below and `MoveCommand.move_error`
## both ask, so the overlay can never offer a cell the command then refuses.
## `visible` is the mover's own sight, handed in for the reason the fill holds one
## for its whole walk: it is a whole-board flood, and the validation that asks this
## has just walked the path with the same answer.
static func can_stop(state: GameState, unit: Unit, cell: Vector2i, visible: Dictionary) -> bool:
	return _can_stop_on(state, unit, state.unit_at(cell), unit.team, visible)


## The rule itself, over the occupancy and the sight the caller already has: the
## fill asks it once per cell and holds one `visible` for the whole walk.
##
## A unit the sighting team cannot see is planned through as if the cell were
## empty and looks like a place to stop, because nobody planning the move has a
## way to know to avoid it — the trap springs on commit. Anyone that team can see
## is stopped on by nobody, its own side included: Vision.can_see_unit always
## sees an ally. Staying put is always legal.
static func _can_stop_on(
	state: GameState, unit: Unit, occupant: Unit, seer: int, visible: Dictionary
) -> bool:
	if occupant == null or occupant == unit:
		return true
	return not Vision.can_see_unit(state, seer, occupant, visible)


## What `GameState.unit_at` answers, for every cell at once — same rule, same
## scan order, so a cell two units somehow shared would report the same one
## either way round. Kept local to the fill and rebuilt on every call: an index
## living anywhere longer than that would need every writer that moves, kills,
## builds, loads or unloads a unit to keep it right, and the one that forgot
## would not fail, it would quietly answer wrong.
static func _occupants(state: GameState) -> Dictionary[Vector2i, Unit]:
	var by_cell: Dictionary[Vector2i, Unit] = {}
	for unit in state.units:
		if unit.carrier == null and not by_cell.has(unit.cell):
			by_cell[unit.cell] = unit
	return by_cell


## `extra` is the hypothetical allowance described on move_budget, and is the
## only thing it changes here: every other rule of the fill is untouched.
##
## `sight_team` says whose knowledge of the board the fill plans occupancy with,
## and defaults to the mover's own — the rule every committed move is planned by.
## A caller drawing somebody *else's* reach names its own team instead, because a
## fill keyed to the mover is walled by units the mover can see and planned through
## the ones it cannot, so its silhouette alone would report which of the onlooker's
## pieces that unit has spotted (COM-57). Occupancy is all it changes: terrain,
## budget and doctrine stay the mover's throughout.
static func reachable(
	state: GameState, unit: Unit, extra: int = 0, sight_team: int = MOVER_SIGHT
) -> MoveRange:
	var result := MoveRange.new()
	result.origin = unit.cell
	result.costs[unit.cell] = 0
	result.stoppable[unit.cell] = true
	var budget := move_budget(state, unit, extra)
	var seer := unit.team if sight_team == MOVER_SIGHT else sight_team
	# Who stands where, worked out once for the whole fill rather than per step:
	# the fill asks about four cells for every cell it reaches, and asking the
	# board one cell at a time is a walk of the whole army per question.
	var occupants := _occupants(state)
	# And what a step onto each kind of ground costs, worked out the first time the
	# fill meets that kind: a board is a dozen kinds of ground and a fill asks
	# about hundreds of cells, and step_cost's third invariant is what lets one
	# answer serve them all.
	var step_costs: Dictionary[TerrainType, int] = {}
	# The sighting team's visible cells decide whether a unit on a cell counts at
	# all. Computed on first need and reused, so a fill that meets nobody — and any
	# fill at all with fog off — never pays for it.
	var visible: Dictionary = {}
	var visible_computed := false
	var frontier: Array[Vector2i] = [unit.cell]
	while not frontier.is_empty():
		# Maps are small; a linear min-scan beats a heap in simplicity.
		var best := 0
		var best_cost: int = result.costs[frontier[0]]
		for i in frontier.size():
			var cost: int = result.costs[frontier[i]]
			if cost < best_cost:
				best = i
				best_cost = cost
		var current: Vector2i = frontier[best]
		frontier.remove_at(best)
		for dir in DIRECTIONS:
			var next: Vector2i = current + dir
			var terrain := state.map.terrain_at(next)
			if terrain == null:
				continue
			var step: int = step_costs.get(terrain, 0)
			if step == 0:  # 0 is no legal cost, so it means "not asked yet"
				step = step_cost(state, unit, terrain)
				step_costs[terrain] = step
			if step == TerrainType.IMPASSABLE:
				continue
			var occupant: Unit = occupants.get(next)
			var stoppable := true
			if occupant != null:
				if state.fog_enabled and not visible_computed:
					visible = Vision.visible_cells(state, seer)
					visible_computed = true
				stoppable = _can_stop_on(state, unit, occupant, seer, visible)
				# A seen enemy is a wall; anyone on the mover's own side — its own units
				# and its allies alike — is passed through but never stopped on.
				if not stoppable and not state.allied(occupant.team, unit.team):
					continue
			var next_cost: int = best_cost + step
			if next_cost > budget:
				continue
			var known: int = result.costs.get(next, -1)
			if known >= 0 and known <= next_cost:
				continue
			result.costs[next] = next_cost
			result.parents[next] = current
			result.stoppable[next] = stoppable
			frontier.append(next)
	return result
