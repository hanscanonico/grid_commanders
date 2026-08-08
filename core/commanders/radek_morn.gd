class_name RadekMorn
extends CommanderType
## Iron Dominion. The hammer: every unit is a flat few points better at hitting
## and at being hit, in every domain and every exchange, and nothing anywhere is
## paid for it. Iona Vance's shape, simply turned up — both terms count equally,
## because the formula reads defence as (200 - def) / 100.
##
## Hammerfall is the game's first *aimed* power and its only lethal one: the
## player names a cell and everything standing in the square around it is
## destroyed outright, full health or not, his own and his ally's included. It is
## the most expensive power on the roster and the only one that can miss — aim it
## a tile off and it lands on empty ground with the meter already spent.

## Attack and defence percentage points on every unit, always. Read through
## (200 - def) / 100, so a point of defence is worth a point of attack.
@export var hammer_attack_pct: int = 5
@export var hammer_defense_pct: int = 5
## Chebyshev radius of the blast: 1 is the eight neighbours and the centre.
@export var hammer_radius: int = 1
## Funds of net destruction the computer waits for before spending the meter:
## what the best square on the board has to be worth in units it would clear, its
## own side's losses already deducted. Deliberately modest — the meter is capped
## at the cost, so charge banked past a full one is thrown away, and holding out
## for a richer square is how a doctrine spends a whole match at 24,000 and never
## fires.
@export var hammer_want_value: int = 5000


## The best square on the board, and what firing at it is worth. One answer
## behind both the gate and the aim (plan D5): `wants_power` is "that value clears
## the price" and `power_target` is "that cell", so he can never want to fire and
## then aim somewhere he did not want to.
class Blast:
	extends RefCounted

	var cell := Vector2i.ZERO
	var value := 0


func attack_bonus(_state: GameState, _fight: Engagement) -> int:
	return hammer_attack_pct


func defense_bonus(_state: GameState, _fight: Engagement) -> int:
	return hammer_defense_pct


func aims_power() -> bool:
	return true


## Chebyshev radius `hammer_radius` about the aim, clipped to the board, in scan
## order. The single authority for the footprint (plan D3) — the overlay, the
## computer's score and the destruction below all read this one function, so a
## corner aim catches fewer tiles everywhere at once or nowhere at all.
func power_blast_cells(state: GameState, _team: int, target: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(target.y - hammer_radius, target.y + hammer_radius + 1):
		for x in range(target.x - hammer_radius, target.x + hammer_radius + 1):
			var cell := Vector2i(x, y)
			if state.map.in_bounds(cell):
				cells.append(cell)
	return cells


## Everything standing in the square, off the board. Whoever owns it, whatever it
## is, however much health it has left — and cargo with the transport it is
## riding, which `remove_unit` already takes down.
##
## Three rules ride on that, all of them D4's. The doomed are collected before any
## of them is removed, because `remove_unit` mutates the very list the footprint
## is being read against. And nothing is banked to either meter: charge is minted
## in three calls inside CombatResolver and nowhere else, so a death outside a
## fight pays nobody — the same rule a plane that starves its own tank relies on.
## And the whole batch goes through `GameState.remove_units` rather than a loop
## of `remove_unit`, so a blast that empties two armies at once is decided by
## the board, never by which of them this scan happened to reach first
## (COM-179).
##
## Properties are untouched. A headquarters, factory or city in the square keeps
## its owner; only what is standing on it dies.
func on_power_activated(state: GameState, team: int, target: Vector2i = Vector2i.ZERO) -> void:
	var doomed: Array[Unit] = []
	for cell in power_blast_cells(state, team, target):
		var unit := state.unit_at(cell)
		if unit != null:
			doomed.append(unit)
	state.remove_units(doomed)


## The board scan behind both `wants_power` and `power_target`, memoised for the
## one call site that asks both back to back with nothing applied between them
## (`AIController._plan_power`, plan D5's shape: one gate, one aim, one function).
## `wants_power` is the only writer and never trusts a memo itself — it is asked
## once a decision for as long as the meter sits full, and the board moves between
## decisions, so it always rescans and re-stamps. `power_target` only ever reads
## the memo back, and only when the key still matches what `wants_power` just
## stamped; called any other way — every direct test in this suite calls it on its
## own — it falls through to a fresh scan rather than risk a stale one. The key is
## deliberately coarse (state identity, day, team, unit count): it is not asked to
## detect every mutation, only to prove none happened since the write moments ago,
## and a unit count drop after a scan is the one mutation firing itself can cause.
var _blast_key: Array = []
var _blast: Blast = null


func _blast_cache_key(state: GameState, team: int) -> Array:
	return [state.get_instance_id(), state.day, team, state.units.size()]


func power_target(state: GameState, team: int) -> Vector2i:
	var key := _blast_cache_key(state, team)
	if _blast != null and _blast_key == key:
		return _blast.cell
	return _best_blast(state, team).cell


func wants_power(state: GameState, team: int) -> bool:
	var blast := _best_blast(state, team)
	_blast_key = _blast_cache_key(state, team)
	_blast = blast
	return blast.value >= hammer_want_value


## The best square, walked in scan order over the board so a replan off one board
## always agrees with itself; ties keep the earliest cell. Seeded with the origin
## rather than a sentinel, so the value reported is always a square somebody could
## actually aim at.
##
## Rule-based, integer and RNG-free, and it never asks the damage chart: a kill is
## a kill here, so there is nothing to forecast (doctrine-AI plan D4).
func _best_blast(state: GameState, team: int) -> Blast:
	var standing := _standing_value(state, team)
	var best := Blast.new()
	best.value = _footprint_value(state, team, best.cell, standing)
	for y in state.map.height:
		for x in state.map.width:
			var cell := Vector2i(x, y)
			var value := _footprint_value(state, team, cell, standing)
			if value > best.value:
				best.cell = cell
				best.value = value
	return best


## What the blast at `target` is worth, in funds. Through `power_blast_cells` like
## everything else, so the square he scores is the square he clears.
func _footprint_value(state: GameState, team: int, target: Vector2i, standing: Dictionary) -> int:
	var value := 0
	for cell in power_blast_cells(state, team, target):
		value += int(standing.get(cell, 0))
	return value


## Cell -> what taking whatever stands there off the board is worth to him: a
## hostile unit a gain, one of his own side a loss. Built once per scan rather
## than asked per square, since every square the board offers reads the same
## units.
func _standing_value(state: GameState, team: int) -> Dictionary:
	var table: Dictionary = {}
	for unit in state.units:
		# A passenger is lost on its transport's cell — its own is stale from
		# wherever it last boarded, and the transport is what the blast finds.
		var cell := unit.cell if unit.carrier == null else unit.carrier.cell
		table[cell] = int(table.get(cell, 0)) + _worth_to(state, team, unit)
	return table


## A unit's price scaled by the health it has left, signed by whose it is.
## Anything hidden from him is worth nothing, which is the sight authority every
## other doctrine gate goes through rather than around.
func _worth_to(state: GameState, team: int, unit: Unit) -> int:
	if Vision.is_hidden_from(state, team, unit):
		return 0
	var worth := unit.type.cost * unit.hp / 100
	return -worth if state.allied(unit.team, team) else worth
