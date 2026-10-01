class_name CaptureRig3D
extends Node3D
## The capture's own dressing on the 3D cut-in stage, over the property the
## plot stands: the flagpole beside it with the owner's flag flying, and the
## flourishes a capture throws — dust off each mash, the building's jolt and its
## flip under a flash, the capturer's flag running up, confetti and two
## fireworks.
##
## Dumb in the `StageSquad3D` idiom: `pose` places everything as a pure function
## of the `CaptureBeats` sheet and one time, through `CaptureShot3D`, so a still
## posed at any moment is the same still every run. The dust, the confetti and
## the fireworks are the combat cut-in's own `CutinFx3D`, redrawn whole each
## frame. No particles, no tweens.
##
## Rig frame: the main building stands on the origin, its front toward +Z; the
## pole stands at its front right.

## The capture's subject is the building, so the plot's main one is blown up
## again past the combat backdrop's size, and its neighbours stood aside for it.
const GROW := 1.3
const NEIGHBOUR_GAP := 0.9
## The pole stands this far out from the pad's right edge, a share of the pad
## forward, and this far over the roof — low enough that the flag flies clear
## of the meter in the band's top right in every shot.
const POLE_OUT := 0.3
const POLE_FORWARD := 0.22
const POLE_OVER := 0.7
const PAD_HALF := 0.46
const POLE_RADIUS := 0.045
const FINIAL := Color("e8c35a")
const POLE := Color("c9ccd2")
## The flag: a cloth of strips hung off the pole, rippling as it flies. Its
## lowest run is a share of the pole.
const FLAG_SIZE := Vector2(1.2, 0.74)
const FLAG_STRIPS := 7
const FLAG_FOOT := 0.3
const FLAG_WAVE := 0.07
const FLAG_WAVE_RATE := 9.0
## How much the flip lights the building from within at its peak; the bloom is
## cubed, so the white-out is a blink rather than the whole flip.
const FLASH_ENERGY := 3.0
## The flip's white also lights the square, from over the roof.
const FLIP_LIGHT := 6.0
## Two puffs kicked out either side of each figure's feet as a mash lands.
const DUST := Color("efe6d2")
const DUST_REACH := 0.45
const DUST_SIZE := Vector2(0.08, 0.24)
const CONFETTI_SIZE := Vector3(0.18, 0.012, 0.12)
const SPARK_RADIUS := 0.13
const SPARK_TRAIL := 0.35

## The flag's top, and the middle of the roof — where the chips rise from and
## the confetti is thrown — both in the rig's frame.
var flag_top := Vector3.ZERO
var roof_top := Vector3.ZERO

var _terrain_id: StringName
var _before: CommanderVisuals.FactionTheme
var _after: CommanderVisuals.FactionTheme
var _buildings: Array[Node3D] = []
var _rest_scales: Array[Vector3] = []
var _pole_at := Vector3.ZERO
var _pole_height := 1.0
var _old_flag: Node3D
var _new_flag: Node3D
var _fx: CutinFx3D
## The confetti, rebuilt whole each frame like the fx but casting no shadow: a
## scrap in the air must not print a dark fleck on the roof below it.
var _confetti: MeshInstance3D


## Dresses `buildings` — the plot's, the main one first and standing on this
## rig's origin — as the property `terrain_id`, painted `before` and flipping to
## `after`.
func setup(
	terrain_id: StringName,
	buildings: Array[Node3D],
	before: CommanderVisuals.FactionTheme,
	after: CommanderVisuals.FactionTheme
) -> void:
	name = "CaptureRig3D"
	_terrain_id = terrain_id
	_buildings = buildings
	for building in _buildings:
		var body := building.get_node("Body") as MeshInstance3D
		MeshKit.flashable(body.material_override as StandardMaterial3D, Color.WHITE)
	_stand_buildings()
	_before = before
	_after = after
	_build_pole()
	_old_flag = _build_flag(before)
	_new_flag = _build_flag(after)
	_fx = CutinFx3D.new()
	add_child(_fx)
	_confetti = MeshInstance3D.new()
	_confetti.material_override = MeshKit.vertex_material()
	_confetti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_confetti)


## The main building's front at its foot, in the rig's frame — where the squad
## mashes.
func door() -> Vector3:
	return Vector3(0.0, 0.0, PAD_HALF * _main_scale())


