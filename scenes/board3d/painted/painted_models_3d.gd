class_name PaintedModels3D
extends RefCounted
## The Blender-built painted miniatures: one mesh and one texture per model, shared
## by every army, and one material per call, since the board tints it in place.

const SHADER: Shader = preload("res://scenes/board3d/painted/painted_miniature_3d.gdshader")
const ROOT := "res://assets/models/%s/%s"
const UNITS := "units"
const BUILDINGS := "buildings"
const TERRAIN := "terrain"
const GENERALS := "generals"
const MUZZLE := "muzzle"
const EMBLEM := "emblem"
const EMBLEM_EDGE := "emblem_edge"
## A rifle squad's cut-in figure is its own model, as is every rotor.
const LONE_SUFFIX := "_lone"
const ROTOR_SUFFIX := "_rotor"

static var _models: Dictionary[String, Baked] = {}
static var _kept: Array[Material] = []


## What one built model's file holds.
class Baked:
	extends RefCounted
	var mesh: ArrayMesh
	var markers: Dictionary[String, Vector3] = {}
	var paint: Texture2D
	var normals: Texture2D


static func exists(folder: String, id: StringName) -> bool:
	return ResourceLoader.exists(ROOT % [folder, "%s.glb" % id])


## Holds both shaders for the game's life, so no play builds them twice.
static func keep_shaders() -> void:
	if not _kept.is_empty():
		return
	for shader: Shader in [ModelSkin3D.OPAQUE, ModelSkin3D.FADING]:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.get_rid()
		_kept.append(material)


static func unit_id(type_id: StringName, lone: bool) -> StringName:
	var own := StringName(String(type_id) + LONE_SUFFIX)
	return own if lone and exists(UNITS, own) else type_id


## A fresh model: a `Body`, and on a helicopter a part per rotor at its hub.
static func unit(type_id: StringName, theme: CommanderVisuals.FactionTheme, lone: bool) -> Node3D:
	var id := unit_id(type_id, lone)
	var root := _single(UNITS, id, theme)
	root.name = String(type_id)
	var hubs: Array = AirModels3D.ROTOR_HUBS.get(type_id, [])
	var rotor := StringName(String(type_id) + ROTOR_SUFFIX)
	for i in hubs.size():
		var part := MeshInstance3D.new()
		part.name = UnitModels3D.ROTOR_PART % i
		part.mesh = baked(UNITS, rotor).mesh
		part.material_override = material_for(UNITS, rotor, theme)
		part.position = hubs[i]
		root.add_child(part)
	return root


static func property(terrain_id: StringName, theme: CommanderVisuals.FactionTheme) -> Node3D:
	return _single(BUILDINGS, terrain_id, theme)


## Where a model's shot leaves it, or `Vector3.INF` for a model with no gun.
static func muzzle_of(type_id: StringName, lone: bool) -> Vector3:
	return baked(UNITS, unit_id(type_id, lone)).markers.get(MUZZLE, Vector3.INF)


static func baked(folder: String, id: StringName) -> Baked:
	var key := "%s/%s" % [folder, id]
	if not _models.has(key):
		_models[key] = _load(folder, id)
	return _models[key]


## A fresh material for one model in one army.
static func material_for(
	folder: String, id: StringName, theme: CommanderVisuals.FactionTheme
) -> ShaderMaterial:
	var model := baked(folder, id)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"paint", model.paint)
	material.set_shader_parameter(&"normals", model.normals)
	if model.markers.has(EMBLEM) and model.markers.has(EMBLEM_EDGE):
		material.set_shader_parameter(&"emblem_centre", model.markers[EMBLEM])
		var radius := model.markers[EMBLEM].distance_to(model.markers[EMBLEM_EDGE])
		material.set_shader_parameter(&"emblem_radius", radius)
	wear(material, theme)
	return material


## Puts a model's material in an army's colours and badge: a capture's flip.
static func wear(material: ShaderMaterial, theme: CommanderVisuals.FactionTheme) -> void:
	var ramp := FactionRamp3D.of(theme)
	material.set_shader_parameter(&"ramp_dark", ramp.dark)
	material.set_shader_parameter(&"ramp_base", ramp.base)
	material.set_shader_parameter(&"ramp_light", ramp.light)
	var emblem_path := "%s/%s.png" % [CommanderVisuals.FACTION_DIR, theme.key]
	var worn := ResourceLoader.exists(emblem_path)
	if worn:
		material.set_shader_parameter(&"emblem", load(emblem_path))
	var radius: Variant = material.get_shader_parameter(&"emblem_radius")
	if radius != null and float(radius) > 0.0 and not worn:
		material.set_shader_parameter(&"emblem_radius", 0.0)


## Puts a building or a prop on the board: its marks and its fog read on it.
static func on_board(material: ShaderMaterial, overlay: Texture2D, fog: Texture2D, cells: Vector2) -> void:
	material.set_shader_parameter(&"on_board", true)
	material.set_shader_parameter(&"overlay", overlay)
	material.set_shader_parameter(&"fog_cells", fog)
	material.set_shader_parameter(&"map_cells", cells)


static func _single(
	folder: String, id: StringName, theme: CommanderVisuals.FactionTheme
) -> Node3D:
	var root := Node3D.new()
	root.name = String(id)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = baked(folder, id).mesh
	body.material_override = material_for(folder, id, theme)
	root.add_child(body)
	return root


static func _load(folder: String, id: StringName) -> Baked:
	var model := Baked.new()
	var scene: PackedScene = load(ROOT % [folder, "%s.glb" % id])
	var holder := scene.instantiate()
	for mesh_instance in holder.find_children("*", "MeshInstance3D", true, false):
		model.mesh = (mesh_instance as MeshInstance3D).mesh
	for node in holder.find_children("*", "Node3D", true, false):
		if String(node.name) in [MUZZLE, EMBLEM, EMBLEM_EDGE]:
			model.markers[String(node.name)] = (node as Node3D).position
	holder.free()
	model.paint = load(ROOT % [folder, "%s_paint.png" % id])
	model.normals = load(ROOT % [folder, "%s_normal.png" % id])
	return model
