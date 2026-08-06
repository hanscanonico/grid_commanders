class_name TurnRules
extends RefCounted
## Start-of-turn bookkeeping for the current team: income, fuel upkeep, resupply,
## paid repairs on friendly properties, and readying units. Used by
## GameState.create for the first turn and by EndTurnCommand after.
##
## It also owns the two turn rules its own bookkeeping shares with a command —
## `in_supply_reach` and `expire_power` — because each was implemented twice and
## the two copies had already started to drift.

const REPAIR_HP := 20  # internal HP (= 2 displayed) per turn on a property


## Every turn is charged the same, day one included. That is what keeps the two
## sides even: create() opens the match with this for the first team, and the
## second team gets its own call through EndTurnCommand before it acts, so both
## have paid exactly once by the time they move. Skipping the opening day would
## have charged the first player one fewer time over any equal count of turns.
static func begin_turn(state: GameState) -> void:
	var team := state.current_team
	expire_power(state, team, CommanderType.Duration.ROUND)
	state.funds[team] += income_for(state, team)
	for unit in state.units_of(team):
		unit.acted = false
		unit.refreshable = false
		if unit.carrier != null:
			continue  # cargo burns no upkeep; its transport refills it below
		_burn_upkeep(unit)
		if _serviced_here(state, unit) or _in_reach_of_supplier(state, unit):
			unit.resupply()
		if _lost_to_empty_tank(state, unit):
			continue  # nothing left to repair, and its cargo went down with it
		_resupply_cargo(state, unit)
		_repair(state, unit)


## What a turn pays `team`: every property it holds, at the same flat rate. The
## planner asks this when it weighs banking against buying, so what the AI
## expects to be paid is what the turn actually pays it.
static func income_for(state: GameState, team: int) -> int:
	return state.properties_of(team).size() * GameState.INCOME_PER_PROPERTY


## Fuel spent simply by existing, before anything refills it. Zero for ground
## units, which is why a tank parked in a field is the same unit it was in M2, and
## several times the surface rate for a submarine that is under — the clock a dive
## is played against.
static func _burn_upkeep(unit: Unit) -> void:
	unit.fuel = maxi(0, unit.fuel - unit.upkeep())


## A transport refuels and re-ammoes every unit it carries, in full and wherever
## it stands — cargo is refilled by its transport, not beside it, so a rider that
## boarded on empty rides out full. Called only for a transport that survived its
## own upkeep, so cargo lost with a dry carrier is never touched; and cargo burns
## no upkeep of its own, so there is nothing to spend before this refill.
static func _resupply_cargo(state: GameState, transport: Unit) -> void:
	for passenger in state.cargo_of(transport):
		passenger.resupply()


## An air or sea unit whose tank reached zero is destroyed here, and its cargo
## with it (remove_unit's rule, shared with every other death).
##
## The order in begin_turn is the whole mechanic and none of it is incidental:
## upkeep is charged *before* resupply, so a plane that never lands eventually
## falls; resupply runs before this check, so one that did land is always full
## again and can never die on friendly tarmac; and the check sits before repair
## because there is nothing left to mend. Nothing is banked to either Command
## Power meter — running yourself dry is not an exchange, and paying the other
## side charge for it would make starving your own air force a tactic.
static func _lost_to_empty_tank(state: GameState, unit: Unit) -> bool:
	if not unit.type.lost_when_dry() or unit.fuel > 0:
		return false
	state.remove_unit(unit)
	return true


## Whether the property `unit` stands on is one of ours *and* refits its domain.
## The single answer to that question: repair and resupply both ask it, so no
## property can ever refuel something it refuses to repair.
##
## `owner_at == unit.team`, deliberately not `allied` (four-players plan D2):
## allies share sight and purpose, never infrastructure. An ally's workshop does
## not repair your tanks, and the funds the repair is billed against are its own.
static func _serviced_here(state: GameState, unit: Unit) -> bool:
	if state.owner_at(unit.cell) != unit.team:
		return false
	return state.map.terrain_at(unit.cell).services_domain(unit.type.domain)


## Takes `team`'s Command Power down when it is one of `duration`, and the only
## way one ever comes down. An OWNER_TURN power ends with the turn it was fired on
## and EndTurnCommand asks for it there; a ROUND power covers the opponent's turn
## and runs out the moment its owner's next one opens, which is the call above,
## before the turn it no longer applies to does anything.
static func expire_power(state: GameState, team: int, duration: CommanderType.Duration) -> void:
	var co_state := state.commander_state(team)
	if co_state.power_active and co_state.type.power_duration == duration:
		co_state.power_active = false


## +2 displayed HP on a friendly property that services this unit's domain, paid
## proportionally to unit cost. Skipped (not partial) when funds don't cover the
## full heal.
static func _repair(state: GameState, unit: Unit) -> void:
	if unit.hp >= 100:
		return
	if not _serviced_here(state, unit):
		return
	var heal := mini(REPAIR_HP, 100 - unit.hp)
	var full_price := unit.type.cost * heal / 100
	var cost := full_price * state.commander_of(unit.team).repair_cost_pct(state, unit) / 100
	if state.funds[unit.team] < cost:
		return
	state.funds[unit.team] -= cost
	unit.hp += heal


## A supply unit close enough to reach `unit`, asked of the rule below so the
## turn's automatic top-up and the Supply action can never disagree about who is
## in reach of whom.
static func _in_reach_of_supplier(state: GameState, unit: Unit) -> bool:
	for other in state.units_of(unit.team):
		if in_supply_reach(state, other, other.cell, unit):
			return true
	return false


## Whether `supplier`, standing on `from`, could top `other` up: its own team's,
## and within the radius its commander sets — one tile for most, two for Gideon
## Holt, so the radius is asked for rather than assumed to be adjacency. Neither
## end may be cargo: a passenger is refilled by its transport at the turn's start,
## not by an APC parked beside it.
##
## `from` is a parameter rather than read off the supplier because the Supply
## action asks before it moves, the same reason CombatResolver.forecast_at takes
## the defender's cell.
##
## A supplier never tops itself up, and that is the identity check rather than a
## floor on the distance: two units that are not cargo can never share a cell, so
## a floor would only ever answer for a board the rules cannot produce.
static func in_supply_reach(state: GameState, supplier: Unit, from: Vector2i, other: Unit) -> bool:
	if other == supplier or not supplier.type.can_resupply:
		return false
	if supplier.carrier != null or other.carrier != null or other.team != supplier.team:
		return false
	var radius := state.commander_of(supplier.team).supply_range(state, supplier)
	return Grid.manhattan(from, other.cell) <= radius
