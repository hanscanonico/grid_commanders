class_name TerrainAutotiles
extends RefCounted
## The one authority for which autotile family a terrain cell draws from and
## which variant of that family it wears. BattleView, its out-of-bounds
## backdrop, MapThumbnail and the legibility harness all index exactly what
## these statics return and do no neighbour reasoning of their own, so the
## board, the field behind the menu, the miniature in front of it and the
## instrument that measures them have a single opinion.
##
## Pure reads over MapData and Node-free, like PathArrow.segments, so the
## suite checks every mask without a scene.
##
## The sheets are sprite_generator's autotile contract (spritegen/autotile.py):
## 16 variants row-major on a 4x4 grid indexed by connection bits N=1 E=2 S=4
## W=8, and the bridge sheet's two cells are the E-W deck then the N-S deck.
## Mask 0 on the road and river sheets is their E-W fallback bar; the coast
## sheet's mask 0 is plain open sea, which is why a coasted cell only ever
## wears a mask with land in it. The woods sheet's mask 15 is the base tile:
## a wood with wood on every side keeps the full-bleed canopy that lets a
## forest butt seamlessly, and only a wood's fringe leaves the atlas for a
## scalloped tree line.
##
## The sea sheet is the one family that is not a connection set: the same open
## water in SEA_PHASES phases, and what a field of it repeats at is the tile
## rather than anything inside it, so a single tile reads row-aligned however
## its glints are spread. The generator emits the phases and the game places
## them (spritegen README), which is `sea_phase` — a hash of the cell, so the
## lattice is broken deterministically and the board, the backdrop, the
## miniature and the harness all break it the same way. Phase 0 is the terrain
## atlas's sea column byte for byte.
##
## Every board read is clamped to the edge, which states one rule twice over:
## an off-board neighbour counts as the cell's own terrain, so the board rim
## grows no shoreline and an edge road runs off the map — and an off-board
## *cell* reads as the nearest edge terrain, which is exactly what the darkened
## backdrop paints there, so the ring is autotiled by the same arithmetic as
## the rim it continues.

## NONE doubles as BattleView's base-atlas source id (0); the other values are
## the TileSet source ids the sheets are registered under.
enum Family { NONE, ROADS, RIVERS, COAST, SHOALS, WOODS, BRIDGES, SEA }

## One generated sheet per family, the single naming of the files. BattleView
## registers a TileSet source per entry and MapThumbnail blits from the same
## images, so neither can point at art the other does not have.
const SHEET_PATHS: Dictionary[int, String] = {
	Family.ROADS: "res://assets/tiles/autotiles/roads.png",
	Family.RIVERS: "res://assets/tiles/autotiles/rivers.png",
	Family.COAST: "res://assets/tiles/autotiles/coast.png",
	Family.SHOALS: "res://assets/tiles/autotiles/shoals.png",
	Family.WOODS: "res://assets/tiles/autotiles/woods.png",
	Family.BRIDGES: "res://assets/tiles/autotiles/bridges.png",
	Family.SEA: "res://assets/tiles/autotiles/sea.png",
}

## How many cells each family's sheet holds: a connection set's 16 masks, the
## bridge sheet's two decks, the sea sheet's phases.
const CONNECTION_VARIANTS := 16
const BRIDGE_VARIANTS := 2
const SEA_PHASES := 3

## The contact sheets' cut: a 2px outer margin, 2px between cells, TERRAIN_PX
## cells — sprite_generator's contract, which BattleView registers a TileSet
## source with and MapThumbnail reads regions out of by hand.
const SHEET_MARGIN := 2
const SHEET_SEPARATION := 2

const BIT_N := 1
const BIT_E := 2
const BIT_S := 4
const BIT_W := 8
const _ALL_EDGES := BIT_N | BIT_E | BIT_S | BIT_W

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
## What a wood's canopy runs on into. Only more wood: everything else is ground
## the tree line has to end against.
const _WOODS_JOINS: Array[StringName] = [&"woods"]

const _STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const _STEP_BITS: Array[int] = [BIT_N, BIT_E, BIT_S, BIT_W]


