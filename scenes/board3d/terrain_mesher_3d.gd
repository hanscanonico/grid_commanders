class_name TerrainMesher3D
extends RefCounted
## Builds the 3D board's ground from MapData: two static meshes, the land and the
## water, so the whole board draws in two calls.
##
## Every cell's top is a 3x3 grid of sub-squares, each with its own height and
## colour. That one shape says every connection the 2D autotiles draw: a river
## is a channel of low wet squares through its banks, a road a strip of road
## squares across the grass, a bridge a deck over wet squares. Walls are then a
## single rule — wherever a sub-square stands above its neighbour, whichever cell
## that neighbour is in, a wall joins them — which gives the coast, the river
## banks and the diorama's sides alike.
##
## Which way a road or a river runs is `TerrainAutotiles.mask`'s answer, the same
## the 2D board wears, so the two boards can never disagree about a junction.
## Properties are not built here: their buildings change colour on capture and
## are Board3D's nodes. Deterministic: the scatter is a hash of the cell.

const GRASS := Color("#74a846")
const WOODS_FLOOR := Color("#548a37")
const ROAD := Color("#b9ab8e")
const SAND := Color("#dcc58a")
const EARTH := Color("#8a6440")
const EARTH_DEEP := Color("#5a4130")
const SEA := Color("#2f6fb5")
const SEA_DEEP := Color("#1e4c80")
const RIVER := Color("#4c9cd4")
const ROCK := Color("#968263")
const ROCK_DARK := Color("#7a6750")
const SNOW := Color("#f1f1ec")
const TRUNK := Color("#6b4a2b")
const PLANK := Color("#a07b52")
const RAIL := Color("#5c4630")
const FOLIAGE: Array[Color] = [Color("#3f7f2f"), Color("#4b8f37"), Color("#377029")]

## Sub-square bounds across a cell: two 0.3 bands and a 0.4 middle, the middle
## wide enough for a river a unit can be seen wading.
const _CUTS: Array[float] = [0.0, 0.3, 0.7, 1.0]
## How far a diorama side's upper band reaches before the deep earth below it.
const _RIM_BAND := 0.12
## Sub-square index of each edge's middle square, N E S W, and the four steps.
const _EDGE_SQUARE: Array[int] = [1, 5, 7, 3]
const _STEPS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const _BITS: Array[int] = [
	TerrainAutotiles.BIT_N, TerrainAutotiles.BIT_E, TerrainAutotiles.BIT_S, TerrainAutotiles.BIT_W
]
const _WET: Array[StringName] = [&"sea", &"reef", &"river", &"bridge"]


## One cell's top: nine heights, nine colours, nine wet flags, row-major.
class Top:
	extends RefCounted
	var height := PackedFloat32Array()
	var colour := PackedColorArray()
	var wet: Array[bool] = []

	func _init(h: float, c: Color, is_wet: bool) -> void:
		height.resize(9)
		height.fill(h)
		colour.resize(9)
		colour.fill(c)
		wet.resize(9)
		wet.fill(is_wet)

	func set_square(k: int, h: float, c: Color, is_wet: bool) -> void:
		height[k] = h
		colour[k] = c
		wet[k] = is_wet


## The land mesh and the water mesh, in that order; the water one is null on a
## board with no water on it.
static func build(map: MapData) -> Array[ArrayMesh]:
	var tops: Dictionary[Vector2i, Top] = {}
	for y in map.height:
		for x in map.width:
			tops[Vector2i(x, y)] = top_of(map, Vector2i(x, y))
	var land := MeshKit.begin()
	var water := MeshKit.begin()
	var any_water := false
	for cell: Vector2i in tops:
		var top := tops[cell]
		for k in 9:
			var st := water if top.wet[k] else land
			any_water = any_water or top.wet[k]
			_square_top(st, cell, k, top)
			_square_walls(st, tops, cell, k)
		_decorate(land, map, cell)
	var meshes: Array[ArrayMesh] = [land.commit(), water.commit() if any_water else null]
	return meshes


