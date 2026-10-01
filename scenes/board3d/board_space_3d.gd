class_name BoardSpace3D
extends RefCounted
## Where the 2D board's coordinates land in the 3D one, and how high each
## terrain stands. One world unit is one cell; map x runs along world +X and map
## y along world +Z, so a cell's centre is (x + 0.5, height, y + 0.5) and the
## map's north edge is the world's -Z side.
##
## Pure arithmetic over MapData, so the heights a unit is stood at, the surface a
## pointer ray is tested against and the quarter-turns the arrow keys are turned
## through are pinned without a scene.

## The 2D board's pixels per cell (BattleView.TILE), the one conversion between
## a sprite's position and a world point.
const PX_PER_CELL := 16.0

## Top of ordinary dry ground. Everything else is measured from it.
const LAND_TOP := 0.0
## The open sea's surface, a clear step below the land so a coast reads.
const SEA_TOP := -0.14
## A shoal's sand and a river's water, between the two.
const SHOAL_TOP := -0.05
const RIVER_TOP := -0.07
## A bridge deck, just proud of the banks it joins.
const DECK_TOP := 0.05
## The mountain's shoulder a unit stands on; the peaks rise behind it.
const MOUNTAIN_SHOULDER := 0.24
## Where the diorama's sides end.
const SLAB_BOTTOM := -0.55
## How high an aircraft flies over the ground under it: low enough that from
## the board camera its fuselage still reads inside its own cell, and high
## enough over a mountain's shoulder to clear the peaks.
const AIR_ALTITUDE := 0.47
## How high a pointer ray still meets a mountain: most of its peaks' height, so
## a click on a peak picks the mountain rather than the cell behind it.
const MOUNTAIN_PICK := 0.5
## The highest any cell answers a pointer ray at, where the ray walk starts.
const PICK_CEILING := MOUNTAIN_PICK

## What stands on each terrain, by id. A terrain missing here is dry ground.
const _STAND: Dictionary[StringName, float] = {
	&"sea": SEA_TOP,
	&"reef": SEA_TOP,
	&"shoal": SHOAL_TOP,
	&"river": RIVER_TOP,
	&"bridge": DECK_TOP,
	&"mountain": MOUNTAIN_SHOULDER,
}

## The ground's own top, which is what a cell's sides are walled against: a
## bridge and a river cut into land and a mountain rises off it, so all three
## stand on dry ground's top.
const _GROUND: Dictionary[StringName, float] = {
	&"sea": SEA_TOP,
	&"reef": SEA_TOP,
	&"shoal": SHOAL_TOP,
}


## A 2D board position (a sprite's `position`, a cell centre) on the ground plane.
static func plane_of(board_px: Vector2) -> Vector2:
	return board_px / PX_PER_CELL


static func cell_centre(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


static func cell_at(plane: Vector2) -> Vector2i:
	return Vector2i(plane.floor())


## The height a ground or naval unit stands at on `terrain_id`.
static func stand_top(terrain_id: StringName) -> float:
	return _STAND.get(terrain_id, LAND_TOP)


## The top of the ground slab a terrain is built on.
static func ground_top(terrain_id: StringName) -> float:
	return _GROUND.get(terrain_id, LAND_TOP)


## The stand height at any point of the plane, eased between the four nearest
## cell centres — so a tank walking off a mountain rolls down its flank rather
## than dropping a step at the cell edge. Off-board samples read the nearest
## edge cell, the way TerrainAutotiles clamps.
static func stand_at(map: MapData, plane: Vector2) -> float:
	var shifted := plane - Vector2(0.5, 0.5)
	var origin := Vector2i(shifted.floor())
	var t := shifted - Vector2(origin)
	t = t * t * (Vector2(3, 3) - 2.0 * t)
	var h00 := _stand_of(map, origin)
	var h10 := _stand_of(map, origin + Vector2i(1, 0))
	var h01 := _stand_of(map, origin + Vector2i(0, 1))
	var h11 := _stand_of(map, origin + Vector2i(1, 1))
	return lerpf(lerpf(h00, h10, t.x), lerpf(h01, h11, t.x), t.y)


## The height an aircraft flies at over any point of the plane: `AIR_ALTITUDE`
## over the ground it is above, climbing and descending with it as it eases.
static func fly_at(map: MapData, plane: Vector2) -> float:
	return stand_at(map, plane) + AIR_ALTITUDE


## The surface a pointer ray is tested against on `cell`: what a player sees as
## that cell's top. A mountain answers most of its peaks' height, not its
## shoulder, so a click on a peak lands on the cell the peak stands in.
static func pick_top(map: MapData, cell: Vector2i) -> float:
	if not map.in_bounds(cell):
		return LAND_TOP
	var id := map.terrain_at(cell).id
	return MOUNTAIN_PICK if id == &"mountain" else stand_top(id)


## A screen direction turned into a board direction for a camera turned
## `quarters` quarter-turns anticlockwise (seen from above) from looking north.
## Up always walks away from the camera, whichever side of the board it is on.
static func turned(direction: Vector2i, quarters: int) -> Vector2i:
	var out := direction
	for _i in posmod(quarters, 4):
		out = Vector2i(out.y, -out.x)
	return out


static func _stand_of(map: MapData, cell: Vector2i) -> float:
	var clamped := cell.clamp(Vector2i.ZERO, map.size() - Vector2i.ONE)
	return stand_top(map.terrain_at(clamped).id)
