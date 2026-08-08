class_name AIPlanningContext
extends RefCounted
## Facts shared by the two AI planners during one command decision.
##
## `begin` snapshots every scan-ordered collection once, so unit actions and
## production see the same enemy, friendly, property, and unit-type order.
## Goals are filled lazily by the unit planner. The threat map is the one fact
## that deliberately survives between decisions: it is expensive, depends only
## on the enemy set during our turn, and is rebuilt when its signature changes.


## Where a unit should head when it has nothing better to do. `stand_off` marks
## goals we want to shoot rather than reach, so indirect units stop at range.
## `keeps_formation` is true on the advance on the enemy and on nothing else:
## that is the one goal cohesion shapes. Every errand an army sends a unit away
## on — refit, repair, a besieged home HQ, a property to take — must go untaxed,
## or the column's pull cancels the errand and the unit never arrives, so the
## default falls on the safe side.
class AdvanceGoal:
	var cell: Vector2i = Vector2i.ZERO
	var stand_off: bool = false
	var keeps_formation: bool = false


var state: GameState
var team: int = 0
var friendly_units: Array[Unit] = []
var ready_units: Array[Unit] = []
var visible_enemies: Array[Unit] = []
var owned_properties: Array[Vector2i] = []
var unit_types: Array[UnitType] = []
## Cost-weighted production input as [cost, type id] pairs, in enemy scan order.
var enemy_roster: Array = []
## Unit -> AdvanceGoal, populated only when that unit reaches its fallback move.
var goals: Dictionary = {}
## Unit -> claimed property cell, settled for every capturer at once the first
## time one asks. Exactly `goals`' lifetime — cleared by `begin`, so it is one
## command deep and nothing about a claim survives the board moving, which is
## what keeps AI Economy D3's rejected claims registry rejected.
var capture_claims: Dictionary = {}

var _unit_db: UnitDB
var _threat_map: ThreatMap = null
var _threat_key: String = ""

## Property cells no army allied with us holds, and whether that scan has run
## yet this command. Both planners ask the identical question over the
## identical scan — the unit planner's capture goal and the production
## planner's capture-unit target — so it is answered once here rather than
## twice with two bodies.
var _capturable_properties: Array[Vector2i] = []
var _capturable_properties_ready: bool = false

## Servicing properties by movement domain, a small Dictionary because a match
## fields at most a handful of domains. Cleared with everything else in `begin`.
var _servicing_properties: Dictionary = {}

## Home HQs of our own side under enemy capture threat, and whether that scan
## has run yet this command.
var _besieged_home_hqs: Array[Vector2i] = []
var _besieged_home_hqs_ready: bool = false


func _init(p_unit_db: UnitDB) -> void:
	_unit_db = p_unit_db


## Starts one command decision without discarding the per-turn threat cache.
func begin(p_state: GameState) -> void:
	state = p_state
	team = state.current_team
	friendly_units = state.units_of(team)
	ready_units = []
	for unit in friendly_units:
		if not unit.acted and unit.carrier == null:
			ready_units.append(unit)
	visible_enemies = _scan_visible_enemies(state, team)
	owned_properties = state.properties_of(team)
	unit_types = _unit_db.all()
	enemy_roster = []
	for enemy in visible_enemies:
		enemy_roster.append([enemy.type.cost, enemy.type.id])
	goals.clear()
	capture_claims.clear()
	_capturable_properties_ready = false
	_servicing_properties.clear()
	_besieged_home_hqs_ready = false


## Property cells held by nobody allied with us, in map scan order. Built on
## first use and cached for this command: both planners ask the same
## question over the same board, and the property list itself never changes
## mid-command.
func capturable_properties() -> Array[Vector2i]:
	if not _capturable_properties_ready:
		_capturable_properties = []
		for cell in state.map.property_cells():
			if not state.allied(state.owner_at(cell), team):
				_capturable_properties.append(cell)
		_capturable_properties_ready = true
	return _capturable_properties


## Our own properties that refuel and repair `domain`, memoised per domain —
## a unit's refit and repair goals, and its withdrawal's refuge, all ask this
## same question and there are only ever a few domains in play at once.
func servicing_properties(domain: StringName) -> Array[Vector2i]:
	if not _servicing_properties.has(domain):
		var cells: Array[Vector2i] = []
		for cell in owned_properties:
			if state.map.terrain_at(cell).services_domain(domain):
				cells.append(cell)
		_servicing_properties[domain] = cells
	return _servicing_properties[domain]


## Home HQs of our own side with a capture-capable enemy standing on them, in
## enemy scan order. Built once per command — the team is fixed for the whole
## decision, so this needs no per-unit key.
func besieged_home_hqs() -> Array[Vector2i]:
	if not _besieged_home_hqs_ready:
		_besieged_home_hqs = []
		for enemy in visible_enemies:
			if not enemy.type.can_capture:
				continue
			var owner := state.owner_at(enemy.cell)
			if not state.allied(owner, team):
				continue
			if state.home_hq.has(owner) and state.home_hq[owner] == enemy.cell:
				_besieged_home_hqs.append(enemy.cell)
		_besieged_home_hqs_ready = true
	return _besieged_home_hqs


## The threat map for the current turn, built on first use and rebuilt whenever
## the day, planning team, or visible enemy set changes. Within the AI's own turn
## only the enemy set can change, when an enemy dies to a counter.
func threat_map() -> ThreatMap:
	var key := _threat_signature(state, visible_enemies)
	if _threat_map == null or _threat_key != key:
		_threat_map = ThreatMap.build(state, visible_enemies)
		_threat_key = key
	return _threat_map


## Whether the map for the board as it stands has already been built this turn.
## The build is lazy and its flood fills are taken against the board at the
## moment of first need, so *when* it happens is part of the answer — which is
## what anything planning to skip a decision has to know before it does.
func threat_map_built() -> bool:
	return _threat_map != null and _threat_key == _threat_signature(state, visible_enemies)


## The enemy units this planner may act on. The AI sees the whole board on
## purpose, with exactly one exception: a unit a doctrine has hidden is hidden
## from it too. Vision owns that exception; visibility is never re-derived here,
## and neither is hostility — an ally is not an enemy, so it is never fired on,
## never feared in the threat map and never pathed around as a blocker.
static func _scan_visible_enemies(p_state: GameState, p_team: int) -> Array[Unit]:
	var enemies: Array[Unit] = []
	for unit in p_state.units:
		if p_state.allied(unit.team, p_team) or unit.carrier != null:
			continue
		if Vision.is_hidden_from(p_state, p_team, unit):
			continue
		enemies.append(unit)
	return enemies


static func _threat_signature(p_state: GameState, enemies: Array[Unit]) -> String:
	var parts := PackedStringArray()
	parts.append("%d.%d" % [p_state.day, p_state.current_team])
	for enemy in enemies:
		parts.append("%d.%d.%d" % [enemy.team, enemy.cell.x, enemy.cell.y])
	return ",".join(parts)
