class_name ModelSkin3D
extends RefCounted
## One way to tint, fade and flash a model, whichever material it wears: the code
## models' `StandardMaterial3D` or the painted miniatures' shader. A board or a
## cut-in says what it wants of a model and never asks which kind it has.

const OPAQUE: Shader = preload("res://scenes/board3d/painted/painted_miniature_3d.gdshader")
const FADING: Shader = preload("res://scenes/board3d/painted/painted_miniature_fade_3d.gdshader")


## Every material a model's parts wear, each once.
static func materials_of(model: Node) -> Array[Material]:
	var found: Array[Material] = []
	for part in model.find_children("*", "GeometryInstance3D", true, false):
		var material := (part as GeometryInstance3D).material_override
		if material != null and not found.has(material):
			found.append(material)
	return found


## `tint`'s colour over the model and its alpha through it. `solid_silhouette`
## keeps a code model's depth while faded, as the painted shader always does.
static func paint(material: Material, tint: Color, solid_silhouette: bool = false) -> void:
	var faded := tint.a < 0.999
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		var wanted := FADING if faded else OPAQUE
		if shader_material.shader != wanted:
			shader_material.shader = wanted
		shader_material.set_shader_parameter(&"tint", Vector3(tint.r, tint.g, tint.b))
		shader_material.set_shader_parameter(&"alpha_scale", tint.a)
		return
	var standard := material as StandardMaterial3D
	var mode := BaseMaterial3D.TRANSPARENCY_ALPHA if faded else BaseMaterial3D.TRANSPARENCY_DISABLED
	if standard.transparency != mode:
		standard.transparency = mode
		if solid_silhouette:
			# Only while faded, so an opaque model keeps the one shader every
			# other board part shares.
			standard.depth_draw_mode = (
				BaseMaterial3D.DEPTH_DRAW_ALWAYS if faded else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			)
	standard.albedo_color = tint


## Readies a material to flash in `colour` without a shader swap at the flash.
static func flashable(material: Material, colour: Color) -> Material:
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter(&"flash_colour", Vector3(colour.r, colour.g, colour.b))
		return material
	return MeshKit.flashable(material as StandardMaterial3D, colour)


static func flash(material: Material, energy: float) -> void:
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter(&"flash", energy)
	else:
		(material as StandardMaterial3D).emission_energy_multiplier = energy


## What a painted model's moving parts follow. A code model has none and ignores it.
static func drive(material: Material, param: StringName, value: float) -> void:
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter(param, value)
