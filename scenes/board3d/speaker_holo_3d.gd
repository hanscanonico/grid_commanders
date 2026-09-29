class_name SpeakerHolo3D
extends Node3D
## A general's portrait projected over the cell they speak from: a disc of light
## on the ground, a beam widening up out of it, and the portrait on a screen at
## the top, turned to face the lens.
##
## Posed, never self-timed: the cinematic hands it a `presence` from 0 (dark) to
## 1 (fully on) and its own clock each frame, so it holds no tween and a skip
## lands it wherever the clock says.

const SCREEN_SHADER := preload("res://scenes/board3d/holo_screen_3d.gdshader")
const GLOW_SHADER := preload("res://scenes/board3d/holo_glow_3d.gdshader")
## The glow shader's shapes (`holo_glow_3d.gdshader`).
const GLOW_BEAM := 0
const GLOW_DISC := 1
const GLOW_RING := 2
## World units per portrait texel: the 110x134 bust stands about a cell tall.
const TEXEL := 0.0084
const DISC_RADIUS := 0.36
const BEAM_FOOT := 0.08
const BEAM_TOP := 0.46
const BOB := 0.03
const BOB_RATE := 1.6
## The light comes up over the first part of `presence` and the picture draws in
## over the rest, overlapping, so the screen seems to be switched on by its beam.
const LIGHT_SPAN := 0.45
const DRAW_FROM := 0.3

var _screen: MeshInstance3D
var _screen_material: ShaderMaterial
var _beam: MeshInstance3D
var _beam_material: ShaderMaterial
var _disc_material: ShaderMaterial
var _screen_h := 0.0


## A projector for `commander`, tinted `tint`, `size` times the ordinary screen.
## `off_board` marks a voice with no seat on this board, which comes in over a
## worse line.
static func make(
	commander: CommanderType, tint: Color, size: float, off_board: bool
) -> SpeakerHolo3D:
	var holo := SpeakerHolo3D.new()
	holo.name = "SpeakerHolo3D"
	holo._build(CommanderVisuals.portrait_for(commander), tint, size, off_board)
	holo.pose(0.0, 0.0)
	return holo


func _build(portrait: Texture2D, tint: Color, size: float, off_board: bool) -> void:
	var art := Vector2(CommanderVisuals.PORTRAIT_SIZE)
	var quad := QuadMesh.new()
	quad.size = art * TEXEL * size
	_screen_h = quad.size.y
	_screen_material = ShaderMaterial.new()
	_screen_material.shader = SCREEN_SHADER
	_screen_material.set_shader_parameter(&"portrait", portrait)
	_screen_material.set_shader_parameter(&"tint", tint)
	_screen_material.set_shader_parameter(&"texels", art)
	_screen_material.set_shader_parameter(&"static_noise", 1.0 if off_board else 0.0)
	_screen = _mesh(quad, _screen_material)

	var cone := CylinderMesh.new()
	cone.top_radius = BEAM_TOP * size
	cone.bottom_radius = BEAM_FOOT
	cone.height = CinemaShot3D.HOLO_FLOAT
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 24
	_beam_material = glow_material(GLOW_BEAM, tint, cone.height)
	_beam = _mesh(cone, _beam_material)

	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * DISC_RADIUS * 2.0
	_disc_material = glow_material(GLOW_DISC, tint, DISC_RADIUS)
	_mesh(plane, _disc_material).position.y = 0.03


## Stands the projector `presence` of the way on, at `clock` seconds.
func pose(presence: float, clock: float) -> void:
	visible = presence > 0.0
	var light := clampf(presence / LIGHT_SPAN, 0.0, 1.0)
	var drawn := clampf((presence - DRAW_FROM) / (1.0 - DRAW_FROM), 0.0, 1.0)
	var rise := CinemaShot3D.HOLO_FLOAT
	_beam.scale = Vector3(1.0, maxf(light, 0.001), 1.0)
	_beam.position.y = rise * light / 2.0
	var bob := sin(clock * BOB_RATE) * BOB
	_screen.position.y = rise + _screen_h / 2.0 + bob
	_screen.visible = drawn > 0.0
	_screen_material.set_shader_parameter(&"reveal", drawn)
	_screen_material.set_shader_parameter(&"fade", clampf(presence * 1.6, 0.0, 1.0))
	for material: ShaderMaterial in [_screen_material, _beam_material, _disc_material]:
		material.set_shader_parameter(&"clock", clock)
	_beam_material.set_shader_parameter(&"strength", light)
	_disc_material.set_shader_parameter(&"strength", light)


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


## Added light in `tint`, drawn as `shape` over a mesh `extent` in size — the
## beam's height, or a plane's half-width.
static func glow_material(shape: int, tint: Color, extent: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter(&"shape", shape)
	material.set_shader_parameter(&"tint", tint)
	material.set_shader_parameter(&"extent", extent)
	return material
