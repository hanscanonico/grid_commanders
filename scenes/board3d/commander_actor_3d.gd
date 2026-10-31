class_name CommanderActor3D
extends Node3D
## A general standing on the 3D board as a little chibi officer, for the story
## scenes: the figure `CommanderFigure3D` builds, hung on pivots named `Hips`,
## `Torso`, `Head`, `ArmL`, `ArmR`, `LegL` and `LegR` (the prop under `ArmR`,
## at the hand), and posed by `ActorPose3D`, so a director only names a clip
## and a time. The figure faces local -Z, so `look_at` turns it to face.

const HEIGHT := CommanderFigure3D.HEIGHT
const PAINTED_OFFICER := &"officer"
const ELBOW_REST := 0.12
const ELBOW_BEND := 0.35
const KNEE_BEND := 1.3
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

## A painted figure hangs on a skeleton in place of the pivots, its elbows and
## knees following the limbs the clips move.
var _skeleton: Skeleton3D
var _bones: Dictionary[StringName, int] = {}
var _painted_material: ShaderMaterial
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
	actor.build(CommanderLooks3D.look_of(id), CommanderVisuals.theme_for(commander), id)
	return actor


func build(
	look: Dictionary, theme: CommanderVisuals.FactionTheme, id: StringName = CommanderType.NEUTRAL_ID
) -> void:
	if PaintedArt.on() and _build_painted(id, theme):
		pose(&"idle", 0.0)
		return
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
	if _skeleton != null:
		_pose_painted(sample)
		return
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
	if _skeleton != null:
		return _skeleton.get_bone_global_pose(_bones[&"head"])
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
	if _painted_material != null:
		ModelSkin3D.paint(_painted_material, Color(1, 1, 1, _alpha))
		_cast_shadows(solid)
		return
	_material.transparency = (
		BaseMaterial3D.TRANSPARENCY_DISABLED if solid else BaseMaterial3D.TRANSPARENCY_ALPHA
	)
	_material.albedo_color.a = _alpha
	_cast_shadows(solid)


func _cast_shadows(solid: bool) -> void:
	var shadow := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if solid
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	for shape in _meshes:
		shape.cast_shadow = shadow


## Stands the general's Blender figure here. False when they have none yet.
func _build_painted(id: StringName, theme: CommanderVisuals.FactionTheme) -> bool:
	var file := PAINTED_OFFICER if id == CommanderType.NEUTRAL_ID else id
	var folder := PaintedModels3D.GENERALS
	if not PaintedModels3D.exists(folder, file):
		return false
	var figure: Node3D = load(PaintedModels3D.ROOT % [folder, "%s.glb" % file]).instantiate()
	add_child(figure)
	_skeleton = figure.find_children("*", "Skeleton3D", true, false)[0]
	for bone in _skeleton.get_bone_count():
		_bones[StringName(_skeleton.get_bone_name(bone))] = bone
	_painted_material = PaintedModels3D.material_for(folder, file, theme)
	for shape in figure.find_children("*", "MeshInstance3D", true, false):
		(shape as MeshInstance3D).material_override = _painted_material
		_meshes.append(shape)
	return true


## The clip's angles on the bones they name. An elbow bends as its arm swings out
## front, a knee as its leg trails, so a limb is never a rigid stick.
func _pose_painted(sample: Dictionary) -> void:
	for part: StringName in sample:
		if part == &"root":
			var hips := _bones[&"hips"]
			_skeleton.set_bone_pose_position(hips, _skeleton.get_bone_rest(hips).origin + sample[part])
		else:
			_turn_bone(part, sample[part])
	for side: String in ["l", "r"]:
		var arm: Vector3 = sample[StringName("arm_" + side)]
		var leg: Vector3 = sample[StringName("leg_" + side)]
		_turn_bone(StringName("fore_" + side), Vector3(ELBOW_REST + maxf(arm.x, 0.0) * ELBOW_BEND, 0, 0))
		_turn_bone(StringName("shin_" + side), Vector3(-maxf(-leg.x, 0.0) * KNEE_BEND, 0, 0))


func _turn_bone(part: StringName, euler: Vector3) -> void:
	var bone := _bones[part]
	var rest := _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	_skeleton.set_bone_pose_rotation(bone, rest * Quaternion.from_euler(euler))
