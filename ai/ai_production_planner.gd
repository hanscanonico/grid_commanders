class_name AIProductionPlanner
extends RefCounted
## Chooses one build across every empty owned production facility.
##
## Production remains one coarse collaborator: roster analysis, banking, and
## candidate ranking are one comparison pipeline and share the same BuildWants
## value object. AIController remains the public façade.

## Spacing between the tiers production ranks candidates in. Wide enough that
## no tier's own ordering can reach into the next.
const TIER_STRIDE := 1000
## "Never buy this" — above every tier, so it loses every comparison.
const RANK_NONE := TIER_STRIDE * 100


## Board-wide production questions, worked out once per decision and passed as
## values. Its factory deliberately accepts no planner or controller callback.
class BuildWants:
	var outgunned_in_the_air: bool = false
	var short_of_capture_units: bool = false
	## Unit id -> number the team already fields.
	var owned: Dictionary = {}
	## Unit id -> place in S3's standing tier, best first.
	var reactive_order: Dictionary = {}
	## Unit id -> places of commander re-rank, already scaled by doctrine_weight.
	var doctrine_bias: Dictionary = {}

	static func from_facts(
		friendly_units: Array[Unit],
		p_outgunned_in_the_air: bool,
		capture_unit_target: int,
		p_reactive_order: Dictionary,
		p_doctrine_bias: Dictionary
	) -> BuildWants:
		var wants := BuildWants.new()
		wants.outgunned_in_the_air = p_outgunned_in_the_air
		var capture_units := 0
		for unit in friendly_units:
			var id := unit.type.id
			wants.owned[id] = int(wants.owned.get(id, 0)) + 1
			if unit.type.can_capture:
				capture_units += 1
		wants.short_of_capture_units = capture_units < capture_unit_target
		wants.reactive_order = p_reactive_order
		wants.doctrine_bias = p_doctrine_bias
		return wants

	func count_of(id: StringName) -> int:
		return int(owned.get(id, 0))

	func bias_of(id: StringName) -> int:
		return int(doctrine_bias.get(id, 0))

	func first_priority_rank() -> int:
		return TIER_STRIDE * 2


var profile: AIProfile


func _init(p_profile: AIProfile) -> void:
	profile = p_profile


## The best build any facility can produce, or null when banking one more turn
## buys something better.
func plan(context: AIPlanningContext) -> Command:
	var state := context.state
	var funds: int = state.funds[context.team]
	var wants := BuildWants.from_facts(
		context.friendly_units,
		_outgunned_in_the_air(context),
		profile.capture_unit_target,
		_reactive_order(context),
		_doctrine_bias(context)
	)
	var best_cell := Vector2i.ZERO
	var best_choice: UnitType = null
	var best_rank := RANK_NONE
	var facilities: Array[TerrainType] = []
	for cell in context.owned_properties:
		var terrain := state.map.terrain_at(cell)
		if terrain.builds.is_empty() or state.unit_at(cell) != null:
			continue
		facilities.append(terrain)
		var choice := _pick_build(context, terrain, wants, funds)
		if choice == null:
			continue
		var rank := _build_rank(choice, wants)
		if rank < best_rank:
			best_rank = rank
			best_choice = choice
			best_cell = cell
	if best_choice == null:
		return null
	if _worth_waiting_for(context, facilities, wants, funds, best_rank):
		return null
	return BuildCommand.new(context.team, best_choice, best_cell)


## The best unit this facility can produce for the money, or null.
func _pick_build(
	context: AIPlanningContext, terrain: TerrainType, wants: BuildWants, funds: int
) -> UnitType:
	var best: UnitType = null
	var best_rank := RANK_NONE
	for unit_type in context.unit_types:
		var price := UnitPricing.cost_for(context.state, context.team, unit_type)
		if not terrain.can_build(unit_type.move_class) or funds < price:
			continue
		var rank := _build_rank(unit_type, wants)
		if rank < best_rank:
			best_rank = rank
			best = unit_type
	return best


## True when the team should bank instead of buying `best_rank`.
func _worth_waiting_for(
	context: AIPlanningContext,
	facilities: Array[TerrainType],
	wants: BuildWants,
	funds: int,
	best_rank: int
) -> bool:
	if best_rank < wants.first_priority_rank() or profile.save_up_turns <= 0:
		return false
	var income := context.owned_properties.size() * GameState.INCOME_PER_PROPERTY
	var budget := funds + income * profile.save_up_turns
	for terrain in facilities:
		for unit_type in context.unit_types:
			var price := UnitPricing.cost_for(context.state, context.team, unit_type)
			if not terrain.can_build(unit_type.move_class) or price > budget:
				continue
			if _build_rank(unit_type, wants) < best_rank:
				return true
	return false


