class_name StageBackdrop3D
extends RefCounted
## The world around the 3D cut-in stage: a graded sky dome, a ring of far hills
## and a few clouds, all vertex-coloured, unlit and out of the fog, so they read
## as the distance the fog fades the ground into. Built once per stage.

const SKY_TOP := Color("#3f73b8")
const SKY_MID := Color("#86b5e0")
const HORIZON := Color("#d4e6f2")
const HILL_NEAR := Color("#8fb0bf")
const HILL_FAR := Color("#b3cad8")
const CLOUD := Color("#f6f8fb")
const CLOUD_SHADE := Color("#d9e3ee")
const DOME_RADIUS := 170.0
const DOME_RINGS := 18
const DOME_SEGMENTS := 32
const HILLS := 40
const CLOUDS := 9


## The dome, the hills and the clouds as one node.
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Backdrop"
	var dome := MeshInstance3D.new()
	dome.mesh = _dome()
	dome.material_override = _unlit(true)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dome)
	var st := MeshKit.begin()
	_hills(st)
	_clouds(st)
	var far := MeshInstance3D.new()
	far.mesh = st.commit()
	far.material_override = _unlit(false)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(far)
	return root


## The sky's colour at `rise` (0 at the horizon, 1 overhead).
static func sky_at(rise: float) -> Color:
	var r := clampf(rise, 0.0, 1.0)
	if r < 0.25:
		return HORIZON.lerp(SKY_MID, r / 0.25)
	return SKY_MID.lerp(SKY_TOP, (r - 0.25) / 0.75)


static func _unlit(inside: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.disable_fog = true
	if inside:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## A hemisphere and a skirt below the horizon, graded by height per vertex so
## the sky is smooth rather than banded.
static func _dome() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in DOME_RINGS:
		var a0 := _ring_angle(r)
		var a1 := _ring_angle(r + 1)
		for s in DOME_SEGMENTS:
			var t0 := TAU * float(s) / DOME_SEGMENTS
			var t1 := TAU * float(s + 1) / DOME_SEGMENTS
			var p00 := _dome_point(a0, t0)
			var p01 := _dome_point(a0, t1)
			var p10 := _dome_point(a1, t0)
			var p11 := _dome_point(a1, t1)
			for p in [p00, p10, p11, p00, p11, p01]:
				st.set_color(sky_at((p as Vector3).y / DOME_RADIUS))
				st.add_vertex(p)
	return st.commit()


## From a little below the horizon (the skirt the ground's apron meets) to the
## zenith.
static func _ring_angle(ring: int) -> float:
	return lerpf(-0.12, PI / 2.0, float(ring) / DOME_RINGS)


static func _dome_point(elevation: float, turn: float) -> Vector3:
	var flat := cos(elevation) * DOME_RADIUS
	return Vector3(cos(turn) * flat, sin(elevation) * DOME_RADIUS, sin(turn) * flat)


## Two rings of low peaks, the nearer darker, spaced round the stage by hash so
## no two stages' horizons are one repeated shape — but every stage's the same.
static func _hills(st: SurfaceTool) -> void:
	for i in HILLS:
		var far := i % 2 == 0
		var turn := TAU * (float(i) + SquadFormation3D.scatter(i, 1) * 0.6) / HILLS
		var reach := (150.0 if far else 120.0) + SquadFormation3D.scatter(i, 2) * 15.0
		var foot := Vector3(cos(turn) * reach, -0.5, sin(turn) * reach)
		var wide := 9.0 + SquadFormation3D.scatter(i, 3) * 12.0
		var tall := 3.0 + SquadFormation3D.scatter(i, 4) * (7.0 if far else 4.0)
		var colour := HILL_FAR if far else HILL_NEAR
		MeshKit.column(
			st, MeshKit.at(foot, rad_to_deg(turn) * 3.0), wide, wide * 0.08, tall, 7, colour
		)


## Flattened puffs high over the far hills, each three lobes, lit from above by
## their own two tones.
static func _clouds(st: SurfaceTool) -> void:
	for i in CLOUDS:
		var turn := TAU * (float(i) + SquadFormation3D.scatter(i, 5)) / CLOUDS
		var reach := 90.0 + SquadFormation3D.scatter(i, 6) * 40.0
		var at := Vector3(
			cos(turn) * reach, 22.0 + SquadFormation3D.scatter(i, 7) * 14.0, sin(turn) * reach
		)
		var size := 5.0 + SquadFormation3D.scatter(i, 8) * 5.0
		for lobe in 3:
			var offset := Vector3((lobe - 1) * size * 0.9, (1 - absi(lobe - 1)) * size * 0.35, 0.0)
			var squash := Basis.from_scale(Vector3(1.4, 0.55, 0.9))
			var xf := Transform3D(
				Basis(Vector3.UP, turn) * squash, at + offset.rotated(Vector3.UP, -turn)
			)
			MeshKit.ball(
				st,
				xf,
				size * (1.0 if lobe == 1 else 0.75),
				3,
				7,
				CLOUD if lobe == 1 else CLOUD_SHADE
			)