## The nine sub-squares a cell's terrain lays down.
static func top_of(map: MapData, cell: Vector2i) -> Top:
	var id := map.terrain_at(cell).id
	var shade := 0.95 + 0.1 * _noise(cell, 0)
	match id:
		&"sea", &"reef":
			return Top.new(BoardSpace3D.SEA_TOP, _tint(SEA, shade), true)
		&"shoal":
			return Top.new(BoardSpace3D.SHOAL_TOP, _tint(SAND, shade), false)
		&"river":
			return _channel(map, cell, _tint(GRASS, shade))
		&"bridge":
			return _bridge_bed(map, cell, _tint(GRASS, shade))
		&"road":
			return _road(map, cell, _tint(GRASS, shade))
		&"woods":
			return _field(cell, WOODS_FLOOR)
	return _field(cell, GRASS)


## Open ground, each sub-square a shade off its neighbours. The variety stays in
## the ground plane: anything that stood up off a plain would read as something
## to capture (presentation.md, standing terrain is interactive).
static func _field(cell: Vector2i, colour: Color) -> Top:
	var top := Top.new(BoardSpace3D.LAND_TOP, colour, false)
	for k in 9:
		top.colour[k] = _tint(colour, 0.95 + 0.1 * _noise(cell, 80 + k))
	return top


static func _channel(map: MapData, cell: Vector2i, bank: Color) -> Top:
	var top := Top.new(BoardSpace3D.LAND_TOP, bank, false)
	var mask := TerrainAutotiles.mask(map, cell)
	top.set_square(4, BoardSpace3D.RIVER_TOP, RIVER, true)
	for side in 4:
		if mask & _BITS[side]:
			top.set_square(_EDGE_SQUARE[side], BoardSpace3D.RIVER_TOP, RIVER, true)
	return top


## Water under the whole deck, with banks only where the deck lands on dry
## ground — so a causeway of bridges across the sea stays open water beneath.
## A deck no water meets stands on its field, as the flat board draws it.
static func _bridge_bed(map: MapData, cell: Vector2i, bank: Color) -> Top:
	var bed := TerrainAutotiles.bridge_bed(map, cell)
	if bed == TerrainAutotiles.BridgeBed.DRY:
		return _field(cell, GRASS)
	var by_sea := bed == TerrainAutotiles.BridgeBed.SEA
	var level := BoardSpace3D.SEA_TOP if by_sea else BoardSpace3D.RIVER_TOP
	var colour := SEA if by_sea else RIVER
	var top := Top.new(level, colour, true)
	var deck_ew := TerrainAutotiles.mask(map, cell) & TerrainAutotiles.BIT_E != 0
	for side in 4:
		var along_deck := (side % 2 == 1) == deck_ew
		var id := TerrainAutotiles.terrain_id(map, cell + _STEPS[side])
		if along_deck and not _WET.has(id) and BoardSpace3D.ground_top(id) >= 0.0:
			for k in _side_squares(side):
				top.set_square(k, BoardSpace3D.LAND_TOP, bank, false)
	return top


static func _road(map: MapData, cell: Vector2i, grass: Color) -> Top:
	var top := Top.new(BoardSpace3D.LAND_TOP, grass, false)
	var mask := TerrainAutotiles.mask(map, cell)
	if mask == 0:
		mask = TerrainAutotiles.BIT_E | TerrainAutotiles.BIT_W
	var paving := _tint(ROAD, 0.97 + 0.06 * _noise(cell, 1))
	top.set_square(4, BoardSpace3D.LAND_TOP, paving, false)
	for side in 4:
		if mask & _BITS[side]:
			top.set_square(_EDGE_SQUARE[side], BoardSpace3D.LAND_TOP, paving, false)
	return top


## The three sub-squares along one side, N E S W.
static func _side_squares(side: int) -> Array[int]:
	match side:
		0:
			return [0, 1, 2]
		1:
			return [2, 5, 8]
		2:
			return [6, 7, 8]
	return [0, 3, 6]


static func _square_rect(cell: Vector2i, k: int) -> Rect2:
	var i := k % 3
	var j := floori(k / 3.0)
	var from := Vector2(cell) + Vector2(_CUTS[i], _CUTS[j])
	var to := Vector2(cell) + Vector2(_CUTS[i + 1], _CUTS[j + 1])
	return Rect2(from, to - from)


