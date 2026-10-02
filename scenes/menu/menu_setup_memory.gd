class_name MenuSetupMemory
extends RefCounted
## The match the main menu last set up — the board, fog and the seat strip's
## table — kept so a return from a match or the editor, or the next launch, finds
## the setup as it was left (SK-13). `Settings.match_setup` holds it; this class
## words it and reads it back.
##
## A pre-fill and never a launch: the menu still stages its `MatchRequest` from
## what is on screen, so `MatchConfig.take()` stays the one way a request is
## consumed and nothing here can replay a match nobody asked for.

const MAP_KEY := "map"
const FOG_KEY := "fog"
const TABLE_KEY := "table"


## Writes the setup on screen back. Silent before there is a board or a strip to
## read: the menu deals its panel on the way up.
static func remember(map: MapData, fog_on: bool, strip: SeatStrip) -> void:
	if map == null or strip == null:
		return
	Settings.set_match_setup({MAP_KEY: map.source_path, FOG_KEY: fog_on, TABLE_KEY: strip.table()})


## The remembered board's file, or "" when nothing sound is remembered. The
## picker looks it up on its shelf and keeps the board it leads with when the file
## is gone — a deleted user map, a renamed file.
static func map_path(setup: Dictionary) -> String:
	var path: Variant = setup.get(MAP_KEY, "")
	return path if path is String else ""


static func fog(setup: Dictionary) -> bool:
	var stored: Variant = setup.get(FOG_KEY, false)
	return stored if stored is bool else false


## The remembered seating, or an empty table unless its seats and sides are lists
## of whole numbers and its tiers a list — `SeatStrip.seat_table` reads it by
## those shapes.
static func table(setup: Dictionary) -> Dictionary:
	var stored: Variant = setup.get(TABLE_KEY, {})
	if not stored is Dictionary:
		return {}
	var who: Variant = stored.get("who", [])
	var sides: Variant = stored.get("sides", [])
	if not (_whole_numbers(who) and _whole_numbers(sides) and stored.get("tiers", []) is Array):
		return {}
	return stored


static func _whole_numbers(list: Variant) -> bool:
	if not list is Array:
		return false
	for entry: Variant in list:
		if not entry is int:
			return false
	return true
