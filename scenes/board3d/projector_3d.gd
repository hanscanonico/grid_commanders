class_name Projector3D
extends Node3D
## Light standing on the board for a cinematic: a disc on the ground and a beam
## rising out of it, with sparks drifting up the beam when it is a pillar. Two
## uses, one shape: the projector a general with no army on this board is
## projected from, and the pillar of light a Command Power raises round the
## general who fires it.
##
## Posed, never self-timed: the cinematic hands it a `presence` from 0 (dark) to
## 1 (fully up) and its own clock each frame.

const GLOW_SHADER := preload("res://scenes/board3d/holo_glow_3d.gdshader")
## The glow shader's shapes (`holo_glow_3d.gdshader`).
const GLOW_BEAM := 0
const GLOW_DISC := 1
const GLOW_RING := 2
const SEGMENTS := 24
const SPARKS := 48
const SPARK_SIZE := 0.035
const SPARK_LIFETIME := 1.3

var _beam: MeshInstance3D
var _beam_material: ShaderMaterial
var _disc_material: ShaderMaterial
var _sparks: CPUParticles3D


## A projector `radius` wide whose beam rises `height`, in `tint`. `sparks`
## makes it a pillar.
static func make(tint: Color, radius: float, height: float, sparks: bool) -> Projector3D:
	var projector := Projector3D.new()
	projector.name = "Projector3D"
	projector._build(tint, radius, height, sparks)
	projector.pose(0.0, 0.0)
	return projector


func _build(tint: Color, radius: float, height: float, sparks: bool) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = radius
	cone.bottom_radius = radius * 0.7
	cone.height = height
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = SEGMENTS
	_beam_material = glow_material(GLOW_BEAM, tint, height)
	_beam = _mesh(cone, _beam_material)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.6
	_disc_material = glow_material(GLOW_DISC, tint, radius * 1.3)
	_mesh(plane, _disc_material).position.y = 0.02
	if sparks:
		_sparks = _spark_emitter(tint, radius, height)
		add_child(_sparks)


## Stands the light `presence` of the way up, at `clock` seconds.
func pose(presence: float, clock: float) -> void:
	visible = presence > 0.0
	var up := clampf(presence, 0.0, 1.0)
	var height := (_beam.mesh as CylinderMesh).height
	_beam.scale = Vector3(1.0, maxf(up, 0.001), 1.0)
	_beam.position.y = height * up / 2.0
	for material: ShaderMaterial in [_beam_material, _disc_material]:
		material.set_shader_parameter(&"clock", clock)
		material.set_shader_parameter(&"strength", up)
	if _sparks != null:
		_sparks.emitting = up > 0.5


## Added light in `tint`, drawn as `shape` over a mesh `extent` in size — the
## beam's height, or a plane's half-width.
static func glow_material(shape: int, tint: Color, extent: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter(&"shape", shape)
	material.set_shader_parameter(&"tint", tint)
	material.set_shader_parameter(&"extent", extent)
	return material


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


static func _spark_emitter(tint: Color, radius: float, height: float) -> CPUParticles3D:
	var sparks := CPUParticles3D.new()
	sparks.amount = SPARKS
	sparks.lifetime = SPARK_LIFETIME
	sparks.emitting = false
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparks.emission_ring_radius = radius * 0.9
	sparks.emission_ring_inner_radius = radius * 0.3
	sparks.emission_ring_height = 0.05
	sparks.emission_ring_axis = Vector3.UP
	sparks.direction = Vector3.UP
	sparks.spread = 8.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = height * 0.45
	sparks.initial_velocity_max = height * 0.8
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * SPARK_SIZE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = tint.lightened(0.3)
	quad.material = material
	sparks.mesh = quad
	return sparks
