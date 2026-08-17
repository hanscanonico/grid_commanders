class_name PowerEffects
extends RefCounted
## What a fired Command Power visibly did to the board: one mark per unit it
## touched, so an activation is more than a card in the middle of the screen.
##
## It computes nothing and re-decides nothing (the cut-in's D1, applied to a
## power): every mark is the difference between a snapshot taken before the
## command applied and the board it left behind, and the blast footprint is handed
## in from `CommanderType.power_blast_cells` — the single footprint authority the
## aim preview and the strike itself already read.
##
## Node-free and pure, the way `PathArrow.segments` and `SeatStrip.normalised_sides`
## are, so what a power marks is checked without a scene.

enum Kind {
	## The unit is off the board — Hammerfall's square, and nothing else in the
	## game removes a unit without a shot.
	DESTROYED,
	HARMED,
	HEALED,
	## Colt's Second Wind: the unit may act again.
	REFRESHED,
	## Fuel or ammo back in the tank.
	RESUPPLIED,
	## The doctrine now has something to say about this unit that it did not have
	## a moment ago, and vice versa for HINDERED (Orin Flux's Signal Jam).
	EMPOWERED,
	HINDERED,
}


## One board mark. `unit` is null for a blast square nothing was standing on,
## which is still worth painting: the footprint is what an aimed power did.
class Mark:
	extends RefCounted

	var cell: Vector2i
	var kind: Kind
	## Displayed HP pips the mark moved, and 0 for every mark that is not about
	## health — the number a player reads off a unit, never internal HP.
	var pips: int
	var unit: Unit

	func _init(p_cell: Vector2i, p_kind: Kind, p_pips: int = 0, p_unit: Unit = null) -> void:
		cell = p_cell
		kind = p_kind
		pips = p_pips
		unit = p_unit


## The board as it stood before the power applied, and the general who fired it.
class Snapshot:
	extends RefCounted

	var team: int
	var commander: CommanderType
	var facts: Dictionary[Unit, PackedInt32Array] = {}
	var cells: Dictionary[Unit, Vector2i] = {}


## Taken by the command pipeline before `PowerCommand.apply`, exactly as it
## already holds the combatants and the acting side's funds.
static func snapshot(state: GameState) -> Snapshot:
	var taken := Snapshot.new()
	taken.team = state.current_team
	taken.commander = state.commander_of(state.current_team)
	for unit in state.units:
		if unit.carrier != null:
			continue
		taken.facts[unit] = _facts(state, taken, unit)
		taken.cells[unit] = unit.cell
	return taken


## Every mark the fired power earned, in board order. An empty blast list is the
## ordinary case: only an aimed power names cells.
static func marks(before: Snapshot, state: GameState, blast: Array[Vector2i]) -> Array[Mark]:
	var found: Array[Mark] = []
	var standing: Dictionary[Unit, bool] = {}
	for unit in state.units:
		standing[unit] = true
	for unit: Unit in before.facts:
		if not standing.has(unit):
			found.append(Mark.new(before.cells[unit], Kind.DESTROYED, 0, unit))
			continue
		var mark := _mark_for(before, state, unit)
		if mark != null:
			found.append(mark)
	for cell in blast:
		if not _holds(found, cell):
			found.append(Mark.new(cell, Kind.DESTROYED))
	if found.is_empty():
		return _army_marks(before, state)
	return found


## A power whose whole effect is a combat number — Vale's attack, Voss's defence,
## Quill's luck — moves no fact on this list, so the board would have nothing to
## show for it. The army it was fired for is the honest answer there: every
## shipped power that changes no unit fact is its own side's.
static func _army_marks(before: Snapshot, state: GameState) -> Array[Mark]:
	var found: Array[Mark] = []
	for unit in state.units_of(before.team):
		if unit.carrier == null:
			found.append(Mark.new(unit.cell, Kind.EMPOWERED, 0, unit))
	return found


static func _mark_for(before: Snapshot, state: GameState, unit: Unit) -> Mark:
	var was := before.facts[unit]
	if _facts(state, before, unit) == was:
		return null
	var pips := unit.displayed_hp() - was[0]
	if pips < 0:
		return Mark.new(unit.cell, Kind.HARMED, -pips, unit)
	if pips > 0:
		return Mark.new(unit.cell, Kind.HEALED, pips, unit)
	if was[1] == 1 and not unit.acted:
		return Mark.new(unit.cell, Kind.REFRESHED, 0, unit)
	if unit.ammo > was[2] or unit.fuel > was[3]:
		return Mark.new(unit.cell, Kind.RESUPPLIED, 0, unit)
	var doctrine := Kind.EMPOWERED if unit.team == before.team else Kind.HINDERED
	return Mark.new(unit.cell, doctrine, 0, unit)


## Every fact a mark is read off: health, whether the unit has acted, and its
## stores, plus whatever the firing doctrine has to say about it.
static func _facts(state: GameState, before: Snapshot, unit: Unit) -> PackedInt32Array:
	var facts := PackedInt32Array([unit.displayed_hp(), 1 if unit.acted else 0])
	facts.append_array(PackedInt32Array([unit.ammo, unit.fuel]))
	facts.append_array(_doctrine_facts(state, before, unit))
	return facts


## What the firing general's doctrine says about `unit` right now — the terms
## that make a movement, sight or capture power visible at all, since none of
## them moves a pip.
##
## Asked of the one authority that owns them: the commander's own hooks for the
## army that fired, the two reach-across-the-table hooks for everyone it is
## hostile to, and nothing at all for an ally, whose doctrine is their own. They
## are compared and never shown, so no gameplay number is recomputed here.
static func _doctrine_facts(state: GameState, before: Snapshot, unit: Unit) -> PackedInt32Array:
	var co := before.commander
	if unit.team == before.team:
		return PackedInt32Array(
			[
				co.move_bonus(state, unit),
				co.vision_bonus(state, unit),
				co.range_bonus(state, unit),
				co.capture_bonus_pct(state, unit),
				1 if co.hides_unit(state, unit) else 0,
				1 if co.sees_into_cover(state, unit) else 0,
			]
		)
	if state.allied(unit.team, before.team):
		return PackedInt32Array()
	return PackedInt32Array(
		[
			co.enemy_move_bonus(state, before.team, unit),
			co.enemy_vision_bonus(state, before.team, unit),
		]
	)


static func _holds(found: Array[Mark], cell: Vector2i) -> bool:
	for mark in found:
		if mark.cell == cell:
			return true
	return false
