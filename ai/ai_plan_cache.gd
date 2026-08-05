class_name AIPlanCache
extends RefCounted
## Keeps each ready unit's AIUnitPlan between the commands of one turn, and
## drops the ones the last command could have changed.
##
## The planner answers with one command and the caller asks again, so scoring
## every ready unit each time is N + (N-1) + ... + 1 full plans per turn where N
## plus a handful of deltas would do. Re-planning after every command is
## load-bearing all the same — it is how a wounded target's kill reaches the
## next attacker without a focus-fire dial — so this has to be *exactly*
## equivalent: it may drop a plan that had not changed, and it may never keep
## one that had.
##
## What changed is read off a board diff taken between calls, never off the
## Command the planner returned, because the returned command is not reliably
## the one that landed: the harness swaps in an EndTurnCommand for a rejected
## command or an overlong turn without telling the planner, a PowerCommand moves
## HP across the whole board and touches no cell in particular, and in the live
## scene an ambush stops a move short of the cell it was planned to. The diff
## costs one pass over the units and is right whatever actually happened.
##
## Node-free like the rest of ai/.

## The numbers every kept plan was scored with. Which dials are live decides what
## a plan can depend on, so the cache reads the same profile the planner does.
var profile: AIProfile

var _plans: Dictionary = {}  # Unit -> AIUnitPlan
var _turn_key := ""
var _units: Dictionary = {}  # Unit -> the condition below, as of the last sync
var _owners: Dictionary = {}
var _meters: Dictionary = {}  # team -> [charge, power_active]
var _enemies: Array[Unit] = []
## Set by the diff: the enemy list or the ground our side holds moved, so every
## goal on the board was chosen over a different list.
var _stale_goals := false
## Set by the diff: a capturer moved, so every capturer's claim was re-dealt.
var _stale_claims := false
## Set by the diff: movement domain -> a unit of it moved, so its column shifted.
var _stale_columns: Dictionary = {}


func _init(p_profile: AIProfile) -> void:
	profile = p_profile


## Drops every plan a command since the last call could have changed. Call once
## per planned command, before asking for anything.
func sync(context: AIPlanningContext) -> void:
	_stale_goals = false
	_stale_claims = false
	_stale_columns.clear()
	var turn := _turn_signature(context)
	if turn != _turn_key or not _may_keep(context) or not _drop_what_changed(context):
		_plans.clear()
	_turn_key = turn
	_record(context)


## The plan still good for `unit`, or null when it has to be scored afresh.
func plan_for(unit: Unit) -> AIUnitPlan:
	return _plans.get(unit)


## Whether a kept plan's fallback advance moved under it while its actions held.
## Three things reach a goal from outside every envelope, and only these three:
## the board's own list of who is left to walk at, the capture claim dealt over
## where every *other* capturer stands, and the column a unit keeps station with,
## which is every friendly of its domain wherever it is. None of them touches a
## plan that is not the fallback, and the last two are inert at their dial's
## shipped value.
func advance_is_stale(unit: Unit) -> bool:
	var plan := plan_for(unit)
	if plan == null or not plan.advances:
		return false
	if _stale_goals:
		return true
	if _stale_claims and profile.capture_claim_depth > 0 and unit.type.can_capture:
		return true
	return (
		plan.keeps_formation
		and profile.cohesion_tiles > 0.0
		and _stale_columns.has(unit.type.domain)
	)


func keep(unit: Unit, plan: AIUnitPlan) -> void:
	_plans[unit] = plan


## One planning team's turn on one board. A controller lives as long as the
## match, so without the day and the team a cache would serve plans across the
## enemy's whole turn; without the board it would serve them into another match.
static func _turn_signature(context: AIPlanningContext) -> String:
	var state := context.state
	return "%d.%d.%d" % [state.get_instance_id(), state.day, context.team]


## Three things a plan can depend on that no envelope around the unit bounds.
## While any of them is in play nothing is kept, which is the shipped planner
## exactly.
##
## Fog: a unit's own reach is filled with its *side's* sight of the board, so
## which enemies wall it off moves with every friendly that walks.
## Focus fire: a shot is priced by what every other ready friendly could still
## add to that same target.
## The threat map: it is built once per turn, lazily, against the board as it
## stands at the moment of first need — so *when* it is built is part of the
## answer, and a cache that skips a replan could move that moment. Once the
## turn's map exists its contents are frozen and the cache can run; what reads
## of it depend on beyond that is an enemy's condition, which the diff watches.
func _may_keep(context: AIPlanningContext) -> bool:
	if context.state.fog_enabled or profile.focus_fire_bonus > 0.0:
		return false
	return not _weighs_threat() or context.threat_map_built()


