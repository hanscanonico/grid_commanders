class_name CutinFx3D
extends Node3D
## The 3D cut-in's effects, redrawn whole every frame: flashes, rounds in the
## air, bursts, smoke, chips, sparks and the kill blast are appended here as
## low-poly primitives between `begin` and `commit`, and nothing survives a
## frame. So every effect is a pure function of the clock that asked for it —
## no particle system, no tween, no state — and a skip or a posed still lands
## on exactly the frame the clock names.
##
## Four layers: `solid` is lit like the models (shells, darts, chips); `smoke`
## and `fire` are soft balls whose rims melt away (blended, and added); `glow`
## is the hard-edged added light of streaks, stars and rings. Two lights ride
## with them, one per side, set per frame.

const LIGHT_RANGE := 4.5
const SOFT_SHADER := preload("res://scenes/board3d/cutin/cutin_soft_3d.gdshader")
const FIRE_SHADER := preload("res://scenes/board3d/cutin/cutin_fire_3d.gdshader")
## A soft ball's facets: enough that its melting edge reads round.
const SOFT_RINGS := 6
const SOFT_SEGMENTS := 12

var _solid: MeshInstance3D
var _smoke: MeshInstance3D
var _glow: MeshInstance3D
var _fire: MeshInstance3D
var _fire_st: SurfaceTool
var _solid_st: SurfaceTool
var _smoke_st: SurfaceTool
var _glow_st: SurfaceTool
var _counts := PackedInt32Array([0, 0, 0, 0])
var _lights: Array[OmniLight3D] = []
var _eye := Vector3.ZERO


func _init() -> void:
	name = "CutinFx3D"
	_solid = _layer(MeshKit.vertex_material())
	_smoke = _layer(_soft(false, 1.4))
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	glow.vertex_color_is_srgb = true
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.disable_fog = true
	_glow = _layer(glow)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fire = _layer(_soft(true, 2.2))
	_fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 2:
		var light := OmniLight3D.new()
		light.omni_range = LIGHT_RANGE
		light.light_energy = 0.0
		light.visible = false
		add_child(light)
		_lights.append(light)


## Opens a frame seen from `eye` (a stage point), which billboards face.
func begin(eye: Vector3) -> void:
	_eye = eye
	_solid_st = MeshKit.begin()
	_smoke_st = MeshKit.begin()
	_glow_st = MeshKit.begin()
	_fire_st = MeshKit.begin()
	_counts = PackedInt32Array([0, 0, 0, 0])
	for light in _lights:
		light.visible = false


## Closes the frame and shows what it drew.
func commit() -> void:
	_solid.mesh = _solid_st.commit() if _counts[0] > 0 else null
	_smoke.mesh = _smoke_st.commit() if _counts[1] > 0 else null
	_glow.mesh = _glow_st.commit() if _counts[2] > 0 else null
	_fire.mesh = _fire_st.commit() if _counts[3] > 0 else null


# --- primitives --------------------------------------------------------------


## A soft ball of fire or light, added over what is behind it and melting
## away at its rim.
func glow_ball(at: Vector3, radius: float, colour: Color) -> void:
	if radius <= 0.001 or colour.a <= 0.002:
		return
	_soft_ball(_fire_st, at, radius, colour)
	_counts[3] += 1


## A puff of smoke or dust, lit by the scene.
func smoke_ball(at: Vector3, radius: float, colour: Color) -> void:
	if radius <= 0.001 or colour.a <= 0.002:
		return
	_soft_ball(_smoke_st, at, radius, colour)
	_counts[1] += 1


## A solid box turned to lie along `dir`: a shell, a chip, a torpedo's body.
func solid_box(at: Vector3, dir: Vector3, size: Vector3, colour: Color) -> void:
	MeshKit.box(_solid_st, Transform3D(_along(dir), at), size, colour)
	_counts[0] += 1


## A dart: a body along `dir` with a coloured nose, for a rocket or a bomb.
func dart(
	at: Vector3, dir: Vector3, length: float, radius: float, body: Color, nose: Color
) -> void:
	var basis := _along(dir)
	MeshKit.tube(_solid_st, Transform3D(basis, at), radius, length, 6, body)
	var tip := Transform3D(basis * Basis(Vector3.BACK, -PI / 2.0), at + basis.x * length * 0.5)
	MeshKit.column(_solid_st, tip, radius, 0.0, radius * 2.5, 6, nose)
	_counts[0] += 1


