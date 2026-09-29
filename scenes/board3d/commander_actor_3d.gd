class_name CommanderActor3D
extends Node3D
## A general standing on the 3D board as a little chibi officer, for the story
## scenes: the figure `CommanderFigure3D` builds, hung on pivots named `Hips`,
## `Torso`, `Head`, `ArmL`, `ArmR`, `LegL` and `LegR` (the prop under `ArmR`,
## at the hand), and posed by `ActorPose3D`, so a director only names a clip
## and a time. The figure faces local -Z, so `look_at` turns it to face.

const HEIGHT := CommanderFigure3D.HEIGHT
const HOLO_SHADER := preload("res://scenes/board3d/actor_holo_3d.gdshader")
const NODE_NAMES: Dictionary[StringName, String] = {
	&"hips": "Hips",
	&"torso": "Torso",
	&"head": "Head",
	&"arm_l": "ArmL",
	&"arm_r": "ArmR",
	&"leg_l": "LegL",
	&"leg_r": "LegR",
	&"prop": "Prop",
}

var _pivots: Dictionary[StringName, Node3D] = {}
var _meshes: Array[MeshInstance3D] = []
var _material: StandardMaterial3D
var _holo: ShaderMaterial
var _alpha := 1.0


## A general's figure in their army's colours; a null or neutral commander is
## a plain officer in the neutral grey.
static func make(commander: CommanderType) -> CommanderActor3D:
	var actor := CommanderActor3D.new()
	var id := CommanderType.NEUTRAL_ID if commander == null else commander.id
	actor.name = "Actor_%s" % id
	actor.build(CommanderLooks3D.look_of(id), CommanderVisuals.theme_for(commander))
	return actor


func build(look: Dictionary, theme: CommanderVisuals.FactionTheme) -> void:
	_material = MeshKit.vertex_material()
	for part in CommanderFigure3D.PARTS:
		var pivot := Node3D.new()
		pivot.name = NODE_NAMES[part]
		pivot.position = CommanderFigure3D.PIVOTS[part]
		var parent: StringName = CommanderFigure3D.PARENTS[part]
		(self if parent.is_empty() else _pivots[parent]).add_child(pivot)
		_pivots[part] = pivot
		var mesh := CommanderFigure3D.part_mesh(part, look, theme)
		if mesh == null:
			continue
		var shape := MeshInstance3D.new()
		shape.name = "Mesh"
		shape.mesh = mesh
		shape.material_override = _material
		pivot.add_child(shape)
		_meshes.append(shape)
	pose(&"idle", 0.0)


func pose(clip: StringName, t: float) -> void:
	var sample := ActorPose3D.sample(clip, t)
	for part: StringName in sample:
		if part == &"root":
			_pivots[&"hips"].position = CommanderFigure3D.PIVOTS[&"hips"] + sample[part]
		else:
			_pivots[part].rotation = sample[part]


## The top of the head in the actor's own space, as posed: where an emote
## bubble sits and what a framing keeps in shot.
func head_top() -> Vector3:
	return _head_frame() * Vector3(0, CommanderFigure3D.HEAD_TOP, 0)


## Eye level in the actor's own space, as posed, for a close-up.
func face_height() -> float:
	return (_head_frame() * Vector3(0, CommanderFigure3D.EYE_Y, 0)).y


func _head_frame() -> Transform3D:
	var hips := _pivots[&"hips"].transform
	return hips * _pivots[&"torso"].transform * _pivots[&"head"].transform


## Every part becomes a translucent, unshaded, scanlined projection in `tint`:
## a general with no army on this board, standing there as a hologram.
func set_hologram(tint: Color) -> void:
	_holo = ShaderMaterial.new()
	_holo.shader = HOLO_SHADER
	_holo.set_shader_parameter(&"tint", tint)
	for shape in _meshes:
		shape.material_override = _holo
		shape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_alpha(_alpha)


## Fades the whole figure, 0 gone to 1 solid: walking into or out of a building.
func set_alpha(a: float) -> void:
	_alpha = clampf(a, 0.0, 1.0)
	visible = _alpha > 0.0
	if _holo != null:
		_holo.set_shader_parameter(&"fade", _alpha)
		return
	var solid := _alpha >= 1.0
	_material.transparency = (
		BaseMaterial3D.TRANSPARENCY_DISABLED if solid else BaseMaterial3D.TRANSPARENCY_ALPHA
	)
	_material.albedo_color.a = _alpha
	var shadow := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if solid
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	for shape in _meshes:
		shape.cast_shadow = shadow
