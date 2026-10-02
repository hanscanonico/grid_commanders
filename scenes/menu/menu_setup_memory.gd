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


## Where the remembered board sits on the shelf, or -1 when nothing is remembered
## or the board is gone — a deleted user map, a renamed file — so the picker keeps
## the board it leads with.
static func map_index(setup: Dictionary, maps: Array[MapData]) -> int:
	var path: Variant = setup.get(MAP_KEY, "")
	if not path is String or path == "":
		return -1
	for i in maps.size():
		if maps[i].source_path == path:
			return i
	return -1


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
