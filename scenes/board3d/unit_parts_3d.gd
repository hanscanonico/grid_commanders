class_name UnitParts3D
extends RefCounted
## The shapes every 3D unit is built from beyond `MeshKit`'s primitives: lofted
## hulls, extruded profiles, and the thin parts — barrels, masts — that hold a
## minimum thickness so none can be authored too thin to survive board scale.

## The thinnest any barrel, rifle, antenna or rotor blade may be, in cells. At
## the default zoom a cell is about fifty pixels, and a thinner part aliases away.
const MIN_THICKNESS := 0.05
const ROD_SIDES := 6


## A convex polygon, fan-triangulated and turned to face `outward` whatever
## order its corners came in.
static func face(st: SurfaceTool, pts: Array[Vector3], outward: Vector3, color: Color) -> void:
	var normal := (pts[1] - pts[0]).cross(pts[2] - pts[0])
	if normal.dot(outward) < 0.0:
		pts.reverse()
	for i in range(1, pts.size() - 1):
		MeshKit.tri(st, pts[0], pts[i], pts[i + 1], color)


## A solid between two convex outlines of equal corner count, `low` at height
## `low_y` and `high` at `high_y`; outlines are (x, z) in the frame of `xf`.
static func loft(
	st: SurfaceTool,
	xf: Transform3D,
	low: PackedVector2Array,
	low_y: float,
	high: PackedVector2Array,
	high_y: float,
	color: Color
) -> void:
	var lows: Array[Vector3] = []
	var highs: Array[Vector3] = []
	var centre := Vector3.ZERO
	for i in low.size():
		lows.append(xf * Vector3(low[i].x, low_y, low[i].y))
		highs.append(xf * Vector3(high[i].x, high_y, high[i].y))
		centre += lows[i] + highs[i]
	centre /= float(low.size() * 2)
	var up := (xf.basis * Vector3.UP).normalized()
	face(st, highs.duplicate(), up, color)
	face(st, lows.duplicate(), -up, color)
	for i in low.size():
		var j := (i + 1) % low.size()
		var side: Array[Vector3] = [lows[i], lows[j], highs[j], highs[i]]
		var mid := (lows[i] + lows[j] + highs[i] + highs[j]) / 4.0
		face(st, side, mid - centre, color)


static func slab(
	st: SurfaceTool, xf: Transform3D, outline: PackedVector2Array, y0: float, y1: float, c: Color
) -> void:
	loft(st, xf, outline, y0, outline, y1, c)


## A side profile — an (x, y) outline — extruded across Z from `z0` to `z1`.
static func profile(
	st: SurfaceTool, outline: PackedVector2Array, z0: float, z1: float, c: Color
) -> void:
	var flipped := PackedVector2Array()
	for p in outline:
		flipped.append(Vector2(p.x, -p.y))
	slab(st, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO), flipped, z0, z1, c)


static func rect(x0: float, x1: float, z0: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## A frame at `pos` pitched `deg` nose-up about Z: +X swings toward +Y.
static func pitch(pos: Vector3, deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, deg_to_rad(deg)), pos)


## A hex tube running `length` along the frame's +X from its origin: a barrel,
## a rifle, a yard. Held to `MIN_THICKNESS` across its flats, measured after the
## frame's own scale.
static func barrel(st: SurfaceTool, xf: Transform3D, length: float, r: float, c: Color) -> void:
	var radius := maxf(r, _least_radius(minf(xf.basis.y.length(), xf.basis.z.length())))
	var mid := xf * Transform3D(Basis.IDENTITY, Vector3(length / 2.0, 0, 0))
	MeshKit.tube(st, mid, radius, length, ROD_SIDES, c)


## A hex mast or antenna standing `height` up the frame's Y from its origin,
## held to `MIN_THICKNESS` across like a barrel.
static func mast(st: SurfaceTool, xf: Transform3D, height: float, r: float, c: Color) -> void:
	var radius := maxf(r, _least_radius(minf(xf.basis.x.length(), xf.basis.z.length())))
	MeshKit.column(st, xf, radius, radius, height, ROD_SIDES, c)


## A cone lying along +X, its base at the frame's origin.
static func nose(
	st: SurfaceTool, xf: Transform3D, r: float, length: float, segments: int, c: Color
) -> void:
	MeshKit.column(
		st, xf * Transform3D(Basis(Vector3.BACK, -PI / 2.0)), r, 0.0, length, segments, c
	)


## The radius a hex rod needs for its flats to stand `MIN_THICKNESS` apart in a
## frame scaled by `scale` across it.
static func _least_radius(scale: float) -> float:
	return MIN_THICKNESS / 2.0 / cos(PI / ROD_SIDES) / scale
