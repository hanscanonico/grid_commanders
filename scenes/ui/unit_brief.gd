class_name UnitBrief
extends RefCounted
## The build menu's card for one unit: what it is for, how it moves and shoots,
## what it hits hardest, and — for a greyed row — why it is greyed. Every word is
## read off the roster's data, the damage chart and `AttackRange`; nothing here is
## a stat of its own.

## How many of the hardest-hit targets the card names.
const BEST_COUNT := 3


static func text(
	game: GameState, unit_db: UnitDB, type: UnitType, price: int, funds: int
) -> String:
	var lines := PackedStringArray([type.display_name, type.role, _stats(type)])
	var best := _best_against(game, unit_db, type)
	if not best.is_empty():
		lines.append("Best vs " + ", ".join(best))
	if funds < price:
		lines.append("Not enough funds: %d short" % (price - funds))
	return "\n".join(lines)


static func _stats(type: UnitType) -> String:
	var parts := PackedStringArray(["Move %d" % type.move_points])
	if type.max_range <= 0:
		parts.append("No weapon")
	elif type.min_range == type.max_range:
		parts.append("Range %d" % type.max_range)
	else:
		parts.append("Range %d–%d" % [type.min_range, type.max_range])
	if AttackRange.is_indirect_type(type):
		parts.append("Can't move and fire")
	if type.transport_capacity > 0:
		parts.append("Carries %d" % type.transport_capacity)
	return " · ".join(parts)


## The targets this unit's full-stock shot hurts most, by the chart's base damage,
## the roster's own order breaking a tie.
static func _best_against(game: GameState, unit_db: UnitDB, type: UnitType) -> PackedStringArray:
	var names := PackedStringArray()
	if game.damage_chart == null:
		return names
	var ranked: Array[Array] = []
	var roster := unit_db.all()
	for i in roster.size():
		var damage := game.damage_chart.base_damage(type.id, roster[i].id)
		if damage > 0:
			ranked.append([damage, i])
	ranked.sort_custom(
		func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1])
	)
	for entry in ranked.slice(0, BEST_COUNT):
		names.append(roster[entry[1]].display_name)
	return names
