class_name MeshKit
extends RefCounted
## Flat-shaded low-poly primitives, appended to one SurfaceTool with the colour
## carried per vertex. Every model on the 3D board is built from these, so a
## whole unit or a whole terrain chunk commits to a single mesh and draws in one
## call — which is what keeps a full board playable on the web build.
##
## Faces are flat: each triangle gets its own normal, so a low vertex count reads
## as facets rather than as a lumpy smooth surface. Every call takes a
## `Transform3D` placing the primitive's own local frame, and the primitive is
## centred on that frame's origin unless its doc says otherwise.
##
## Winding: callers here think counter-clockwise seen from outside, and `tri`
## hands Godot the clockwise order it treats as the front face.


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## A transform standing a primitive at `pos`, turned `yaw_deg` about the up axis.
static func at(pos: Vector3, yaw_deg: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)


## One triangle, `a`, `b`, `c` counter-clockwise seen from its front.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(c)
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(b)


## One quad, corners counter-clockwise seen from its front.
static func quad(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color
) -> void:
	tri(st, a, b, c, color)
	tri(st, a, c, d, color)


## A box of `size`, centred on the frame's origin.
static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, color: Color) -> void:
	var h := size / 2.0
	var c: Array[Vector3] = []
	for corner in [
		Vector3(-h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z),
		Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z),
		Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z),
		Vector3(-h.x, h.y, h.z),
	]:
		c.append(xf * corner)
	quad(st, c[4], c[7], c[6], c[5], color)  # top
	quad(st, c[0], c[1], c[2], c[3], color)  # bottom
	quad(st, c[3], c[2], c[6], c[7], color)  # +z
	quad(st, c[1], c[0], c[4], c[5], color)  # -z
	quad(st, c[2], c[1], c[5], c[6], color)  # +x
	quad(st, c[0], c[3], c[7], c[4], color)  # -x


## A box standing on the frame's origin rather than centred on it.
static func block(st: SurfaceTool, xf: Transform3D, size: Vector3, color: Color) -> void:
	box(st, xf * Transform3D(Basis.IDENTITY, Vector3(0, size.y / 2.0, 0)), size, color)


## An upright prism or frustum along the frame's up axis, standing on its origin:
## `segments` sides, `bottom` and `top` radii. A `top` of zero is a cone, six
## segments a hex column. Both caps are closed.
static func column(
	st: SurfaceTool,
	xf: Transform3D,
	bottom: float,
	top: float,
	height: float,
	segments: int,
	color: Color
) -> void:
	var low: Array[Vector3] = []
	var high: Array[Vector3] = []
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		var dir := Vector3(cos(angle), 0, -sin(angle))
		low.append(xf * (dir * bottom))
		high.append(xf * (dir * top + Vector3(0, height, 0)))
	var base := xf * Vector3.ZERO
	var apex := xf * Vector3(0, height, 0)
	for i in segments:
		var j := (i + 1) % segments
		if top > 0.0:
			quad(st, low[i], low[j], high[j], high[i], color)
			tri(st, apex, high[i], high[j], color)
		else:
			tri(st, low[i], low[j], apex, color)
		tri(st, base, low[j], low[i], color)


## A column lying along the frame's +X axis instead of standing: a barrel, an
## exhaust, a hull's round nose. Centred on the origin along its length.
static func tube(
	st: SurfaceTool, xf: Transform3D, radius: float, length: float, segments: int, color: Color
) -> void:
	var lay := Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(-length / 2.0, 0, 0))
	column(st, xf * lay, radius, radius, length, segments, color)


## A ridge roof: a box whose top edge collapses to a ridge running along X. The
## eaves span `size.z`, the gables face ±X, and it stands on the frame's origin.
static func roof(st: SurfaceTool, xf: Transform3D, size: Vector3, color: Color) -> void:
	var h := Vector3(size.x / 2.0, size.y, size.z / 2.0)
	var a := xf * Vector3(-h.x, 0, h.z)
	var b := xf * Vector3(h.x, 0, h.z)
	var c := xf * Vector3(h.x, 0, -h.z)
	var d := xf * Vector3(-h.x, 0, -h.z)
	var ridge_w := xf * Vector3(-h.x, h.y, 0)
	var ridge_e := xf * Vector3(h.x, h.y, 0)
	quad(st, a, b, ridge_e, ridge_w, color)
	quad(st, c, d, ridge_w, ridge_e, color)
	tri(st, b, c, ridge_e, color)
	tri(st, d, a, ridge_w, color)
	quad(st, d, c, b, a, color)


## A wedge: a box whose top face slopes from full height at -X to nothing at +X —
## a sloped glacis, a ship's bow, a ramp. Stands on the frame's origin.
static func wedge(st: SurfaceTool, xf: Transform3D, size: Vector3, color: Color) -> void:
	var h := Vector3(size.x / 2.0, size.y, size.z / 2.0)
	var a := xf * Vector3(-h.x, 0, h.z)
	var b := xf * Vector3(h.x, 0, h.z)
	var c := xf * Vector3(h.x, 0, -h.z)
	var d := xf * Vector3(-h.x, 0, -h.z)
	var top_s := xf * Vector3(-h.x, h.y, h.z)
	var top_n := xf * Vector3(-h.x, h.y, -h.z)
	quad(st, d, c, b, a, color)
	quad(st, top_s, b, c, top_n, color)
	quad(st, d, a, top_s, top_n, color)
	tri(st, a, b, top_s, color)
	tri(st, c, d, top_n, color)


## A low-poly ball: `rings` bands of `segments` facets, centred on the origin.
static func ball(
	st: SurfaceTool, xf: Transform3D, radius: float, rings: int, segments: int, color: Color
) -> void:
	var rows: Array[Array] = []
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		var row: Array[Vector3] = []
		for s in segments:
			var theta := TAU * float(s) / float(segments)
			var p := Vector3(sin(phi) * cos(theta), cos(phi), -sin(phi) * sin(theta)) * radius
			row.append(xf * p)
		rows.append(row)
	for r in rings:
		var up: Array = rows[r]
		var down: Array = rows[r + 1]
		for s in segments:
			var t := (s + 1) % segments
			if r == 0:
				tri(st, up[s], down[s], down[t], color)
			elif r == rings - 1:
				tri(st, up[s], down[s], up[t], color)
			else:
				quad(st, up[s], down[s], down[t], up[t], color)


## The material every vertex-coloured model draws with: the colour is the
## mesh's, the light is the scene's. A fresh instance per call, because the
## board tints a unit's material in place to grey it out or flash it.
static func vertex_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.85
	return material
