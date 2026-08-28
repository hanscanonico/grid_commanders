class_name Unit
extends RefCounted
## One unit instance on the battlefield. Pure simulation state.

## Internal HP is 0-100; a dead unit is removed rather than held at zero, so a
## live one's floor is one and its ceiling is full health.
const MAX_HP := 100
const MIN_HP := 1

var type: UnitType
var team: int
var cell: Vector2i
## Internal HP 0-100; the UI shows ceil(hp / 10).
var hp: int = 100
## True once the unit has used its action this turn.
var acted: bool = false
## True when the action that exhausted this unit was its own — a walk, a shot, a
## capture. A fresh build and a unit somebody else set down or merged into are
## exhausted by another unit's action and stay false. Kept separate from acted so
## a refresh power remains exact across a mid-turn save.
var refreshable: bool = false
## Remaining fuel; movement spends it point-for-point with terrain cost.
var fuel: int = 99
## Remaining primary ammo; only meaningful when type.max_ammo > 0.
var ammo: int = 0
## The transport carrying this unit, or null when on the board. Carried units
## are invisible to cell lookups and can neither act nor be targeted.
var carrier: Unit = null
## Submerged (subs only). A dived unit is hidden from enemies that are not
## standing next to it — with or without fog, unlike everything else the fog
## rules hide — and only a weapon that reaches under the surface can touch it.
## It still occupies its cell, and a movement fill plans through it exactly as
## it does any other unit the mover cannot see: the cell fills and offers
## itself as a stopping place. `GameState.advance_unit` springs the Advance
## Wars trap on contact, halting the mover at the last free cell before it.
## Same rule with fog on or off — `Vision.is_hidden_from` checks dive ahead of
## the fog gate.
var dived: bool = false
## The name the board gave this unit, empty for every unit nobody named — the
## optional fifth column of a map's [units] row, carried in the save. It is what
## lets a campaign mission say "destroy Draeg's siege gun" about a unit that
## moves. Inert data (campaign-depth plan D4): nothing in core/rules/, in ai/ or
## in the damage chart reads it, so a named unit fights and is planned against
## exactly like an unnamed one.
var tag: StringName = &""


static func create(p_type: UnitType, p_team: int, p_cell: Vector2i) -> Unit:
	var unit := Unit.new()
	unit.type = p_type
	unit.team = p_team
	unit.cell = p_cell
	unit.fuel = p_type.max_fuel
	unit.ammo = p_type.max_ammo
	return unit


## `unit -> index` in the list, built once by a caller that would otherwise
## re-scan for every one of the n units it writes — the same shape
## MovementResolver._occupants is waived for (CLAUDE.md). Both codecs read a
## carrier through it, and a unit with no carrier is simply absent as a key, so
## each caller's own `get` fallback stands in for `Array.find`'s -1.
static func indices_of(units: Array[Unit]) -> Dictionary[Unit, int]:
	var indices: Dictionary[Unit, int] = {}
	for i in units.size():
		indices[units[i]] = i
	return indices


func displayed_hp() -> int:
	return ceili(hp / 10.0)


## True when the unit has under `margin_turns` worth of fuel left: it can no
## longer both fly a full move and pay that many days of upkeep. Always false for
## anything an empty tank merely strands — a tank out of fuel is parked, not
## doomed, so warning about it would be noise.
##
## The single definition of "running dry". The board's warning badge, the tile
## panel and the AI's decision to break off and refuel all ask this one question,
## which is what stops the interface flagging a unit the planner is happy with,
## or the reverse.
func running_dry(margin_turns: int = 1) -> bool:
	return _running_dry(upkeep(), margin_turns)


## The same question about a boat that is still on the surface: would going under
## leave it running dry? Diving costs several times the surface rate, so a
## submarine weighing the hatch has to ask about the tank it will be paying from
## rather than the one it is paying from now.
func running_dry_if_dived(margin_turns: int = 1) -> bool:
	return _running_dry(type.dived_fuel_upkeep, margin_turns)


func _running_dry(burn: int, margin_turns: int) -> bool:
	if not type.lost_when_dry() or margin_turns <= 0:
		return false
	return fuel <= (burn + type.move_points) * margin_turns


## Fuel this unit burns at the start of its turn. Staying under costs a submarine
## several times what running on the surface does, which is the clock the whole
## dive mechanic is played against: hiding is free of risk and expensive in fuel.
func upkeep() -> int:
	return type.dived_fuel_upkeep if dived else type.fuel_upkeep


func resupply() -> void:
	fuel = type.max_fuel
	ammo = type.max_ammo
