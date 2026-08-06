class_name DamageChart
extends Resource
## Primary and secondary damage matrices: attacker unit id -> (defender unit id
## -> base damage %). A missing entry means that weapon cannot damage the
## defender.

const PRIMARY := &"primary"
const SECONDARY := &"secondary"


class Shot:
	var slot: StringName
	var base_damage: int
	var consumes_primary_ammo: bool

	func _init(p_slot: StringName, p_base_damage: int, p_consumes_primary_ammo: bool) -> void:
		slot = p_slot
		base_damage = p_base_damage
		consumes_primary_ammo = p_consumes_primary_ammo


@export var chart: Dictionary[StringName, Dictionary] = {}
@export var secondary_chart: Dictionary[StringName, Dictionary] = {}


## Full-stock lookup used by production scoring: primary first, then secondary.
func base_damage(attacker: StringName, defender: StringName) -> int:
	var primary := _cell(chart, attacker, defender)
	if primary >= 0:
		return primary
	return _cell(secondary_chart, attacker, defender)


## One cell of a matrix: the base damage `attacker` does `defender`, or -1 when
## that weapon does not cover it. The one reader of either matrix's values, so
## that a chart is held to whole numbers in one place — read straight into an
## `int`, a cell authored 55.9 became 55 and silently rebalanced a matchup every
## commander was tested against. Declaring the dictionaries typed does not catch
## it: their values are Variants either way, and a typed one coerces as quietly.
## Refused rather than rounded, because a cell nobody meant to write is not a
## number to guess at.
static func _cell(matrix: Dictionary, attacker: StringName, defender: StringName) -> int:
	var row: Dictionary = matrix.get(attacker, {})
	var value: Variant = row.get(defender, -1)
	if typeof(value) != TYPE_INT:
		push_error(
			"DamageChart: %s vs %s is %s, which is not a whole number" % [attacker, defender, value]
		)
		return -1
	return value


func can_attack(attacker: StringName, defender: StringName) -> bool:
	return base_damage(attacker, defender) >= 0


## Selects the ready weapon for one target. Preferred-secondary matchups exist
## only in secondary_chart; overlapping vehicle rows therefore use a stocked
## primary first and fall back to the infinite secondary when it is dry.
func select_shot(
	attacker: StringName, defender: StringName, primary_ammo: int, primary_ammo_capacity: int
) -> Shot:
	var primary_damage := _cell(chart, attacker, defender)
	var primary_ready := primary_ammo_capacity == 0 or primary_ammo > 0
	if primary_damage >= 0 and primary_ready:
		return Shot.new(PRIMARY, primary_damage, primary_ammo_capacity > 0)
	var secondary_damage := _cell(secondary_chart, attacker, defender)
	if secondary_damage >= 0:
		return Shot.new(SECONDARY, secondary_damage, false)
	return null


## Whether this attacker owns a secondary weapon at all. The authority on that
## question: a secondary is a row in this chart, and the presentation key on
## UnitType only names how an already-selected one looks.
func has_secondary(attacker: StringName) -> bool:
	var row: Dictionary = secondary_chart.get(attacker, {})
	return not row.is_empty()


## Whether this attacker has any weapon it could fire now, target aside. Used
## only to avoid drawing an entirely inert unit into a threat-map flood fill;
## target-specific legality still goes through select_shot().
func has_ready_weapon(attacker: StringName, primary_ammo: int, primary_ammo_capacity: int) -> bool:
	var primary_ready := primary_ammo_capacity == 0 or primary_ammo > 0
	var primary_row: Dictionary = chart.get(attacker, {})
	if primary_ready and not primary_row.is_empty():
		return true
	var secondary_row: Dictionary = secondary_chart.get(attacker, {})
	return not secondary_row.is_empty()