## The three dials that build a threat map, and the reason this is stated twice:
## each of them gates its own read in AIUnitActionPlanner, and a fourth one added
## there has to be added here too or the cache would keep plans made before the
## map existed.
##
## `dive_score` reads the map too and is deliberately not a fourth. It is live in
## every profile, so listing it here would keep nothing on any board — including
## every board with no submarine on it — for a read only a submarine makes; and
## its read is the last branch of a plan whose earlier branches decide whether it
## is reached, so a re-score the cache skipped would have taken the same branch
## and the moment the map is built cannot move. The narrow sea in
## tests/unit/test_ai_plan_cache.gd is what holds that.
func _weighs_threat() -> bool:
	return (
		profile.threat_aversion > 0.0
		or profile.advance_threat_tiles > 0.0
		or profile.withdraw_weight > 0.0
	)


## Walks the board against the last snapshot, dropping the plans whose ground
## moved and marking the goals that were chosen over a list that has since
## changed. False when what changed reaches further than any envelope can and the
## whole cache has to go — three things do:
##
## - ground changing hands re-prices every goal and every refit on the board, and
##   a refuge is chosen off the refits;
## - a commander's meter or power moves HP, fuel, ammo, reach and the doctrine
##   hooks at once, and Sable Wren prices a tile off the meter itself;
## - any enemy moving, dying or being found while a threat dial is live, because
##   the threat map is read from as far away as that enemy can shoot and rebuilt
##   the moment the set it was keyed on changes.
##
## Everything else is a cell, or the fallback advance, or both.
func _drop_what_changed(context: AIPlanningContext) -> bool:
	var state := context.state
	if _owners != state.property_owners or _meters != _read_meters(state):
		return false
	# Capture progress is not compared: every rule that moves it moves it on a
	# cell some unit stepped onto or off — the capture itself, the walk away that
	# abandons one — or takes that unit off the board, so it is already touched.
	var touched: Array[Vector2i] = []
	var enemy_moved := false
	var present: Dictionary = {}
	for unit in state.units:
		present[unit] = true
		var before: Array = _units.get(unit, [])
		if before == _condition(unit):
			continue
		# A unit that was not there last time is one a base has just put on the
		# board: new company for its domain, wherever it stands.
		var arrived := before.is_empty()
		var was: Vector2i = unit.cell if arrived else before[0]
		touched.append(was)
		touched.append(unit.cell)
		if _note_change(unit, context, arrived or was != unit.cell):
			enemy_moved = true
	for unit: Unit in _units:
		if present.has(unit):
			continue
		touched.append(_units[unit][0])
		if _note_change(unit, context, true):
			enemy_moved = true
	if _enemies != context.visible_enemies:
		enemy_moved = true
		# Who is left to walk at, and which of our home HQs is under somebody, are
		# read off the whole list rather than off the ground around one unit.
		_stale_goals = true
		# So is whether to be under the water: a dive is judged against every
		# enemy's own reach, which is further than ours.
		for unit: Unit in _plans.keys():
			if unit.type.can_dive:
				_plans.erase(unit)
	if enemy_moved and _weighs_threat():
		return false
	_drop_inside(state, touched)
	return true


## Files one changed unit under what its change reaches, and answers whether it
## was an enemy's. Only our own army keeps formation or deals claims; an enemy's
## condition is priced where it stands, and the list it belongs to is read apart.
func _note_change(unit: Unit, context: AIPlanningContext, moved: bool) -> bool:
	if unit.team != context.team:
		return true
	if moved:
		_stale_columns[unit.type.domain] = true
	if unit.type.can_capture:
		_stale_claims = true
	return false


## Everything a plan reads is either a cell its unit could reach, something
## standing inside its weapon's range of one of those, or the ring beyond that a
## doctrine reads for company — so a Manhattan envelope of that width around the
## unit covers all of it. Deliberately an over-approximation: it may drop a plan
## that had not changed, and it can never keep one that had.
##
## A supply unit's ring is wider than its weapon's, and it is the commander's
## rather than one tile: Gideon Holt refills two cells out, which a supply plan
## is priced on and which the +1 above would not cover.
func _drop_inside(state: GameState, cells: Array[Vector2i]) -> void:
	for unit: Unit in _plans.keys():
		var envelope := (
			MovementResolver.move_budget(state, unit) + AttackRange.maximum(state, unit) + 1
		)
		if unit.type.can_resupply:
			envelope += state.commander_of(unit.team).supply_range(state, unit)
		for cell in cells:
			if Grid.manhattan(cell, unit.cell) <= envelope:
				_plans.erase(unit)
				break


func _record(context: AIPlanningContext) -> void:
	var state := context.state
	_units.clear()
	for unit in state.units:
		_units[unit] = _condition(unit)
	_owners = state.property_owners.duplicate()
	_meters = _read_meters(state)
	_enemies = context.visible_enemies.duplicate()


## Everything about a unit a plan can be scored against, in one comparable row.
static func _condition(unit: Unit) -> Array:
	return [unit.cell, unit.hp, unit.acted, unit.fuel, unit.ammo, unit.dived, unit.carrier]


static func _read_meters(state: GameState) -> Dictionary:
	var meters: Dictionary = {}
	for team in state.teams:
		var co_state := state.commander_state(team)
		meters[team] = [co_state.charge, co_state.power_active]
	return meters
