class_name AirShadow3D
extends RefCounted
## The shadow an aircraft lays straight down on the ground under it: its body's
## silhouette flattened onto the cell, in one solid tone. The board's sun is low
## in the west, so an aircraft's own cast shadow lands a cell away and makes
## its position ambiguous; this one marks the cell it is over. It is the 3D
## reading of the flat board's rule that only what is airborne casts, and that
## its shadow is solid — so an aircraft wearing one casts nothing from the sun.

## The flat board's air shadow tone (the sprite generator's `sun.SHADOW`).
const TONE := Color("101218")
## How far the shadow stands off the ground, so it never fights the surface.
const LIFT := 0.012
const FLAT := 0.001
## The silhouette is drawn this much smaller, about the cell's centre: dark and
## solid at full size it read as a second aircraft parked on the ground, and
## the widest flyer's shadow spilled to its cell's edge.
const SPREAD := 0.75


## Lays a shadow under `model`, a `UnitModels3D.build` aircraft, and stops its
## parts casting from the sun. Returns the shadow for `lay` to pose.
static func attach(model: Node3D) -> MeshInstance3D:
	for part in model.get_children():
		var geometry := part as GeometryInstance3D
		if geometry != null:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = (model.get_node("Body") as MeshInstance3D).mesh
	shadow.scale = Vector3(SPREAD, FLAT, SPREAD)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = TONE
	shadow.material_override = material
	model.add_child(shadow)
	return shadow


## Puts `shadow` on the ground at height `ground`, under a model whose root
## stands at `height`.
static func lay(shadow: Node3D, height: float, ground: float) -> void:
	shadow.position.y = ground + LIFT - height
