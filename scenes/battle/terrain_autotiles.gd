class_name TerrainAutotiles
extends RefCounted
## The one authority for which autotile family a terrain cell draws from and
## which connection-mask variant of that family it wears. BattleView indexes
## exactly what these statics return and does no neighbour reasoning of its
## own, so the board's connected look has a single opinion.
##
## Pure reads over MapData and Node-free, like PathArrow.segments, so the
## suite checks every mask without a scene.
##
## The sheets are sprite_generator's autotile contract (spritegen/autotile.py):
## 16 variants row-major on a 4x4 grid indexed by connection bits N=1 E=2 S=4
## W=8, and the bridge sheet's two cells are the E-W deck then the N-S deck.
## Mask 0 on the road and river sheets is their E-W fallback bar; the coast
## sheet's mask 0 is plain open sea, which is why open water stays on the base
## atlas (Family.NONE) exactly as the generator's own demo composes it.
##
## An off-board neighbour counts as the cell's own terrain, so the board rim
## grows no shoreline and an edge road runs off the map the way the darkened
## backdrop's continuation implies.

## NONE doubles as BattleView's base-atlas source id (0); the other values are
## the TileSet source ids the sheets are registered under.
enum Family { NONE, ROADS, RIVERS, COAST, SHOALS, BRIDGES }

const BIT_N := 1
const BIT_E := 2
const BIT_S := 4
const BIT_W := 8

## What a road reads as continuing into.
const _ROAD_JOINS: Array[StringName] = [&"road", &"bridge"]
## What a river reads as flowing into.
const _RIVER_JOINS: Array[StringName] = [&"river", &"bridge", &"sea", &"port"]
## What the sea reads as open water — a coast edge is any neighbour outside
## this set. Shoals are water here: they carry their own surf, so the sea draws
## no second shoreline against them (the generator demo's rule).
const _SEA_WATER: Array[StringName] = [&"sea", &"river", &"reef", &"shoal", &"bridge", &"port"]
## What a shoal surfs against: the same water minus shoal itself, so a run of
## beach breaks no surf on its own sand (the generator demo's _WATERY).
const _SHOAL_WATER: Array[StringName] = [&"sea", &"river", &"reef", &"bridge", &"port"]

const _STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const _STEP_BITS: Array[int] = [BIT_N, BIT_E, BIT_S, BIT_W]


## Which sheet `cell` draws from; NONE keeps the base atlas tile.
static func family(map: MapData, cell: Vector2i) -> Family:
	match map.terrain_at(cell).id:
		&"road":
			return Family.ROADS
		&"river":
			return Family.RIVERS
		&"bridge":
			return Family.BRIDGES
		&"shoal":
			return Family.SHOALS
		&"sea":
			# Open water keeps the base tile; only a sea cell with land on an
			# edge draws from the coast sheet.
			return Family.COAST if mask(map, cell) != 0 else Family.NONE
	return Family.NONE


## The connection mask `cell` wears on its family's sheet. For a bridge the
## mask is its deck orientation: E|W beside a road or another bridge, N|S
## otherwise.
static func mask(map: MapData, cell: Vector2i) -> int:
	match map.terrain_at(cell).id:
		&"road":
			return _joins_mask(map, cell, _ROAD_JOINS)
		&"river":
			return _joins_mask(map, cell, _RIVER_JOINS)
		&"bridge":
			var road_side := _joins_mask(map, cell, _ROAD_JOINS)
			return (BIT_E | BIT_W) if road_side & (BIT_E | BIT_W) != 0 else (BIT_N | BIT_S)
		&"sea":
			return _land_mask(map, cell)
		&"shoal":
			return _joins_mask(map, cell, _SHOAL_WATER)
	return 0


## Where mask `p_mask` sits on family `p_family`'s sheet: variant m at grid
## (m % 4, m / 4), except the two-cell bridge sheet.
static func atlas_coords(p_family: int, p_mask: int) -> Vector2i:
	if p_family == Family.BRIDGES:
		return Vector2i(0 if p_mask & BIT_E != 0 else 1, 0)
	return Vector2i(p_mask & 3, p_mask >> 2)


static func _joins_mask(map: MapData, cell: Vector2i, joins: Array[StringName]) -> int:
	var bits := 0
	for i in _STEPS.size():
		if joins.has(_neighbour_id(map, cell, _STEPS[i])):
			bits |= _STEP_BITS[i]
	return bits


## The sea's mask counts the opposite way: a bit per edge whose neighbour is
## land, meaning anything outside the water set.
static func _land_mask(map: MapData, cell: Vector2i) -> int:
	var bits := 0
	for i in _STEPS.size():
		if not _SEA_WATER.has(_neighbour_id(map, cell, _STEPS[i])):
			bits |= _STEP_BITS[i]
	return bits


static func _neighbour_id(map: MapData, cell: Vector2i, step: Vector2i) -> StringName:
	var neighbour := cell + step
	if not map.in_bounds(neighbour):
		return map.terrain_at(cell).id
	return map.terrain_at(neighbour).id