## What a flag's strips draw with: the model material, seen from both sides.
static func flag_material() -> StandardMaterial3D:
	var material := MeshKit.vertex_material()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _main_scale() -> float:
	return _rest_scales[0].x if not _rest_scales.is_empty() else 1.0


## Grows the main building and walks its neighbours out of its way.
func _stand_buildings() -> void:
	if _buildings.is_empty():
		return
	var main := _buildings[0]
	var grown := PAD_HALF * main.scale.x * (GROW - 1.0)
	for i in _buildings.size():
		var building := _buildings[i]
		if i == 0:
			building.scale *= GROW
		else:
			var away := signf(building.position.x - main.position.x)
			building.position.x += away * (grown + NEIGHBOUR_GAP)
		_rest_scales.append(building.scale)


## Everything at time `t` of a capture laid out on `beats`. The buildings jolt
## on each landing, swell and flash through the flip, and wear the capturer's
## colours from its peak. `feet` are where the squad's figures stand, for the
## dust a mash kicks up, and `eye` is where the lens is; both in the rig's frame.
func pose(
	beats: CaptureBeats, captured: bool, t: float, feet: PackedVector3Array, eye: Vector3
) -> void:
	var flipped := CaptureShot3D.flipped(beats, captured, t)
	var mesh := PropertyModels3D.mesh_for(_terrain_id, _after if flipped else _before)
	var glow := pow(CaptureShot3D.bloom(beats, captured, t), 3.0)
	var jolt := CaptureShot3D.building_scale(beats, captured, t)
	for i in _buildings.size():
		var body := _buildings[i].get_node("Body") as MeshInstance3D
		body.mesh = mesh
		_buildings[i].scale = jolt * _rest_scales[i]
		var material := body.material_override as StandardMaterial3D
		material.emission_energy_multiplier = FLASH_ENERGY * glow
	_fly(_old_flag, CaptureShot3D.old_flag(beats, captured, t), t)
	_fly(_new_flag, CaptureShot3D.new_flag(beats, captured, t), t)
	_fx.begin(eye)
	_draw_dust(beats, t, feet)
	_draw_confetti(beats, captured, t)
	_draw_fireworks(beats, captured, t)
	var bloom := CaptureShot3D.bloom(beats, captured, t)
	_fx.light(0, roof_top + Vector3.UP * 1.5 + Vector3.BACK * 2.0, bloom * FLIP_LIGHT, Color.WHITE)
	_fx.commit()


func _build_pole() -> void:
	var st := MeshKit.begin()
	var size := _main_scale()
	var roof := PropertyModels3D.mesh_for(_terrain_id, _before).get_aabb().end.y * size
	_pole_height = roof + POLE_OVER
	roof_top = Vector3(0.0, roof, 0.0)
	_pole_at = Vector3(PAD_HALF * size + POLE_OUT, 0.0, POLE_FORWARD * size)
	MeshKit.column(st, MeshKit.at(Vector3.ZERO), 0.16, 0.13, 0.1, 8, POLE)
	MeshKit.column(
		st, MeshKit.at(Vector3.ZERO), POLE_RADIUS, POLE_RADIUS * 0.8, _pole_height, 6, POLE
	)
	MeshKit.ball(st, MeshKit.at(Vector3(0.0, _pole_height + 0.06, 0.0)), 0.09, 3, 8, FINIAL)
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	pole.mesh = st.commit()
	pole.material_override = MeshKit.vertex_material()
	pole.position = _pole_at
	add_child(pole)
	flag_top = _pole_at + Vector3(FLAG_SIZE.x * 0.5, _pole_height, 0.0)


## A flag of `theme`'s colours: its field, a light band and a dark hem, cut into
## strips so it can ripple.
func _build_flag(theme: CommanderVisuals.FactionTheme) -> Node3D:
	var flag := Node3D.new()
	flag.name = "Flag"
	add_child(flag)
	var material := flag_material()
	var strip_w := FLAG_SIZE.x / FLAG_STRIPS
	for i in FLAG_STRIPS:
		var st := MeshKit.begin()
		var h := FLAG_SIZE.y
		MeshKit.box(st, MeshKit.at(Vector3(0, 0, 0)), Vector3(strip_w, h, 0.012), theme.color)
		MeshKit.box(
			st,
			MeshKit.at(Vector3(0, h * 0.08, 0)),
			Vector3(strip_w, h * 0.2, 0.016),
			theme.color_light
		)
		MeshKit.box(
			st,
			MeshKit.at(Vector3(0, -h * 0.42, 0)),
			Vector3(strip_w, h * 0.1, 0.016),
			theme.color_dark
		)
		var strip := MeshInstance3D.new()
		strip.mesh = st.commit()
		strip.material_override = material
		strip.position = Vector3(strip_w * (i + 0.5), 0.0, 0.0)
		flag.add_child(strip)
	return flag


