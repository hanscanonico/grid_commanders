class_name UnitModels3D
extends RefCounted
## The eighteen units as low-poly 3D models for the 3D board, built facing +X
## with the origin at the centre of the footprint on the ground (the belly, for
## an aircraft; the waterline, for a ship). Each body is one merged mesh per
## unit type and faction, cached, so a full board of units stays a handful of
## meshes however many units stand on it.
##
## Shapes are exaggerated on purpose: a unit is about fifty pixels wide at the
## default camera, so what tells a tank from a medium tank is the turret and the
## barrel, not detail. `LandModels3D`, `AirModels3D` and `SeaModels3D` build the
## bodies from `UnitParts3D`'s shapes, in `FactionRamp3D`'s army tones and
## `UnitPalette3D`'s role colours.

## A foot unit's model is a few soldiers — three riflemen, two mech troopers; a
## cut-in squad posts them one per figure instead, blown up to stand beside a
## vehicle.
const LONE_SOLDIER_SCALE := 2.0

static var _meshes: Dictionary[String, ArrayMesh] = {}
static var _warned: Dictionary[StringName, bool] = {}


static func mesh_for(type_id: StringName, theme: CommanderVisuals.FactionTheme) -> ArrayMesh:
	var key := "%s|%s" % [type_id, theme.key]
	if not _meshes.has(key):
		var ramp := FactionRamp3D.of(theme)
		var st := MeshKit.begin()
		_body(st, type_id, ramp)
		_meshes[key] = ramp.commit(st)
	return _meshes[key]


## One figure of a cut-in squad: a foot unit's lone soldier, any other unit's
## whole body.
static func figure_mesh_for(type_id: StringName, theme: CommanderVisuals.FactionTheme) -> ArrayMesh:
	if type_id != &"infantry" and type_id != &"mech":
		return mesh_for(type_id, theme)
	var key := "%s|%s|lone" % [type_id, theme.key]
	if not _meshes.has(key):
		var ramp := FactionRamp3D.of(theme)
		var st := MeshKit.begin()
		LandModels3D.soldier(st, Vector3.ZERO, LONE_SOLDIER_SCALE, ramp, type_id == &"mech")
		_meshes[key] = ramp.commit(st)
	return _meshes[key]


## Where a figure's shot leaves it, in the model's frame: the front of its
## footprint at seven-tenths of its height, unless its gun stands elsewhere.
static func muzzle_for(type_id: StringName, aabb: AABB) -> Vector3:
	var muzzle := TrackedModels3D.muzzle_of(type_id)
	if muzzle.is_finite():
		return muzzle
	return Vector3(aabb.end.x, aabb.position.y + aabb.size.y * 0.7, 0.0)


## A fresh model: a `Body` and, on a helicopter, a `Rotor` spinning about its
## own Y. Every part shares one material made for this call alone, because the
## board tints it in place. `lone` builds a cut-in figure (`figure_mesh_for`).
static func build(
	type_id: StringName, theme: CommanderVisuals.FactionTheme, lone: bool = false
) -> Node3D:
	var root := Node3D.new()
	root.name = String(type_id)
	var material := MeshKit.vertex_material()
	var body := figure_mesh_for(type_id, theme) if lone else mesh_for(type_id, theme)
	_part(root, "Body", body, material, Vector3.ZERO)
	if AirModels3D.ROTOR_HUB.has(type_id):
		var hub: Vector3 = AirModels3D.ROTOR_HUB[type_id]
		_part(root, "Rotor", AirModels3D.rotor_mesh(type_id), material, hub)
	return root


static func _part(
	root: Node3D, part_name: String, mesh: ArrayMesh, material: Material, pos: Vector3
) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	root.add_child(part)


static func _body(st: SurfaceTool, type_id: StringName, ramp: FactionRamp3D) -> void:
	if LandModels3D.build(st, type_id, ramp):
		return
	if AirModels3D.build(st, type_id, ramp):
		return
	if SeaModels3D.build(st, type_id, ramp):
		return
	if not _warned.has(type_id):
		_warned[type_id] = true
		push_warning("UnitModels3D: no model for unit type '%s'" % type_id)
	MeshKit.block(st, MeshKit.at(Vector3.ZERO), Vector3(0.4, 0.3, 0.4), ramp.base)