static func _square_top(st: SurfaceTool, cell: Vector2i, k: int, top: Top) -> void:
	var r := _square_rect(cell, k)
	var h := top.height[k]
	MeshKit.quad(
		st,
		Vector3(r.position.x, h, r.end.y),
		Vector3(r.end.x, h, r.end.y),
		Vector3(r.end.x, h, r.position.y),
		Vector3(r.position.x, h, r.position.y),
		top.colour[k]
	)


## A wall on every side of sub-square `k` whose neighbour — in this cell or the
## next — stands lower; off the board the neighbour is the slab's bottom.
static func _square_walls(
	st: SurfaceTool, tops: Dictionary[Vector2i, Top], cell: Vector2i, k: int
) -> void:
	var top := tops[cell]
	var h := top.height[k]
	for side in 4:
		var step := _STEPS[side]
		var i := k % 3 + step.x
		var j := floori(k / 3.0) + step.y
		var other := cell + Vector2i(floori(i / 3.0), floori(j / 3.0))
		var low := BoardSpace3D.SLAB_BOTTOM
		if tops.has(other):
			low = tops[other].height[posmod(j, 3) * 3 + posmod(i, 3)]
		if low >= h - 0.0001:
			continue
		var side_colour := _wall_colour(top, k)
		if tops.has(other):
			_wall(st, _square_rect(cell, k), side, low, h, side_colour)
		else:
			var band := h - _RIM_BAND
			_wall(st, _square_rect(cell, k), side, band, h, side_colour)
			_wall(st, _square_rect(cell, k), side, low, band, EARTH_DEEP)


static func _wall_colour(top: Top, k: int) -> Color:
	if top.wet[k]:
		return SEA_DEEP
	if top.height[k] < BoardSpace3D.LAND_TOP:
		return SAND.darkened(0.2)
	return EARTH


static func _wall(st: SurfaceTool, r: Rect2, side: int, lo: float, hi: float, c: Color) -> void:
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	match side:
		0:
			MeshKit.quad(
				st,
				Vector3(x1, lo, z0),
				Vector3(x0, lo, z0),
				Vector3(x0, hi, z0),
				Vector3(x1, hi, z0),
				c
			)
		1:
			MeshKit.quad(
				st,
				Vector3(x1, lo, z1),
				Vector3(x1, lo, z0),
				Vector3(x1, hi, z0),
				Vector3(x1, hi, z1),
				c
			)
		2:
			MeshKit.quad(
				st,
				Vector3(x0, lo, z1),
				Vector3(x1, lo, z1),
				Vector3(x1, hi, z1),
				Vector3(x0, hi, z1),
				c
			)
		3:
			MeshKit.quad(
				st,
				Vector3(x0, lo, z0),
				Vector3(x0, lo, z1),
				Vector3(x0, hi, z1),
				Vector3(x0, hi, z0),
				c
			)


# --- what stands on the ground -------------------------------------------------


static func _decorate(st: SurfaceTool, map: MapData, cell: Vector2i) -> void:
	var centre := BoardSpace3D.cell_centre(cell)
	var base := Vector3(centre.x, BoardSpace3D.LAND_TOP, centre.y)
	match map.terrain_at(cell).id:
		&"woods":
			_trees(st, cell, base)
		&"mountain":
			_mountain(st, cell, base)
		&"reef":
			_rocks(st, cell, Vector3(centre.x, BoardSpace3D.SEA_TOP, centre.y))
		&"bridge":
			_deck(st, map, cell, base)


