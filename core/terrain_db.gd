class_name TerrainDB
extends RefCounted
## Registry of all TerrainType resources, indexed by id and by map symbol.

const TERRAIN_DIR := "res://data/terrain"

## The ground a property stands on. The atlas ships its five property columns as
## transparent overlays — the building, its plinth and its shadow, alpha all
## around — so every surface that draws one has to paint this terrain's cell
## underneath it first. Stated once, because the board, the menu thumbnail, the
## tile chip and the legibility composite all have to agree about what is under
## a city. Not a per-cell answer: a map has one terrain per cell and the property
## *is* that terrain, so the ground beneath is the default one everywhere.
const GROUND_ID := &"plains"

var _by_id: Dictionary[StringName, TerrainType] = {}
var _by_symbol: Dictionary[String, TerrainType] = {}


static func load_default() -> TerrainDB:
	var db := TerrainDB.new()
	var dir := DirAccess.open(TERRAIN_DIR)
	if dir == null:
		push_error("TerrainDB: cannot open %s" % TERRAIN_DIR)
		return db
	for file in dir.get_files():
		# Exported builds list .tres files as .tres.remap.
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var terrain: TerrainType = load(TERRAIN_DIR.path_join(name))
		if terrain != null:
			db.register(terrain)
	return db


func register(terrain: TerrainType) -> void:
	if _by_id.has(terrain.id):
		push_error("TerrainDB: duplicate terrain id '%s'" % terrain.id)
		return
	if _by_symbol.has(terrain.symbol):
		push_error("TerrainDB: duplicate terrain symbol '%s'" % terrain.symbol)
		return
	_by_id[terrain.id] = terrain
	_by_symbol[terrain.symbol] = terrain


func by_id(id: StringName) -> TerrainType:
	return _by_id.get(id)


## The terrain GROUND_ID names — the surface a transparent property overlay is
## painted over.
func ground() -> TerrainType:
	return by_id(GROUND_ID)


func by_symbol(symbol: String) -> TerrainType:
	return _by_symbol.get(symbol)


func all() -> Array[TerrainType]:
	var result: Array[TerrainType] = []
	for terrain in _by_id.values():
		result.append(terrain)
	return result


func size() -> int:
	return _by_id.size()
