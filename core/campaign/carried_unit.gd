class_name CarriedUnit
extends RefCounted
## One unit the war remembers between two missions: what it was, the wounds it
## still carries and the name it was given.
##
## Deliberately not a `Unit`. Nothing survives the gap between two boards except
## condition and identity (campaign-depth D6) — a cell, a fuel tank, a transport
## it was riding in and the turn it had left are all facts about a board that is
## over, and the board it lands on is what makes it a unit again.
##
## What identifies it there is its **type**: `CampaignRoster` fills a carry slot
## with a veteran the board authored the type of, so a name is history rather than
## a key and a unit nobody named carries forward exactly as one that was.

## The `UnitType.id` this was, which is what a carry slot matches on.
var unit_id: StringName = &""
var hp: int = Unit.MAX_HP
## The name the board it fought on gave it, empty for every unit nobody named.
var tag: StringName = &""


func _init(p_unit_id: StringName = &"", p_hp: int = Unit.MAX_HP, p_tag: StringName = &"") -> void:
	unit_id = p_unit_id
	hp = p_hp
	tag = p_tag


static func of(unit: Unit) -> CarriedUnit:
	return CarriedUnit.new(unit.type.id, unit.hp, unit.tag)


## As the campaign profile stores it. Every field always written, like the unit
## list `SaveCodec` writes, so one record has one shape.
func to_dict() -> Dictionary:
	return {"unit": String(unit_id), "hp": hp, "tag": String(tag)}


static func from_dict(data: Dictionary) -> CarriedUnit:
	return CarriedUnit.new(
		StringName(data["unit"]), int(data["hp"]), StringName(data.get("tag", ""))
	)


## Why this dictionary is not a carried unit, or "".
##
## Tolerant of a `unit` no roster ships any more, for the reason a profile
## tolerates a record of a renamed mission: a save that outlives a retired unit
## type should lose that veteran rather than the whole war. It simply matches no
## slot and the board's own unit stands.
static func record_error(record: Variant) -> String:
	if not (record is Dictionary):
		return "'%s' is not a carried unit" % [record]
	var data: Dictionary = record
	if not data.has("unit") or not (data["unit"] is String):
		return "a carried unit that names no type"
	if not String(data["unit"]).is_valid_ascii_identifier():
		return "'%s' is not a unit type" % data["unit"]
	if not data.has("hp"):
		return "carried unit '%s' has no condition" % data["unit"]
	var condition = data["hp"]
	if not (condition is float or condition is int):
		return "carried unit '%s' holds %s, which is no condition" % [data["unit"], condition]
	var carried_hp := int(condition)
	if carried_hp < Unit.MIN_HP or carried_hp > Unit.MAX_HP:
		return "carried unit '%s' holds %d HP" % [data["unit"], carried_hp]
	var carried_tag = data.get("tag", "")
	if not (carried_tag is String):
		return "carried unit '%s' answers to %s, which is no name" % [data["unit"], carried_tag]
	return UnitTag.name_error(StringName(carried_tag))