## Hoists `flag` to `height` of its run, 1 at the top, and ripples it off the
## clock; out of sight at the foot of its run.
func _fly(flag: Node3D, height: float, t: float) -> void:
	flag.visible = height > 0.01
	var top := _pole_height - FLAG_SIZE.y * 0.5 - 0.04
	var foot := _pole_height * FLAG_FOOT
	flag.position = _pole_at + Vector3(0.0, lerpf(foot, top, height), 0.0)
	var strips := flag.get_children()
	for i in strips.size():
		var strip := strips[i] as Node3D
		var reach := float(i + 1) / FLAG_STRIPS
		var phase := t * FLAG_WAVE_RATE - i * 0.8
		strip.position.z = sin(phase) * FLAG_WAVE * reach
		strip.position.y = cos(phase * 0.7) * FLAG_WAVE * 0.35 * reach
		strip.rotation.y = cos(phase) * 0.35 * reach


## The dust of whichever mash landed last, rolling out from each figure's feet.
func _draw_dust(beats: CaptureBeats, t: float, feet: PackedVector3Array) -> void:
	var p := 0.0
	for i in beats.lands.size():
		p = maxf(p, CaptureShot3D.dust(beats, i, t))
	if p <= 0.0:
		return
	var spread := 1.0 - pow(1.0 - p, 2.0)
	var colour := Color(DUST, 0.6 * pow(1.0 - p, 1.5))
	var radius := lerpf(DUST_SIZE.x, DUST_SIZE.y, spread)
	for foot in feet:
		for out: float in [-1.0, 1.0]:
			var at := foot + Vector3(out, 0.0, 0.35) * DUST_REACH * spread
			_fx.smoke_ball(at + Vector3.UP * (radius * 0.6), radius, colour)


## Confetti thrown out of the roof at the flip's peak, tumbling as it falls and
## shrinking away at the end of its run.
func _draw_confetti(beats: CaptureBeats, captured: bool, t: float) -> void:
	var life := CaptureShot3D.confetti_life(beats, captured, t)
	_confetti.mesh = null
	if life <= 0.0:
		return
	var colours: Array[Color] = [
		_after.color, CutscenePalette.GOLD, _after.color_light, Color.WHITE
	]
	var since := t - CaptureShot3D.flip_at(beats)
	var st := MeshKit.begin()
	for i in CaptureShot3D.CONFETTI:
		var at := roof_top + CaptureShot3D.confetti_offset(i, since)
		var spin := since * (5.0 + i % 5) + i * 0.7
		var tumble := Basis.from_euler(Vector3(spin, spin * 1.3, i * 0.9))
		MeshKit.box(st, Transform3D(tumble, at), CONFETTI_SIZE * life, colours[i % colours.size()])
	_confetti.mesh = st.commit()


## Two firework rings popping over the building behind the banner, each spark
## trailing back toward its burst. The sparks are blended rather than added:
## light added over the pale sky washes out to white, and these are to read in
## the capturer's colours.
func _draw_fireworks(beats: CaptureBeats, captured: bool, t: float) -> void:
	for ring in CaptureShot3D.FIREWORKS.size():
		var p := CaptureShot3D.firework(beats, captured, ring, t)
		if p <= 0.0:
			continue
		var centre := CaptureShot3D.FIREWORKS[ring]
		var fade := 1.0 - p * p
		for i in CaptureShot3D.FIREWORK_SPARKS:
			var offset := CaptureShot3D.spark_offset(ring, i, p)
			var tint := _after.color if i % 2 == 0 else _after.color_light
			var at := centre + offset
			_fx.smoke_ball(at, SPARK_RADIUS * (1.0 - p * 0.6), Color(tint, fade))
			_fx.streak(
				at,
				at - offset.normalized() * SPARK_TRAIL * fade,
				0.04,
				Color(CutscenePalette.GOLD, fade * 0.3)
			)