## Which sheet `cell` draws from; NONE keeps the base atlas tile.
static func family(map: MapData, cell: Vector2i) -> Family:
	match terrain_id(map, cell):
		&"road":
			return Family.ROADS
		&"river":
			return Family.RIVERS
		&"bridge":
			return Family.BRIDGES
		&"shoal":
			return Family.SHOALS
		&"sea":
			# A sea cell with land on an edge draws its shoreline from the coast
			# sheet; open water draws a phase of the sea sheet.
			return Family.COAST if mask(map, cell) != 0 else Family.SEA
		&"woods":
			# A wood walled in by wood keeps the base tile; only a fringe cell
			# draws its tree line from the woods sheet.
			return Family.NONE if mask(map, cell) == _ALL_EDGES else Family.WOODS
	return Family.NONE


## The connection mask `cell` wears on its family's sheet. For a bridge the
## mask is its deck orientation: E|W beside a road or another bridge, N|S
## otherwise.
static func mask(map: MapData, cell: Vector2i) -> int:
	match terrain_id(map, cell):
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
		&"woods":
			return _joins_mask(map, cell, _WOODS_JOINS)
	return 0


## Which cell of its family's sheet `cell` wears — the one call the painters
## make, so no surface has to know which families are keyed by connection and
## which by phase.
static func variant(map: MapData, cell: Vector2i) -> int:
	if family(map, cell) == Family.SEA:
		return sea_phase(cell)
	return mask(map, cell)


## The phase open water at `cell` draws. A hash of the coordinate rather than a
## seeded draw: the same cell is the same phase in every process, and nothing
## has to store which tile went where.
static func sea_phase(cell: Vector2i) -> int:
	var hash_bits := (cell.x * 0x9E3779B1) ^ (cell.y * 0x85EBCA77)
	hash_bits = (hash_bits ^ (hash_bits >> 13)) * 0xC2B2AE3D
	return posmod(hash_bits >> 17, SEA_PHASES)


## Every cell family `p_family`'s sheet holds, which is what BattleView
## registers a tile for. Stated here rather than counted by the caller, because
## a bridge's variant is a mask and a phase is an index, and only this file may
## know which sheet is which.
static func sheet_cells(p_family: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	match p_family:
		Family.BRIDGES:
			for deck in BRIDGE_VARIANTS:
				cells.append(Vector2i(deck, 0))
		Family.SEA:
			for phase in SEA_PHASES:
				cells.append(atlas_coords(p_family, phase))
		_:
			for connection in CONNECTION_VARIANTS:
				cells.append(atlas_coords(p_family, connection))
	return cells


## Where variant `p_variant` sits on family `p_family`'s sheet: connection mask
## m at grid (m % 4, m / 4), a phase or a deck along the sheet's one row.
static func atlas_coords(p_family: int, p_variant: int) -> Vector2i:
	if p_family == Family.BRIDGES:
		return Vector2i(0 if p_variant & BIT_E != 0 else 1, 0)
	if p_family == Family.SEA:
		return Vector2i(p_variant, 0)
	return Vector2i(p_variant & 3, p_variant >> 2)


## The terrain `cell` reads as, clamped to the board — the one place the rim
## rule is stated, and what lets the backdrop's ring be asked about at all.
static func terrain_id(map: MapData, cell: Vector2i) -> StringName:
	var clamped := Vector2i(clampi(cell.x, 0, map.width - 1), clampi(cell.y, 0, map.height - 1))
	return map.terrain_at(clamped).id


static func _joins_mask(map: MapData, cell: Vector2i, joins: Array[StringName]) -> int:
	var bits := 0
	for i in _STEPS.size():
		if joins.has(terrain_id(map, cell + _STEPS[i])):
			bits |= _STEP_BITS[i]
	return bits


## The sea's mask counts the opposite way: a bit per edge whose neighbour is
## land, meaning anything outside the water set.
static func _land_mask(map: MapData, cell: Vector2i) -> int:
	var bits := 0
	for i in _STEPS.size():
		if not _SEA_WATER.has(terrain_id(map, cell + _STEPS[i])):
			bits |= _STEP_BITS[i]
	return bits
