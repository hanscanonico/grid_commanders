extends SceneTree
## Prints the search's whole input as one JSON object, and plays nothing.
##
## The blocks and their lattices are `ArenaBlocks`', the boards, seeds and anchors
## are `ArenaPools`', and the vector a search starts from is read off the base
## profile. `tools/arena_search.py` derives none of them: a driver that restated
## a range or a seed range would be a second opinion about the search space, and
## the first thing to drift.
##
## Usage (headless; the search driver runs this itself):
##   Godot --headless --path . -s res://tools/run_arena_blocks.gd -- [flags]
##     --base=data/ai/default.tres   the profile the vector is read from
##
## The engine prints a banner of its own first, so a caller takes the line that
## parses as JSON.

const DEFAULT_BASE := "data/ai/default.tres"


func _init() -> void:
	var base := DEFAULT_BASE
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--base="):
			base = arg.get_slice("=", 1).strip_edges()
		else:
			push_error("arena-blocks: unknown flag '%s'" % arg)
			quit(2)
			return
	var profile := _profile(base)
	if profile == null:
		quit(2)
		return
	print(JSON.stringify(_plan(base, profile)))
	quit(0)


func _profile(base: String) -> AIProfile:
	var path := ArenaRequest.project_path(base)
	if path == "" or not ResourceLoader.exists(path):
		push_error("arena-blocks: no profile at '%s'" % base)
		return null
	var loaded: Resource = load(path)
	if not (loaded is AIProfile):
		push_error("arena-blocks: '%s' is not an AIProfile" % base)
		return null
	var profile: AIProfile = loaded
	return profile


func _plan(base: String, profile: AIProfile) -> Dictionary:
	return {
		"base": base,
		"days": ArenaPools.DAYS,
		"anchors": ArenaPools.ANCHORS,
		"pools": _pools(),
		"dials": _dials(),
		"blocks": _blocks(),
		"vector": _vector(profile),
		"excluded": ArenaBlocks.EXCLUDED,
	}


func _pools() -> Dictionary:
	var listed: Dictionary = {}
	for pool: String in ArenaPools.POOLS:
		listed[pool] = {
			"boards": ArenaPools.boards(pool),
			"seeds": ArenaPools.seeds(pool),
			"seed_offset": ArenaPools.seed_offset(pool),
		}
	return listed


## Every dial with its lattice, plus the one fact the table asks `AIProfile` for
## rather than declaring: whether the field is an integer.
func _dials() -> Dictionary:
	var listed: Dictionary = {}
	for field: StringName in ArenaBlocks.DIALS:
		var dial: Dictionary = ArenaBlocks.dial(field).duplicate()
		dial["int"] = ArenaBlocks.integer(field)
		listed[String(field)] = dial
	return listed


func _blocks() -> Array:
	var listed: Array = []
	for entry: Dictionary in ArenaBlocks.BLOCKS:
		var name := String(entry["name"])
		var couples: Dictionary = {}
		var declared: Dictionary = entry["couples"]
		for field: StringName in declared:
			couples[String(field)] = declared[field]
		var block := {
			"name": name,
			"fields": _strings(ArenaBlocks.fields_of(name)),
			"couples": couples,
			"per_board": bool(entry.get("per_board", false)),
			"note": String(entry["note"]),
		}
		listed.append(block)
	return listed


func _vector(profile: AIProfile) -> Dictionary:
	var listed: Dictionary = {}
	for field: StringName in ArenaBlocks.DIALS:
		listed[String(field)] = profile.get(field)
	return listed


static func _strings(fields: Array[StringName]) -> Array[String]:
	var listed: Array[String] = []
	for field in fields:
		listed.append(String(field))
	return listed