## A streak of light from `from` to `to`, turned to face the lens: a tracer,
## a trail, a spark.
func streak(from: Vector3, to: Vector3, width: float, colour: Color) -> void:
	var along := to - from
	if along.length() < 0.0005 or colour.a <= 0.002:
		return
	var facing := (_eye - (from + to) * 0.5).normalized()
	var side := along.cross(facing).normalized() * width * 0.5
	MeshKit.quad(_glow_st, from - side, to - side, to + side, from + side, colour)
	_counts[2] += 1


## A starburst of `points` spikes about `at`, facing the lens, pointed most
## along `dir`: a muzzle flash.
func star(at: Vector3, dir: Vector3, radius: float, colour: Color, points: int = 6) -> void:
	if radius <= 0.001:
		return
	var facing := (_eye - at).normalized()
	var right := dir.cross(facing).normalized()
	if right.length() < 0.5:
		right = facing.cross(Vector3.UP).normalized()
	var up := facing.cross(right).normalized()
	var forward := dir.normalized()
	for i in points:
		var turn := TAU * float(i) / points
		var spoke := (right * cos(turn) + up * sin(turn)).normalized()
		var reach := radius * (1.0 + 0.9 * maxf(0.0, spoke.dot(forward)))
		var tip := at + spoke * reach
		var half := (right * cos(turn + PI / 2.0) + up * sin(turn + PI / 2.0)) * radius * 0.22
		MeshKit.tri(_glow_st, at + half, tip, at - half, colour)
	_counts[2] += 1


## A flat ring lying on the ground at `at`: a shockwave, a splash's rim.
func ring(at: Vector3, radius: float, width: float, colour: Color) -> void:
	if radius <= 0.001 or colour.a <= 0.002:
		return
	var inner := maxf(radius - width, 0.0)
	var segments := 20
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var o0 := Vector3(cos(a0), 0.0, sin(a0))
		var o1 := Vector3(cos(a1), 0.0, sin(a1))
		MeshKit.quad(
			_glow_st, at + o0 * inner, at + o1 * inner, at + o1 * radius, at + o0 * radius, colour
		)
	_counts[2] += 1


## A light at `at` for this frame: `index` 0 is the firing side's, 1 the
## receiving side's.
func light(index: int, at: Vector3, energy: float, colour: Color) -> void:
	if energy <= 0.01:
		return
	var lamp := _lights[index]
	lamp.visible = true
	lamp.position = at
	lamp.light_energy = energy
	lamp.light_color = colour


## A ball with smooth normals, so the soft shader's rim falls off evenly
## rather than facet by facet.
static func _soft_ball(st: SurfaceTool, at: Vector3, radius: float, colour: Color) -> void:
	for r in SOFT_RINGS:
		var a0 := PI * float(r) / SOFT_RINGS
		var a1 := PI * float(r + 1) / SOFT_RINGS
		for s in SOFT_SEGMENTS:
			var t0 := TAU * float(s) / SOFT_SEGMENTS
			var t1 := TAU * float(s + 1) / SOFT_SEGMENTS
			var n00 := _on_sphere(a0, t0)
			var n01 := _on_sphere(a0, t1)
			var n10 := _on_sphere(a1, t0)
			var n11 := _on_sphere(a1, t1)
			for n in [n00, n10, n11, n00, n11, n01]:
				st.set_color(colour)
				st.set_normal(n)
				st.add_vertex(at + (n as Vector3) * radius)


static func _on_sphere(down: float, turn: float) -> Vector3:
	return Vector3(sin(down) * cos(turn), cos(down), sin(down) * sin(turn))


static func _soft(additive: bool, softness: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FIRE_SHADER if additive else SOFT_SHADER
	material.set_shader_parameter(&"softness", softness)
	material.set_shader_parameter(&"top_light", 0.0 if additive else 0.55)
	if additive:
		material.render_priority = 1
	return material


func _layer(material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.material_override = material
	add_child(instance)
	return instance


## A basis whose +X runs along `dir`.
static func _along(dir: Vector3) -> Basis:
	var x := dir.normalized() if dir.length() > 0.0001 else Vector3.RIGHT
	var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	var z := x.cross(up).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)
