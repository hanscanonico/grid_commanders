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
## W=8, and the bridge sheet holds a row per `BridgeBed`, each the E-W
## deck then the N-S deck.
## Mask 0 on the road and river sheets is their E-W fallback bar; the coast
## sheet's mask 0 is plain open sea, which is why a coasted cell only ever
## wears a mask with land in it. The woods sheet's mask 15 is the base tile:
## a wood with wood on every side keeps the full-bleed canopy that lets a
## forest butt seamlessly, and only a wood's fringe leaves the atlas for a
## scalloped tree line.
##
## The sea, plains and mountain sheets are the families that are not connection
## sets: the same open water, the same field and the same massif in phases,
## because what a stretch of one repeats at is the tile rather than anything
## inside it, so a single tile reads row-aligned however its glints, its tufts or
## its peaks are spread. The generator emits the phases and the game places them
## (spritegen README), which is `phase` — a hash of the cell, so the lattice is
## broken deterministically and the board, the backdrop, the miniature and the
## harness all break it the same way. Phase 0 of each is that terrain's atlas
## column byte for byte.
##
## Every board read is clamped to the edge, which states one rule twice over:
## an off-board neighbour counts as the cell's own terrain, so the board rim
## grows no shoreline and an edge road runs off the map — and an off-board
## *cell* reads as the nearest edge terrain, which is exactly what the darkened
## backdrop paints there, so the ring is autotiled by the same arithmetic as
## the rim it continues.

## NONE doubles as BattleView's base-atlas source id (0); the other values are
## the TileSet source ids the sheets are registered under.
enum Family { NONE, ROADS, RIVERS, COAST, SHOALS, WOODS, BRIDGES, SEA, PLAINS, MOUNTAIN }

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
	Family.PLAINS: "res://assets/tiles/autotiles/plains.png",
	Family.MOUNTAIN: "res://assets/tiles/autotiles/mountain.png",
}

## Every animated family's second time frame: the same cut and the same
## indexing as `SHEET_PATHS`' own file, with only the glint or foam pixels
## moved — the sea was the first of these, rivers and shoals joined it at the
## same idiom (S9). `sheet_path` is the only place a frame-B file is named,
## so a family with no entry here just keeps answering its one sheet.
const FRAME_B_PATHS: Dictionary[int, String] = {
	Family.SEA: "res://assets/tiles/autotiles/sea_b.png",
	Family.RIVERS: "res://assets/tiles/autotiles/rivers_b.png",
	Family.SHOALS: "res://assets/tiles/autotiles/shoals_b.png",
}

## How many cells each family's sheet holds: a connection set's 16 masks, the
## bridge sheet's two decks over each of its beds, the phases of the phase-keyed
## sheets.
const CONNECTION_VARIANTS := 16
const BRIDGE_DECKS := 2
const SEA_PHASES := 3
const PLAINS_PHASES := 8
const MOUNTAIN_PHASES := 3

## Which families are keyed by where the cell is rather than by what surrounds
## it, and how many phases each of their sheets holds. Stated once so `variant`,
## `sheet_cells` and `atlas_coords` cannot disagree about which is which.
const PHASE_COUNTS: Dictionary[int, int] = {
	Family.SEA: SEA_PHASES,
	Family.PLAINS: PLAINS_PHASES,
	Family.MOUNTAIN: MOUNTAIN_PHASES,
}

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
# A port is in none of the three sets below: the board paints its cell as
# `TerrainDB.ground()` — plains — under a transparent building, and counted as
# water it left the sea running seamlessly into a quay standing on grass.
# These sets are the board's authority. The sprite generator's demo preview
# (`generators/sprites/spritegen/demo.py`) still holds `port` in its `_WATERY`,
# so the two diverge by exactly that id; syncing the demo is a follow-up, not a
# reason to put `port` back here.
## What a river reads as flowing into.
const _RIVER_JOINS: Array[StringName] = [&"river", &"bridge", &"sea"]
## What the sea reads as open water — a coast edge is any neighbour outside
## this set. Shoals are water here: they carry their own surf, so the sea draws
## no second shoreline against them.
const _SEA_WATER: Array[StringName] = [&"sea", &"river", &"reef", &"shoal", &"bridge"]
## What a shoal surfs against: the same water minus shoal itself, so a run of
## beach breaks no surf on its own sand.
const _SHOAL_WATER: Array[StringName] = [&"sea", &"river", &"reef", &"bridge"]
## What a wood's canopy runs on into. Only more wood: everything else is ground
## the tree line has to end against.
const _WOODS_JOINS: Array[StringName] = [&"woods"]

## What a bridge stands over, its sheet's row: the river every deck was first
## drawn across, open sea, and dry ground for a deck no water meets — a lone
## bridge on a field drew a river's stubs into the grass (playtest ED-21).
enum BridgeBed { RIVER, SEA, DRY }
## A bridge's variant carries its bed above the four deck bits.
const _BED_SHIFT := 4
## What reads as sea under a deck: the open water a causeway crosses.
const _SEA_BEDS: Array[StringName] = [&"sea", &"reef", &"shoal"]

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
		&"plains":
			return Family.PLAINS
		&"mountain":
			return Family.MOUNTAIN
	return Family.NONE


