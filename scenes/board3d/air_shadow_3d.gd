class_name AirShadow3D
extends RefCounted
## The shadow an aircraft lays straight down on the ground under it: its body's
## silhouette, flattened onto the cell and darkening whatever ground is there
## rather than painting over it. The board's sun is low in the west, so an
## aircraft's own cast shadow lands a cell away and makes its position
## ambiguous; this one marks the cell it is over. It is the 3D reading of the
## flat board's rule that only what is airborne casts — so an aircraft wearing
## one casts nothing from the sun.
##
## Every aircraft's silhouette is one tile of a single texture, drawn by one
## material that multiplies the ground under it, so every shadow on the board is
## one shader. The material is never freed — Godot drops a shader with its last
## material, and rebuilding it stalls the web build — and `primer` draws it
## before the first aircraft needs it.

## What the ground keeps of its own colour under a shadow: a darkening, not a
## tone. Solid near-black read as a second aircraft parked on the cell.
const SHADE := 0.6
## How far the shadow stands off the ground, so it never fights the surface.
const LIFT := 0.012
## The silhouette is drawn this much smaller, about the cell's centre, so the
## widest flyer's shadow stays well inside its cell.
const SPREAD := 0.75
## Texels a silhouette is drawn on across one cell.
const TILE_PX := 64
## The aircraft the atlas holds a tile for, in tile order.
const FLYERS: Array[StringName] = [&"fighter", &"bomber", &"b_copter", &"t_copter"]

static var _material: StandardMaterial3D
static var _quads: Dictionary[StringName, ArrayMesh] = {}


## Lays a shadow under `model`, a `UnitModels3D.build` of `type_id`, and stops
## its parts casting from the sun. Returns the shadow for `lay` to pose.
static func attach(model: Node3D, type_id: StringName) -> MeshInstance3D:
	for part in model.get_children():
		var geometry := part as GeometryInstance3D
		if geometry != null:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow := _instance(_quad(FLYERS.find(type_id), SPREAD))
	shadow.name = "Shadow"
	model.add_child(shadow)
	return shadow


## Puts `shadow` on the ground at height `ground`, under a model whose root
## stands at `height`.
static func lay(shadow: Node3D, height: float, ground: float) -> void:
	shadow.position.y = ground + LIFT - height


## A speck of the shadow material that darkens nothing — it samples the
## atlas's clear margin, and the ground times one is the ground — for a board
## to stand in front of its lens until it has been drawn once, so the shader is
## built while the board comes up rather than the first time an aircraft is.
static func primer() -> MeshInstance3D:
	var speck := _instance(_quad(-1, 0.01))
	speck.name = "ShadowPrimer"
	return speck


## The silhouette of each flyer seen from straight above, one tile apiece: the
## ground's own `SHADE` inside it and white — no change — around it. A tile's
## texel (u, v) is the model's (x, z), the cell running -0.5 to 0.5 across it.
static func atlas() -> Image:
	var image := Image.create_empty(TILE_PX * FLYERS.size(), TILE_PX, false, Image.FORMAT_L8)
	image.fill(Color.WHITE)
	var shade := Color(SHADE, SHADE, SHADE)
	var neutral := CommanderVisuals.theme_for_key(CommanderVisuals.NEUTRAL_KEY)
	for tile in FLYERS.size():
		var body := UnitModels3D.mesh_for(FLYERS[tile], neutral)
		var arrays := body.surface_get_arrays(0)
		var corners: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(0, corners.size(), 3):
			if normals[i].y > 0.0:
				var face: Array[Vector3] = [corners[i], corners[i + 1], corners[i + 2]]
				_fill(image, tile, face, shade)
	return image


## Paints every texel of `tile` whose centre one up-facing triangle covers.
## A closed body's silhouette is the union of its up-facing faces.
static func _fill(image: Image, tile: int, tri: Array[Vector3], shade: Color) -> void:
	var pts: Array[Vector2] = []
	for corner in tri:
		pts.append((Vector2(corner.x, corner.z) + Vector2.ONE * 0.5) * TILE_PX)
	var area := (pts[1] - pts[0]).cross(pts[2] - pts[0])
	if absf(area) < 0.0001:
		return
	var lo := pts[0].min(pts[1]).min(pts[2]).floor()
	var hi := pts[0].max(pts[1]).max(pts[2]).ceil()
	for y in range(maxi(0, int(lo.y)), mini(TILE_PX, int(hi.y))):
		for x in range(maxi(0, int(lo.x)), mini(TILE_PX, int(hi.x))):
			var p := Vector2(x + 0.5, y + 0.5)
			var a := (pts[1] - pts[0]).cross(p - pts[0]) * area
			var b := (pts[2] - pts[1]).cross(p - pts[1]) * area
			var c := (pts[0] - pts[2]).cross(p - pts[2]) * area
			if a >= 0.0 and b >= 0.0 and c >= 0.0:
				image.set_pixel(tile * TILE_PX + x, y, shade)


## A flat square `size` across, mapped onto `tile`'s silhouette — or, for a
## tile of -1, onto one clear texel of the atlas's margin.
static func _quad(tile: int, size: float) -> ArrayMesh:
	var key := StringName("%d|%s" % [tile, size])
	if _quads.has(key):
		return _quads[key]
	var tiles := float(FLYERS.size())
	var u0 := maxi(tile, 0) / tiles
	var u1 := (maxi(tile, 0) + 1) / tiles
	var v0 := 0.0
	var v1 := 1.0
	if tile < 0:
		u1 = u0 + 0.5 / (tiles * TILE_PX)
		v1 = 0.5 / TILE_PX
	var h := size / 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for corner: Vector4 in [
		Vector4(-h, -h, u0, v0),
		Vector4(h, -h, u1, v0),
		Vector4(h, h, u1, v1),
		Vector4(-h, -h, u0, v0),
		Vector4(h, h, u1, v1),
		Vector4(-h, h, u0, v1),
	]:
		st.set_uv(Vector2(corner.z, corner.w))
		st.add_vertex(Vector3(corner.x, 0.0, corner.y))
	_quads[key] = st.commit()
	return _quads[key]


static func _instance(mesh: ArrayMesh) -> MeshInstance3D:
	var shadow := MeshInstance3D.new()
	shadow.mesh = mesh
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.material_override = _shared_material()
	return shadow


static func _shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.albedo_texture = ImageTexture.create_from_image(atlas())
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return _material