## How much the team wants `unit_type`, lower being more wanted: answer enemy
## aircraft, fill the capture roster, follow the standing priority, then any
## capture unit. Transports reach no tier and remain unbuilt.
##
## The commander's doctrine bias moves a unit within the priority tier only —
## the urgent tiers above outrank any doctrine, and the tier floor keeps a
## pulled-up unit from reading as urgent to the banking rule.
func _build_rank(unit_type: UnitType, wants: BuildWants) -> int:
	if wants.outgunned_in_the_air:
		var answer := profile.air_answer_ids.find(unit_type.id)
		if answer >= 0:
			return answer
	if unit_type.can_capture and wants.short_of_capture_units:
		return TIER_STRIDE
	var duplicates := wants.count_of(unit_type.id) * profile.duplicate_priority_cost
	var bias := wants.bias_of(unit_type.id)
	if wants.reactive_order.has(unit_type.id):
		var reactive := int(wants.reactive_order[unit_type.id])
		return TIER_STRIDE * 2 + maxi(0, reactive + duplicates + bias)
	var priority := profile.build_priority.find(unit_type.id)
	if priority >= 0:
		return TIER_STRIDE * 2 + maxi(0, priority + duplicates + bias)
	if bias < 0 and unit_type.max_range > 0:
		# A doctrine may pull a combat unit the list omits onto its tail — never
		# a transport, which stays without a rank to move.
		return TIER_STRIDE * 2 + maxi(0, profile.build_priority.size() + duplicates + bias)
	if unit_type.can_capture:
		return TIER_STRIDE * 3
	return RANK_NONE


## Unit id -> how far the commander's doctrine moves it on the build list,
## scaled by the profile's doctrine weight. Empty when the dial is off — the
## hook is then never called, which keeps a zero-weight profile byte-identical.
func _doctrine_bias(context: AIPlanningContext) -> Dictionary:
	if profile.doctrine_weight <= 0.0:
		return {}
	var commander := context.state.commander_of(context.team)
	var bias: Dictionary = {}
	for unit_type in context.unit_types:
		var advice := commander.build_bias(context.state, context.team, unit_type)
		if advice != 0:
			bias[unit_type.id] = int(roundf(profile.doctrine_weight * float(advice)))
	return bias


## S3. Orders combat units by how well they answer the enemy's cost-weighted
## roster, blended with the static build-priority order.
func _reactive_order(context: AIPlanningContext) -> Dictionary:
	if profile.build_reactivity <= 0.0 or context.enemy_roster.is_empty():
		return {}
	var candidates: Array[UnitType] = []
	var effectiveness: Dictionary = {}
	var max_eff := 0.0
	for unit_type in context.unit_types:
		if unit_type.max_range <= 0:
			continue
		candidates.append(unit_type)
		var value := _effectiveness(context.state, unit_type, context.enemy_roster)
		effectiveness[unit_type.id] = value
		max_eff = maxf(max_eff, value)
	if max_eff <= 0.0:
		return {}
	var priority := profile.build_priority
	var scored: Array = []
	for i in candidates.size():
		var cand := candidates[i]
		var static_norm := 0.0
		var rank := priority.find(cand.id)
		if rank >= 0:
			static_norm = float(priority.size() - rank) / float(priority.size())
		var eff_norm := float(effectiveness[cand.id]) / max_eff
		var score := (
			(1.0 - profile.build_reactivity) * static_norm + profile.build_reactivity * eff_norm
		)
		scored.append([score, i, cand.id])
	scored.sort_custom(_by_score_then_scan_order)
	var order: Dictionary = {}
	for i in scored.size():
		order[scored[i][2]] = i
	return order


## Best score first, ties broken by database order.
static func _by_score_then_scan_order(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] > b[0]
	return a[1] < b[1]


## Cost-weighted mean base damage `candidate` deals across the enemy roster.
static func _effectiveness(state: GameState, candidate: UnitType, roster: Array) -> float:
	var total_weight := 0.0
	var weighted := 0.0
	for entry in roster:
		var enemy_cost: float = float(entry[0])
		total_weight += enemy_cost
		var damage := state.damage_chart.base_damage(candidate.id, entry[1])
		if damage > 0:
			weighted += enemy_cost * damage
	if total_weight <= 0.0:
		return 0.0
	return weighted / total_weight


## Whether the enemy is flying and we field fewer units that can answer it than
## the profile wants.
func _outgunned_in_the_air(context: AIPlanningContext) -> bool:
	var state := context.state
	var flying: Array[Unit] = []
	for enemy in context.visible_enemies:
		if enemy.type.domain == UnitType.AIR:
			flying.append(enemy)
	if flying.is_empty():
		return false
	var answers := 0
	for unit in context.friendly_units:
		if _can_hit_any(state, unit, flying):
			answers += 1
	return answers < profile.air_answer_target


static func _can_hit_any(state: GameState, unit: Unit, targets: Array[Unit]) -> bool:
	if unit.type.max_range <= 0:
		return false
	for target in targets:
		if AttackRange.can_fire(state, unit, target):
			return true
	return false
