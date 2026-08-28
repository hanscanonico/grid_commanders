class_name CommanderDB
extends RefCounted
## Registry of all CommanderType resources, indexed by id. Mirrors UnitDB.
##
## The neutral commander is not a file: it is CommanderType's own defaults, and
## it is always present under `CommanderType.NEUTRAL_ID` so the CO picker and a
## save that names no commander both resolve through the same lookup.

const COMMANDER_DIR := "res://data/commanders"

var _by_id: Dictionary[StringName, CommanderType] = {}


static func load_default() -> CommanderDB:
	var db := CommanderDB.new()
	db.register(CommanderType.neutral())
	for path in ResourceDir.files(COMMANDER_DIR, ".tres", "CommanderDB"):
		var commander: CommanderType = load(path)
		if commander != null:
			db.register(commander)
	return db


func register(commander: CommanderType) -> void:
	if _by_id.has(commander.id):
		push_error("CommanderDB: duplicate commander id '%s'" % commander.id)
		return
	_by_id[commander.id] = commander


## Never null: an unknown id falls back to the neutral commander, so a save that
## names a general who has since been removed still loads and plays.
func by_id(id: StringName) -> CommanderType:
	# The fallback is built only when it is needed: a default argument is evaluated
	# on every call, and `neutral()` now hands back a fresh commander each time.
	var found: CommanderType = _by_id.get(id)
	return found if found != null else CommanderType.neutral()


func has(id: StringName) -> bool:
	return _by_id.has(id)


## A commander a side can be measured *as*. "No commander" is a legal seat and a
## legal pick, but it is the absence of a doctrine rather than one of them, so a
## roster measurement is over these — ask here rather than spelling the neutral
## exclusion out at each site.
func is_playable(id: StringName) -> bool:
	return has(id) and id != CommanderType.NEUTRAL_ID


## Every playable commander, in `all()`'s order.
func playable() -> Array[CommanderType]:
	var result: Array[CommanderType] = []
	for commander in all():
		if is_playable(commander.id):
			result.append(commander)
	return result


## Every commander, neutral first and the rest grouped by faction then name —
## the order the CO picker shows them in.
func all() -> Array[CommanderType]:
	var result: Array[CommanderType] = []
	for commander: CommanderType in _by_id.values():
		result.append(commander)
	result.sort_custom(
		func(a: CommanderType, b: CommanderType) -> bool:
			if a.faction != b.faction:
				return a.faction < b.faction
			return a.display_name < b.display_name
	)
	return result


func size() -> int:
	return _by_id.size()