## The connection mask `cell` wears on its family's sheet. For a bridge the
## mask is its deck orientation — see `_deck_mask`.
static func mask(map: MapData, cell: Vector2i) -> int:
	match terrain_id(map, cell):
		&"road":
			return _joins_mask(map, cell, _ROAD_JOINS)
		&"river":
			return _joins_mask(map, cell, _RIVER_JOINS)
		&"bridge":
			return _deck_mask(map, cell)
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
	var p_family := family(map, cell)
	if PHASE_COUNTS.has(p_family):
		return phase(cell, PHASE_COUNTS[p_family])
	if p_family == Family.BRIDGES:
		return mask(map, cell) | (bridge_bed(map, cell) << _BED_SHIFT)
	return mask(map, cell)


## What the bridge at `cell` stands over: the sea when any cell around it is
## open water, else a river when one is, else dry ground when other land meets
## it. A deck that meets only bridges and road — the middle of a wide causeway —
## takes the bed of the nearest bridge in its run that does meet something, and a
## run of nothing but bridges keeps the river deck.
static func bridge_bed(map: MapData, cell: Vector2i) -> BridgeBed:
	var seen: Dictionary[Vector2i, bool] = {cell: true}
	var ring: Array[Vector2i] = [cell]
	var met_ground := false
	while not ring.is_empty():
		var beds: Array[int] = []
		var next: Array[Vector2i] = []
		for at in ring:
			for step in _STEPS:
				var near := at + step
				if not map.in_bounds(near):
					continue
				var id := terrain_id(map, near)
				if id != &"bridge":
					met_ground = true
					beds.append(_bed_beside(id))
				elif not seen.has(near):
					seen[near] = true
					next.append(near)
		for bed: int in [BridgeBed.SEA, BridgeBed.RIVER, BridgeBed.DRY]:
			if beds.has(bed):
				return bed as BridgeBed
		ring = next
	return BridgeBed.DRY if met_ground else BridgeBed.RIVER


## The bed one non-bridge neighbour asks for; -1 for road, which a deck lands on
## over any bed and so says nothing about it.
static func _bed_beside(id: StringName) -> int:
	if _SEA_BEDS.has(id):
		return BridgeBed.SEA
	if id == &"river":
		return BridgeBed.RIVER
	return -1 if id == &"road" else BridgeBed.DRY


## A deck runs along the axis whose straight run of bridges lands on road at more
## of its ends, so a block of bridges spans the crossing rather than across it. A
## tie — a lone deck, or one with no road in line — runs E-W beside a road or
## bridge east or west and N-S otherwise.
static func _deck_mask(map: MapData, cell: Vector2i) -> int:
	var across := _road_ends(map, cell, Vector2i.RIGHT)
	var along := _road_ends(map, cell, Vector2i.DOWN)
	if across != along:
		return (BIT_E | BIT_W) if across > along else (BIT_N | BIT_S)
	var road_side := _joins_mask(map, cell, _ROAD_JOINS)
	return (BIT_E | BIT_W) if road_side & (BIT_E | BIT_W) != 0 else (BIT_N | BIT_S)


## How many ends of the straight bridge run through `cell` along `axis` meet road.
static func _road_ends(map: MapData, cell: Vector2i, axis: Vector2i) -> int:
	var ends := 0
	for step: Vector2i in [axis, -axis]:
		var at := cell + step
		while map.in_bounds(at) and terrain_id(map, at) == &"bridge":
			at += step
		if map.in_bounds(at) and terrain_id(map, at) == &"road":
			ends += 1
	return ends


## Which of a phase-keyed family's `count` phases `cell` draws. A hash of the
## coordinate rather than a seeded draw: the same cell is the same phase in every
## process, and nothing has to store which tile went where.
static func phase(cell: Vector2i, count: int) -> int:
	var hash_bits := (cell.x * 0x9E3779B1) ^ (cell.y * 0x85EBCA77)
	hash_bits = (hash_bits ^ (hash_bits >> 13)) * 0xC2B2AE3D
	return posmod(hash_bits >> 17, count)


## Which file family `p_family` draws frame `p_frame` of. Frame 0 is the
## `SHEET_PATHS` sheet every surface has always read, so the miniature and the
## legibility ruler are unaffected by the beat: a time frame is another axis, and
## a thumbnail or a report taken on a different one answers a different question.
## Only the families in `FRAME_B_PATHS` have a second frame; every other family
## answers frame 0 whatever it is asked, so a caller never has to know which
## families animate.
static func sheet_path(p_family: int, p_frame: int = 0) -> String:
	if p_frame == 1 and FRAME_B_PATHS.has(p_family):
		return FRAME_B_PATHS[p_family]
	return SHEET_PATHS[p_family]


## Every cell family `p_family`'s sheet holds, which is what BattleView
## registers a tile for. Stated here rather than counted by the caller, because
## a bridge's variant is a deck and a bed and a phase is an index, and only this file may
## know which sheet is which.
static func sheet_cells(p_family: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if PHASE_COUNTS.has(p_family):
		for index in PHASE_COUNTS[p_family]:
			cells.append(atlas_coords(p_family, index))
		return cells
	if p_family == Family.BRIDGES:
		for bed in BridgeBed.size():
			for deck in BRIDGE_DECKS:
				cells.append(Vector2i(deck, bed))
		return cells
	for connection in CONNECTION_VARIANTS:
		cells.append(atlas_coords(p_family, connection))
	return cells


## Where variant `p_variant` sits on family `p_family`'s sheet: connection mask
## m at grid (m % 4, m / 4), a phase along the sheet's one row, a deck along
## its bed's row.
static func atlas_coords(p_family: int, p_variant: int) -> Vector2i:
	if p_family == Family.BRIDGES:
		return Vector2i(0 if p_variant & BIT_E != 0 else 1, p_variant >> _BED_SHIFT)
	if PHASE_COUNTS.has(p_family):
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