## Four trees round the cell's edge, leaving the middle open for whoever stands
## in the wood.
static func _trees(st: SurfaceTool, cell: Vector2i, base: Vector3) -> void:
	var spots: Array[Vector2] = [
		Vector2(-0.27, -0.26), Vector2(0.27, -0.28), Vector2(-0.28, 0.27), Vector2(0.26, 0.28)
	]
	for n in spots.size():
		var jitter := Vector2(_noise(cell, 10 + n) - 0.5, _noise(cell, 20 + n) - 0.5) * 0.1
		var spot := spots[n] + jitter
		var size := 0.85 + 0.3 * _noise(cell, 30 + n)
		var foliage := FOLIAGE[int(_noise(cell, 40 + n) * FOLIAGE.size()) % FOLIAGE.size()]
		var foot := base + Vector3(spot.x, 0, spot.y)
		MeshKit.column(st, MeshKit.at(foot), 0.035, 0.03, 0.08 * size, 5, TRUNK)
		MeshKit.column(
			st,
			MeshKit.at(foot + Vector3(0, 0.06 * size, 0)),
			0.15 * size,
			0,
			0.26 * size,
			6,
			foliage
		)
		MeshKit.column(
			st,
			MeshKit.at(foot + Vector3(0, 0.19 * size, 0), 30),
			0.11 * size,
			0,
			0.2 * size,
			6,
			foliage.lightened(0.08)
		)


## A shoulder a unit stands on, and two snow-capped peaks rising off its back.
static func _mountain(st: SurfaceTool, cell: Vector2i, base: Vector3) -> void:
	var turn := _noise(cell, 50) * 360.0
	MeshKit.column(st, MeshKit.at(base, turn), 0.47, 0.3, BoardSpace3D.MOUNTAIN_SHOULDER, 7, ROCK)
	var peaks: Array[Vector4] = [Vector4(-0.2, -0.17, 0.25, 0.64), Vector4(0.19, -0.2, 0.21, 0.5)]
	for n in peaks.size():
		var p := peaks[n]
		var tall := p.w * (0.9 + 0.2 * _noise(cell, 51 + n))
		var foot := base + Vector3(p.x, 0, p.y)
		MeshKit.column(st, MeshKit.at(foot, turn + 20 * n), p.z, 0, tall, 5, ROCK_DARK)
		var cap := 0.36
		MeshKit.column(
			st,
			MeshKit.at(foot + Vector3(0, tall * (1.0 - cap), 0), turn + 20 * n),
			p.z * cap * 1.08,
			0,
			tall * cap * 1.02,
			5,
			SNOW
		)


static func _rocks(st: SurfaceTool, cell: Vector2i, base: Vector3) -> void:
	for n in 3:
		var angle := TAU * (float(n) / 3.0 + _noise(cell, 60 + n) * 0.2)
		var reach := 0.18 + 0.12 * _noise(cell, 63 + n)
		var size := 0.08 + 0.05 * _noise(cell, 66 + n)
		var at := base + Vector3(cos(angle) * reach, 0, sin(angle) * reach)
		var squash := Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 1.0)), at)
		MeshKit.ball(st, squash, size, 3, 5, ROCK_DARK)


static func _deck(st: SurfaceTool, map: MapData, cell: Vector2i, base: Vector3) -> void:
	var deck_ew := TerrainAutotiles.mask(map, cell) & TerrainAutotiles.BIT_E != 0
	var turn := 0.0 if deck_ew else 90.0
	var top := BoardSpace3D.DECK_TOP
	var deck := MeshKit.at(Vector3(base.x, top - 0.025, base.z), turn)
	MeshKit.box(st, deck, Vector3(1.0, 0.05, 0.46), PLANK)
	for z: float in [-0.215, 0.215]:
		var rail := deck * Transform3D(Basis.IDENTITY, Vector3(0, 0.05, z))
		MeshKit.box(st, rail, Vector3(1.0, 0.05, 0.035), RAIL)
	for x: float in [-0.32, 0.32]:
		var pier := deck * Transform3D(Basis.IDENTITY, Vector3(x, -0.1, 0))
		MeshKit.box(st, pier, Vector3(0.08, 0.16, 0.36), RAIL)


## A colour a shade lighter or darker, its alpha left whole.
static func _tint(c: Color, by: float) -> Color:
	return Color(c.r * by, c.g * by, c.b * by)


## A stable number in [0, 1) for one cell and one question.
static func _noise(cell: Vector2i, salt: int) -> float:
	return float(hash(Vector3i(cell.x, cell.y, salt)) % 10007) / 10007.0
