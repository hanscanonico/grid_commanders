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


@export var chart: Dictionary = {}
@export var secondary_chart: Dictionary = {}


## Full-stock lookup used by production scoring: primary first, then secondary.
func base_damage(attacker: StringName, defender: StringName) -> int:
	var row: Dictionary = chart.get(attacker, {})
	var primary: int = row.get(defender, -1)
	if primary >= 0:
		return primary
	var secondary_row: Dictionary = secondary_chart.get(attacker, {})
	return secondary_row.get(defender, -1)


func can_attack(attacker: StringName, defender: StringName) -> bool:
	return base_damage(attacker, defender) >= 0


## Selects the ready weapon for one target. Preferred-secondary matchups exist
## only in secondary_chart; overlapping vehicle rows therefore use a stocked
## primary first and fall back to the infinite secondary when it is dry.
func select_shot(
	attacker: StringName, defender: StringName, primary_ammo: int, primary_ammo_capacity: int
) -> Shot:
	var primary_row: Dictionary = chart.get(attacker, {})
	var primary_damage: int = primary_row.get(defender, -1)
	var primary_ready := primary_ammo_capacity == 0 or primary_ammo > 0
	if primary_damage >= 0 and primary_ready:
		return Shot.new(PRIMARY, primary_damage, primary_ammo_capacity > 0)
	var secondary_row: Dictionary = secondary_chart.get(attacker, {})
	var secondary_damage: int = secondary_row.get(defender, -1)
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
