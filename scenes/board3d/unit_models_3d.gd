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
## barrel, not detail.

const METAL := Color("5b6068")
const TRACK := Color("2e3136")
const GLASS := Color("a9d3ee")
const GLASS_DARK := Color("27384a")
const SKIN := Color("e3b58e")
const MISSILE := Color("e9e6df")
const DECK := Color("b9b3a3")

## Where a spinning part's pivot sits on the body, for the types that have one.
const ROTOR_HUB: Dictionary[StringName, Vector3] = {
	&"b_copter": Vector3(0.0, 0.225, 0.0),
	&"t_copter": Vector3(-0.02, 0.29, 0.0),
}
## A foot unit's model is three soldiers; a cut-in squad posts them one per
## figure instead, blown up to stand beside a vehicle.
const LONE_SOLDIER_SCALE := 2.0

static var _meshes: Dictionary[String, ArrayMesh] = {}
static var _rotors: Dictionary[StringName, ArrayMesh] = {}
static var _warned: Dictionary[StringName, bool] = {}


static func mesh_for(type_id: StringName, theme: CommanderVisuals.FactionTheme) -> ArrayMesh:
	var key := "%s|%s" % [type_id, theme.key]
	if not _meshes.has(key):
		var st := MeshKit.begin()
		_body(st, type_id, theme)
		_meshes[key] = st.commit()
	return _meshes[key]


## One figure of a cut-in squad: a foot unit's lone soldier, any other unit's
## whole body.
static func figure_mesh_for(type_id: StringName, theme: CommanderVisuals.FactionTheme) -> ArrayMesh:
	if type_id != &"infantry" and type_id != &"mech":
		return mesh_for(type_id, theme)
	var key := "%s|%s|lone" % [type_id, theme.key]
	if not _meshes.has(key):
		var st := MeshKit.begin()
		_soldier(st, Vector3.ZERO, LONE_SOLDIER_SCALE, theme, type_id == &"mech")
		_meshes[key] = st.commit()
	return _meshes[key]


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
	if ROTOR_HUB.has(type_id):
		_part(root, "Rotor", _rotor_mesh(type_id), material, ROTOR_HUB[type_id])
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


static func _body(st: SurfaceTool, type_id: StringName, t: CommanderVisuals.FactionTheme) -> void:
	match type_id:
		&"infantry":
			_infantry(st, t)
		&"mech":
			_mech(st, t)
		&"recon":
			_recon(st, t)
		&"apc":
			_apc(st, t)
		&"tank":
			_tank(st, t)
		&"md_tank":
			_md_tank(st, t)
		&"artillery":
			_artillery(st, t)
		&"rockets":
			_rockets(st, t)
		&"anti_air":
			_anti_air(st, t)
		&"missiles":
			_missiles(st, t)
		&"fighter":
			_fighter(st, t)
		&"bomber":
			_bomber(st, t)
		&"b_copter":
			_b_copter(st, t)
		&"t_copter":
			_t_copter(st, t)
		&"battleship":
			_battleship(st, t)
		&"cruiser":
			_cruiser(st, t)
		&"lander":
			_lander(st, t)
		&"sub":
			_sub(st, t)
		_:
			if not _warned.has(type_id):
				_warned[type_id] = true
				push_warning("UnitModels3D: no model for unit type '%s'" % type_id)
			MeshKit.block(st, MeshKit.at(Vector3.ZERO), Vector3(0.4, 0.3, 0.4), t.color)


# --- shared shapes ---------------------------------------------------------


## A convex polygon, fan-triangulated and turned to face `outward` whatever
## order its corners came in.
static func _face(st: SurfaceTool, pts: Array[Vector3], outward: Vector3, color: Color) -> void:
	var normal := (pts[1] - pts[0]).cross(pts[2] - pts[0])
	if normal.dot(outward) < 0.0:
		pts.reverse()
	for i in range(1, pts.size() - 1):
		MeshKit.tri(st, pts[0], pts[i], pts[i + 1], color)


## A solid between two convex outlines of equal corner count, `low` at height
## `low_y` and `high` at `high_y`; outlines are (x, z) in the frame of `xf`.
static func _loft(
	st: SurfaceTool,
	xf: Transform3D,
	low: PackedVector2Array,
	low_y: float,
	high: PackedVector2Array,
	high_y: float,
	color: Color
) -> void:
	var lows: Array[Vector3] = []
	var highs: Array[Vector3] = []
	var centre := Vector3.ZERO
	for i in low.size():
		lows.append(xf * Vector3(low[i].x, low_y, low[i].y))
		highs.append(xf * Vector3(high[i].x, high_y, high[i].y))
		centre += lows[i] + highs[i]
	centre /= float(low.size() * 2)
	var up := (xf.basis * Vector3.UP).normalized()
	_face(st, highs.duplicate(), up, color)
	_face(st, lows.duplicate(), -up, color)
	for i in low.size():
		var j := (i + 1) % low.size()
		var side: Array[Vector3] = [lows[i], lows[j], highs[j], highs[i]]
		var mid := (lows[i] + lows[j] + highs[i] + highs[j]) / 4.0
		_face(st, side, mid - centre, color)


static func _slab(
	st: SurfaceTool, xf: Transform3D, outline: PackedVector2Array, y0: float, y1: float, c: Color
) -> void:
	_loft(st, xf, outline, y0, outline, y1, c)


## A side profile — an (x, y) outline — extruded across Z from `z0` to `z1`.
static func _profile(
	st: SurfaceTool, outline: PackedVector2Array, z0: float, z1: float, c: Color
) -> void:
	var flipped := PackedVector2Array()
	for p in outline:
		flipped.append(Vector2(p.x, -p.y))
	_slab(st, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO), flipped, z0, z1, c)


static func _rect(x0: float, x1: float, z0: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## A frame at `pos` pitched `deg` nose-up about Z: +X swings toward +Y.
static func _pitch(pos: Vector3, deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, deg_to_rad(deg)), pos)


## A tube running `length` along the frame's +X from its origin.
static func _barrel(st: SurfaceTool, xf: Transform3D, length: float, r: float, c: Color) -> void:
	MeshKit.tube(st, xf * Transform3D(Basis.IDENTITY, Vector3(length / 2.0, 0, 0)), r, length, 6, c)


## A cone lying along +X, its base at the frame's origin.
static func _nose(
	st: SurfaceTool, xf: Transform3D, r: float, length: float, segments: int, c: Color
) -> void:
	MeshKit.column(
		st, xf * Transform3D(Basis(Vector3.BACK, -PI / 2.0)), r, 0.0, length, segments, c
	)


static func _wheel(st: SurfaceTool, pos: Vector3, r: float, width: float) -> void:
	MeshKit.tube(st, MeshKit.at(pos, 90), r, width, 8, TRACK)
	MeshKit.tube(st, MeshKit.at(pos, 90), r * 0.45, width + 0.012, 6, METAL)


## Two tracks under a hull, with road-wheel hubs and a team-coloured guard.
static func _tracks(
	st: SurfaceTool,
	length: float,
	height: float,
	width: float,
	gap: float,
	t: CommanderVisuals.FactionTheme
) -> void:
	var l := length / 2.0
	var outline := PackedVector2Array(
		[
			Vector2(-l + height * 0.45, 0),
			Vector2(l - height * 0.45, 0),
			Vector2(l, height * 0.55),
			Vector2(l - height * 0.2, height),
			Vector2(-l + height * 0.2, height),
			Vector2(-l, height * 0.55),
		]
	)
	for side: float in [-1.0, 1.0]:
		var z := side * gap
		_profile(st, outline, z - width / 2.0, z + width / 2.0, TRACK)
		for i in 4:
			var x := lerpf(-l + height * 0.55, l - height * 0.55, float(i) / 3.0)
			var hub := Vector3(x, height * 0.45, side * (gap + width / 2.0))
			MeshKit.tube(st, MeshKit.at(hub, 90), height * 0.3, 0.016, 6, METAL)
		var guard := Vector3(0, height + 0.012, z)
		MeshKit.box(
			st, MeshKit.at(guard), Vector3(length * 0.96, 0.024, width + 0.03), t.color_dark
		)


## A six-wheeled truck: chassis, wheels and a cab at the front. The launcher
## trucks differ only in what rides the flatbed behind the cab.
static func _truck(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	for x in [-0.27, -0.11, 0.25]:
		for z in [-0.2, 0.2]:
			_wheel(st, Vector3(x, 0.075, z), 0.075, 0.07)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.07, 0)), Vector3(0.78, 0.06, 0.3), t.color_dark)
	var cab_low := _rect(0.14, 0.4, -0.17, 0.17)
	var cab_high := _rect(0.14, 0.31, -0.15, 0.15)
	_loft(st, Transform3D.IDENTITY, cab_low, 0.13, cab_high, 0.28, t.color)
	var shield := MeshKit.at(Vector3(0.36, 0.215, 0)) * Transform3D(Basis(Vector3.BACK, 0.5))
	MeshKit.box(st, shield, Vector3(0.012, 0.08, 0.26), GLASS_DARK)
	MeshKit.block(st, MeshKit.at(Vector3(0.36, 0.1, 0)), Vector3(0.1, 0.04, 0.32), t.color_light)


# --- infantry ----------------------------------------------------------------


static func _soldier(
	st: SurfaceTool, pos: Vector3, s: float, t: CommanderVisuals.FactionTheme, heavy: bool
) -> void:
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * s), pos)
	for z in [-0.022, 0.022]:
		MeshKit.block(st, xf * MeshKit.at(Vector3(0, 0, z)), Vector3(0.045, 0.08, 0.034), TRACK)
	MeshKit.block(st, xf * MeshKit.at(Vector3(0, 0.075, 0)), Vector3(0.075, 0.1, 0.1), t.color)
	for z in [-0.062, 0.062]:
		MeshKit.block(
			st, xf * MeshKit.at(Vector3(0.01, 0.1, z)), Vector3(0.04, 0.07, 0.03), t.color
		)
	var pack := Vector3(0.05, 0.08, 0.09) if heavy else Vector3(0.035, 0.07, 0.07)
	MeshKit.block(st, xf * MeshKit.at(Vector3(-0.05, 0.09, 0)), pack, t.color_dark)
	MeshKit.ball(st, xf * MeshKit.at(Vector3(0.012, 0.205, 0)), 0.036, 3, 6, SKIN)
	MeshKit.ball(st, xf * MeshKit.at(Vector3(-0.006, 0.222, 0)), 0.04, 3, 8, t.color_dark)
	MeshKit.block(
		st, xf * MeshKit.at(Vector3(0.0, 0.2, 0)), Vector3(0.1, 0.012, 0.09), t.color_dark
	)
	if heavy:
		var tube := xf * MeshKit.at(Vector3(-0.01, 0.2, 0.065))
		MeshKit.tube(st, tube, 0.026, 0.24, 6, t.color_light)
		MeshKit.tube(st, tube * MeshKit.at(Vector3(0.11, 0, 0)), 0.032, 0.03, 6, METAL)
	else:
		var rifle := xf * _pitch(Vector3(0.05, 0.13, 0.05), 20)
		MeshKit.box(st, rifle, Vector3(0.14, 0.02, 0.02), METAL)


static func _infantry(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	for pos in [Vector3(0.15, 0, 0), Vector3(-0.12, 0, -0.2), Vector3(-0.1, 0, 0.2)]:
		_soldier(st, pos, 1.3, t, false)


static func _mech(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	for pos in [Vector3(0.13, 0, -0.03), Vector3(-0.14, 0, -0.2), Vector3(-0.1, 0, 0.2)]:
		_soldier(st, pos, 1.4, t, true)


# --- ground vehicles -------------------------------------------------------


static func _recon(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	for x in [-0.22, 0.22]:
		for z in [-0.215, 0.215]:
			_wheel(st, Vector3(x, 0.085, z), 0.085, 0.08)
	var low := _rect(-0.36, 0.38, -0.17, 0.17)
	var high := _rect(-0.3, 0.16, -0.14, 0.14)
	_loft(st, Transform3D.IDENTITY, low, 0.07, high, 0.22, t.color)
	var shield := MeshKit.at(Vector3(0.235, 0.18, 0)) * Transform3D(Basis(Vector3.BACK, 0.9))
	MeshKit.box(st, shield, Vector3(0.012, 0.09, 0.22), GLASS_DARK)
	for z in [-0.18, 0.18]:
		MeshKit.box(st, MeshKit.at(Vector3(0, 0.17, z)), Vector3(0.6, 0.02, 0.03), t.color_dark)
	MeshKit.column(st, MeshKit.at(Vector3(-0.08, 0.22, 0)), 0.075, 0.065, 0.04, 8, t.color_dark)
	_barrel(st, MeshKit.at(Vector3(-0.04, 0.245, 0)), 0.22, 0.014, METAL)
	MeshKit.block(st, MeshKit.at(Vector3(-0.1, 0.26, 0)), Vector3(0.06, 0.03, 0.05), METAL)


static func _apc(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_tracks(st, 0.72, 0.12, 0.15, 0.225, t)
	var low := _rect(-0.36, 0.36, -0.2, 0.2)
	var high := _rect(-0.34, 0.14, -0.18, 0.18)
	_loft(st, Transform3D.IDENTITY, low, 0.08, high, 0.31, t.color)
	for z in [-0.184, 0.184]:
		MeshKit.box(
			st, MeshKit.at(Vector3(-0.1, 0.22, z)), Vector3(0.44, 0.035, 0.012), t.color_light
		)
	MeshKit.box(st, MeshKit.at(Vector3(-0.35, 0.17, 0)), Vector3(0.015, 0.16, 0.2), TRACK)
	MeshKit.block(st, MeshKit.at(Vector3(-0.2, 0.31, 0)), Vector3(0.16, 0.025, 0.2), t.color_dark)
	MeshKit.block(st, MeshKit.at(Vector3(0.04, 0.31, 0)), Vector3(0.1, 0.03, 0.12), t.color_light)
	var slit := MeshKit.at(Vector3(0.25, 0.26, 0)) * Transform3D(Basis(Vector3.BACK, 1.1))
	MeshKit.box(st, slit, Vector3(0.012, 0.05, 0.26), GLASS_DARK)


static func _tank(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_tracks(st, 0.7, 0.13, 0.16, 0.23, t)
	var low := _rect(-0.33, 0.34, -0.2, 0.2)
	var high := _rect(-0.31, 0.2, -0.19, 0.19)
	_loft(st, Transform3D.IDENTITY, low, 0.09, high, 0.19, t.color)
	MeshKit.column(st, MeshKit.at(Vector3(-0.04, 0.19, 0)), 0.165, 0.165, 0.02, 8, t.color_dark)
	MeshKit.column(st, MeshKit.at(Vector3(-0.04, 0.21, 0)), 0.15, 0.115, 0.085, 8, t.color)
	MeshKit.column(
		st, MeshKit.at(Vector3(-0.08, 0.295, 0.04)), 0.045, 0.04, 0.025, 6, t.color_light
	)
	MeshKit.box(st, MeshKit.at(Vector3(0.1, 0.25, 0)), Vector3(0.05, 0.06, 0.08), t.color_dark)
	_barrel(st, MeshKit.at(Vector3(0.1, 0.25, 0)), 0.32, 0.027, METAL)


static func _md_tank(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_tracks(st, 0.8, 0.15, 0.18, 0.25, t)
	for side: float in [-1.0, 1.0]:
		var skirt := MeshKit.at(Vector3(0, 0.11, side * 0.345))
		MeshKit.box(st, skirt, Vector3(0.72, 0.08, 0.02), t.color_dark)
	var low := _rect(-0.38, 0.38, -0.24, 0.24)
	var high := _rect(-0.36, 0.24, -0.23, 0.23)
	_loft(st, Transform3D.IDENTITY, low, 0.1, high, 0.22, t.color)
	var t_low := PackedVector2Array(
		[
			Vector2(-0.24, -0.18),
			Vector2(0.1, -0.18),
			Vector2(0.17, -0.1),
			Vector2(0.17, 0.1),
			Vector2(0.1, 0.18),
			Vector2(-0.24, 0.18)
		]
	)
	var t_high := PackedVector2Array(
		[
			Vector2(-0.22, -0.15),
			Vector2(0.07, -0.15),
			Vector2(0.12, -0.08),
			Vector2(0.12, 0.08),
			Vector2(0.07, 0.15),
			Vector2(-0.22, 0.15)
		]
	)
	_loft(st, Transform3D.IDENTITY, t_low, 0.22, t_high, 0.33, t.color)
	MeshKit.block(st, MeshKit.at(Vector3(-0.28, 0.24, 0)), Vector3(0.08, 0.07, 0.26), t.color_dark)
	MeshKit.column(st, MeshKit.at(Vector3(-0.1, 0.33, -0.07)), 0.05, 0.045, 0.035, 6, t.color_light)
	_barrel(st, MeshKit.at(Vector3(0.12, 0.275, 0)), 0.29, 0.036, METAL)
	MeshKit.box(st, MeshKit.at(Vector3(0.39, 0.275, 0)), Vector3(0.055, 0.065, 0.075), TRACK)


static func _artillery(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_tracks(st, 0.66, 0.12, 0.14, 0.2, t)
	var low := _rect(-0.31, 0.32, -0.18, 0.18)
	var high := _rect(-0.3, 0.22, -0.17, 0.17)
	_loft(st, Transform3D.IDENTITY, low, 0.08, high, 0.17, t.color)
	for side: float in [-1.0, 1.0]:
		var cheek := PackedVector2Array(
			[Vector2(-0.24, 0.17), Vector2(0.02, 0.17), Vector2(-0.04, 0.29), Vector2(-0.2, 0.29)]
		)
		_profile(st, cheek, side * 0.13 - 0.02, side * 0.13 + 0.02, t.color)
	var shield := _pitch(Vector3(0.02, 0.17, 0), 60)
	MeshKit.box(
		st, shield * MeshKit.at(Vector3(0.07, 0, 0)), Vector3(0.14, 0.012, 0.3), t.color_dark
	)
	var gun := _pitch(Vector3(-0.12, 0.24, 0), 24)
	MeshKit.tube(st, gun * MeshKit.at(Vector3(0.02, 0, 0)), 0.06, 0.18, 8, t.color_dark)
	_barrel(st, gun, 0.34, 0.032, METAL)
	MeshKit.tube(st, gun * MeshKit.at(Vector3(0.31, 0, 0)), 0.042, 0.05, 6, TRACK)
	MeshKit.wedge(st, MeshKit.at(Vector3(-0.35, 0.02, 0), 180), Vector3(0.06, 0.08, 0.28), TRACK)


static func _anti_air(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_tracks(st, 0.68, 0.12, 0.15, 0.22, t)
	var low := _rect(-0.33, 0.33, -0.19, 0.19)
	var high := _rect(-0.31, 0.2, -0.18, 0.18)
	_loft(st, Transform3D.IDENTITY, low, 0.08, high, 0.18, t.color)
	var t_low := _rect(-0.17, 0.12, -0.12, 0.12)
	var t_high := _rect(-0.15, 0.07, -0.1, 0.1)
	_loft(st, Transform3D.IDENTITY, t_low, 0.18, t_high, 0.28, t.color_light)
	for z in [-0.155, 0.155]:
		MeshKit.box(st, MeshKit.at(Vector3(0.0, 0.25, z)), Vector3(0.1, 0.08, 0.05), t.color_dark)
		for dz in [-0.014, 0.014]:
			var pivot := _pitch(Vector3(0.03, 0.26, z + dz), 32)
			_barrel(st, pivot, 0.26, 0.012, METAL)
	MeshKit.column(st, MeshKit.at(Vector3(-0.13, 0.28, 0)), 0.012, 0.012, 0.05, 4, METAL)
	var dish := MeshKit.at(Vector3(-0.13, 0.34, 0)) * Transform3D(Basis(Vector3.BACK, -0.35))
	MeshKit.box(st, dish, Vector3(0.02, 0.07, 0.18), t.color_dark)


static func _rockets(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_truck(st, t)
	var pod := _pitch(Vector3(-0.35, 0.14, 0), 20)
	var size := Vector3(0.4, 0.13, 0.27)
	MeshKit.block(st, MeshKit.at(Vector3(0.0, 0.1, 0)), Vector3(0.06, 0.05, 0.12), METAL)
	MeshKit.box(st, pod * MeshKit.at(Vector3(size.x / 2.0, size.y / 2.0, 0)), size, t.color)
	for row in 2:
		for col in 3:
			var mouth := Vector3(size.x + 0.002, 0.035 + 0.06 * row, -0.08 + 0.08 * col)
			MeshKit.box(st, pod * MeshKit.at(mouth), Vector3(0.012, 0.045, 0.055), TRACK)
	var band := pod * MeshKit.at(Vector3(size.x * 0.3, size.y / 2.0, 0))
	MeshKit.box(st, band, Vector3(0.04, size.y + 0.01, size.z + 0.01), t.color_dark)


static func _missiles(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_truck(st, t)
	var rail := _pitch(Vector3(-0.37, 0.15, 0), 16)
	MeshKit.box(
		st, rail * MeshKit.at(Vector3(0.24, 0.01, 0)), Vector3(0.48, 0.03, 0.26), t.color_dark
	)
	MeshKit.block(st, MeshKit.at(Vector3(0.05, 0.1, 0)), Vector3(0.05, 0.1, 0.08), METAL)
	for z in [-0.075, 0.075]:
		var body := rail * MeshKit.at(Vector3(0.0, 0.07, z))
		_barrel(st, body, 0.42, 0.046, MISSILE)
		_nose(st, body * MeshKit.at(Vector3(0.42, 0, 0)), 0.046, 0.08, 6, t.color)
		MeshKit.tube(st, body * MeshKit.at(Vector3(0.12, 0, 0)), 0.05, 0.04, 6, t.color)
		MeshKit.box(st, body * MeshKit.at(Vector3(0.02, 0, 0)), Vector3(0.05, 0.13, 0.012), TRACK)


# --- aircraft ----------------------------------------------------------------


## One wing of a pair: `outline` is the +Z wing in (x, z), mirrored for -Z.
static func _wings(
	st: SurfaceTool, outline: PackedVector2Array, y: float, thick: float, c: Color
) -> void:
	var mirrored := PackedVector2Array()
	for p in outline:
		mirrored.append(Vector2(p.x, -p.y))
	_slab(st, Transform3D.IDENTITY, outline, y, y + thick, c)
	_slab(st, Transform3D.IDENTITY, mirrored, y, y + thick, c)


static func _fighter(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	MeshKit.tube(st, MeshKit.at(Vector3(-0.06, 0.075, 0)), 0.07, 0.56, 8, t.color)
	_nose(st, MeshKit.at(Vector3(0.22, 0.075, 0)), 0.07, 0.19, 8, t.color_light)
	var wing := PackedVector2Array(
		[Vector2(0.14, 0.05), Vector2(-0.2, 0.4), Vector2(-0.3, 0.4), Vector2(-0.3, 0.05)]
	)
	_wings(st, wing, 0.055, 0.025, t.color)
	var tip := PackedVector2Array(
		[Vector2(-0.19, 0.36), Vector2(-0.2, 0.4), Vector2(-0.3, 0.4), Vector2(-0.3, 0.36)]
	)
	_wings(st, tip, 0.056, 0.026, t.color_light)
	var tail := PackedVector2Array(
		[Vector2(-0.22, 0.11), Vector2(-0.34, 0.14), Vector2(-0.38, 0.14), Vector2(-0.34, 0.11)]
	)
	_wings(st, tail, 0.065, 0.02, t.color_dark)
	for z in [-0.055, 0.055]:
		var fin := PackedVector2Array(
			[Vector2(-0.2, 0.12), Vector2(-0.31, 0.12), Vector2(-0.37, 0.27), Vector2(-0.31, 0.27)]
		)
		_profile(st, fin, z - 0.01, z + 0.01, t.color_dark)
	var canopy := Transform3D(Basis.from_scale(Vector3(2.4, 1.0, 1.0)), Vector3(0.1, 0.13, 0))
	MeshKit.ball(st, canopy, 0.05, 3, 8, GLASS_DARK)
	MeshKit.tube(st, MeshKit.at(Vector3(-0.35, 0.075, 0)), 0.055, 0.04, 8, TRACK)


static func _bomber(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	MeshKit.tube(st, MeshKit.at(Vector3(-0.03, 0.1, 0)), 0.09, 0.6, 8, t.color)
	var nose := Transform3D(Basis.from_scale(Vector3(1.4, 1.0, 1.0)), Vector3(0.27, 0.1, 0))
	MeshKit.ball(st, nose, 0.09, 4, 8, t.color_light)
	MeshKit.ball(st, Transform3D(Basis.IDENTITY, Vector3(0.36, 0.11, 0)), 0.05, 3, 8, GLASS_DARK)
	var wing := PackedVector2Array(
		[Vector2(0.12, 0.06), Vector2(0.02, 0.42), Vector2(-0.08, 0.42), Vector2(-0.12, 0.06)]
	)
	_wings(st, wing, 0.1, 0.03, t.color)
	var band := PackedVector2Array(
		[Vector2(0.05, 0.25), Vector2(0.04, 0.3), Vector2(-0.1, 0.3), Vector2(-0.09, 0.25)]
	)
	_wings(st, band, 0.101, 0.031, t.color_dark)
	for z in [-0.3, -0.16, 0.16, 0.3]:
		var pod := MeshKit.at(Vector3(0.04 - absf(z) * 0.25, 0.08, z))
		MeshKit.tube(st, pod, 0.04, 0.18, 6, t.color_dark)
		MeshKit.tube(st, pod * MeshKit.at(Vector3(0.09, 0, 0)), 0.03, 0.02, 6, TRACK)
	var tail := PackedVector2Array(
		[Vector2(-0.26, 0.06), Vector2(-0.33, 0.2), Vector2(-0.39, 0.2), Vector2(-0.38, 0.06)]
	)
	_wings(st, tail, 0.12, 0.02, t.color)
	var fin := PackedVector2Array(
		[Vector2(-0.22, 0.15), Vector2(-0.34, 0.15), Vector2(-0.4, 0.3), Vector2(-0.33, 0.3)]
	)
	_profile(st, fin, -0.012, 0.012, t.color_dark)


static func _skids(st: SurfaceTool, half_gap: float, length: float) -> void:
	for z in [-half_gap, half_gap]:
		MeshKit.box(st, MeshKit.at(Vector3(0, 0.008, z)), Vector3(length, 0.016, 0.02), TRACK)
		for x in [-length * 0.3, length * 0.3]:
			MeshKit.box(
				st, MeshKit.at(Vector3(x, 0.03, z * 0.8)), Vector3(0.015, 0.05, 0.015), TRACK
			)


static func _b_copter(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_skids(st, 0.1, 0.34)
	var low := _rect(-0.14, 0.24, -0.065, 0.065)
	var high := _rect(-0.12, 0.1, -0.06, 0.06)
	_loft(st, Transform3D.IDENTITY, low, 0.04, high, 0.17, t.color)
	var canopy := Transform3D(Basis.from_scale(Vector3(2.6, 1.0, 1.0)), Vector3(0.12, 0.14, 0))
	MeshKit.ball(st, canopy, 0.055, 3, 8, GLASS_DARK)
	var boom := MeshKit.at(Vector3(-0.27, 0.13, 0))
	MeshKit.tube(st, boom, 0.028, 0.28, 6, t.color)
	var fin := PackedVector2Array(
		[Vector2(-0.34, 0.12), Vector2(-0.41, 0.12), Vector2(-0.41, 0.26), Vector2(-0.37, 0.26)]
	)
	_profile(st, fin, -0.01, 0.01, t.color_dark)
	MeshKit.box(st, MeshKit.at(Vector3(-0.39, 0.2, 0.02)), Vector3(0.02, 0.12, 0.008), TRACK)
	MeshKit.box(st, MeshKit.at(Vector3(-0.02, 0.09, 0)), Vector3(0.09, 0.016, 0.34), t.color_dark)
	for z in [-0.15, 0.15]:
		MeshKit.tube(st, MeshKit.at(Vector3(-0.01, 0.065, z)), 0.028, 0.14, 6, METAL)
	_barrel(st, MeshKit.at(Vector3(0.2, 0.035, 0)), 0.12, 0.012, METAL)
	MeshKit.column(st, MeshKit.at(Vector3(0, 0.17, 0)), 0.035, 0.025, 0.06, 6, METAL)


static func _t_copter(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_skids(st, 0.14, 0.4)
	var low := _rect(-0.24, 0.24, -0.125, 0.125)
	var high := _rect(-0.2, 0.14, -0.11, 0.11)
	_loft(st, Transform3D.IDENTITY, low, 0.04, high, 0.23, t.color)
	var shield := MeshKit.at(Vector3(0.19, 0.19, 0)) * Transform3D(Basis(Vector3.BACK, 0.7))
	MeshKit.box(st, shield, Vector3(0.012, 0.07, 0.2), GLASS_DARK)
	for z in [-0.123, 0.123]:
		MeshKit.box(st, MeshKit.at(Vector3(-0.02, 0.12, z)), Vector3(0.14, 0.12, 0.008), TRACK)
		MeshKit.box(
			st, MeshKit.at(Vector3(-0.02, 0.2, z)), Vector3(0.4, 0.03, 0.008), t.color_light
		)
	var boom_low := _rect(-0.42, -0.2, -0.04, 0.04)
	var boom_high := _rect(-0.42, -0.2, -0.03, 0.03)
	_loft(st, Transform3D.IDENTITY, boom_low, 0.13, boom_high, 0.21, t.color)
	var fin := PackedVector2Array(
		[Vector2(-0.33, 0.2), Vector2(-0.42, 0.2), Vector2(-0.42, 0.31), Vector2(-0.37, 0.31)]
	)
	_profile(st, fin, -0.012, 0.012, t.color_dark)
	MeshKit.block(st, MeshKit.at(Vector3(-0.04, 0.23, 0)), Vector3(0.2, 0.04, 0.12), t.color_dark)
	MeshKit.column(st, MeshKit.at(Vector3(-0.02, 0.26, 0)), 0.03, 0.025, 0.03, 6, METAL)


## A main rotor: blades radiate from the hub at the part's origin, which the
## body's `ROTOR_HUB` places on the mast.
static func _rotor_mesh(type_id: StringName) -> ArrayMesh:
	if not _rotors.has(type_id):
		var blades := 4 if type_id == &"b_copter" else 3
		var radius := 0.38 if type_id == &"b_copter" else 0.42
		var st := MeshKit.begin()
		MeshKit.column(st, MeshKit.at(Vector3(0, -0.01, 0)), 0.035, 0.025, 0.03, 6, METAL)
		for i in blades:
			var xf := MeshKit.at(Vector3.ZERO, 360.0 * i / blades + 20.0)
			var blade := xf * MeshKit.at(Vector3(radius / 2.0, 0.008, 0))
			MeshKit.box(st, blade, Vector3(radius, 0.01, 0.04), TRACK)
		_rotors[type_id] = st.commit()
	return _rotors[type_id]


# --- ships -----------------------------------------------------------------


## A hull from keel (y -0.06) to deck: a pointed bow at +X, a narrower keel,
## and a dark boot-topping band where it meets the water.
static func _hull(
	st: SurfaceTool,
	length: float,
	beam: float,
	deck: float,
	bow: float,
	t: CommanderVisuals.FactionTheme
) -> void:
	var l := length / 2.0
	var b := beam / 2.0
	var top := PackedVector2Array(
		[Vector2(-l, -b), Vector2(l - bow, -b), Vector2(l, 0), Vector2(l - bow, b), Vector2(-l, b)]
	)
	var mid := PackedVector2Array(
		[
			Vector2(-l + 0.01, -b * 0.9),
			Vector2(l - bow - 0.01, -b * 0.9),
			Vector2(l - 0.03, 0),
			Vector2(l - bow - 0.01, b * 0.9),
			Vector2(-l + 0.01, b * 0.9),
		]
	)
	var keel := PackedVector2Array(
		[
			Vector2(-l + 0.03, -b * 0.6),
			Vector2(l - bow - 0.02, -b * 0.6),
			Vector2(l - 0.08, 0),
			Vector2(l - bow - 0.02, b * 0.6),
			Vector2(-l + 0.03, b * 0.6),
		]
	)
	_loft(st, Transform3D.IDENTITY, keel, -0.06, mid, 0.02, t.color_dark)
	_loft(st, Transform3D.IDENTITY, mid, 0.02, top, deck, t.color)


static func _ship_turret(
	st: SurfaceTool, pos: Vector3, yaw: float, guns: int, t: CommanderVisuals.FactionTheme
) -> void:
	var xf := (
		MeshKit.at(pos, yaw) * Transform3D(Basis.from_scale(Vector3.ONE * (1.0 + guns * 0.12)))
	)
	var low := _rect(-0.05, 0.05, -0.05, 0.05)
	var high := _rect(-0.05, 0.03, -0.04, 0.04)
	_loft(st, xf, low, 0.0, high, 0.05, t.color_light)
	for g in guns:
		var z := (float(g) - (guns - 1) / 2.0) * 0.026
		_barrel(st, xf * _pitch(Vector3(0.03, 0.028, z), 4), 0.11, 0.01, METAL)


static func _battleship(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_hull(st, 0.84, 0.28, 0.1, 0.22, t)
	_slab(st, Transform3D.IDENTITY, _rect(-0.38, 0.18, -0.12, 0.12), 0.1, 0.108, DECK)
	_ship_turret(st, Vector3(0.23, 0.108, 0), 0, 3, t)
	_ship_turret(st, Vector3(0.1, 0.13, 0), 0, 3, t)
	MeshKit.block(st, MeshKit.at(Vector3(0.1, 0.108, 0)), Vector3(0.1, 0.022, 0.1), t.color)
	_ship_turret(st, Vector3(-0.24, 0.108, 0), 180, 2, t)
	MeshKit.block(st, MeshKit.at(Vector3(-0.08, 0.108, 0)), Vector3(0.2, 0.09, 0.17), t.color)
	MeshKit.block(st, MeshKit.at(Vector3(-0.05, 0.198, 0)), Vector3(0.12, 0.08, 0.12), t.color)
	MeshKit.box(st, MeshKit.at(Vector3(0.012, 0.25, 0)), Vector3(0.01, 0.025, 0.1), GLASS_DARK)
	MeshKit.block(
		st, MeshKit.at(Vector3(-0.04, 0.278, 0)), Vector3(0.07, 0.04, 0.08), t.color_light
	)
	MeshKit.column(st, MeshKit.at(Vector3(-0.04, 0.318, 0)), 0.012, 0.008, 0.12, 4, METAL)
	MeshKit.box(st, MeshKit.at(Vector3(-0.04, 0.39, 0)), Vector3(0.012, 0.012, 0.1), METAL)
	MeshKit.column(st, MeshKit.at(Vector3(-0.17, 0.198, 0)), 0.04, 0.035, 0.1, 8, t.color_dark)
	MeshKit.column(st, MeshKit.at(Vector3(-0.17, 0.298, 0)), 0.036, 0.036, 0.012, 8, TRACK)


static func _cruiser(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_hull(st, 0.8, 0.22, 0.09, 0.26, t)
	_slab(st, Transform3D.IDENTITY, _rect(-0.38, 0.12, -0.09, 0.09), 0.09, 0.097, t.color_dark)
	_ship_turret(st, Vector3(0.2, 0.097, 0), 0, 1, t)
	for row in 2:
		for col in 3:
			var cell := Vector3(0.07 + 0.03 * row, 0.097, -0.03 + 0.03 * col)
			MeshKit.block(st, MeshKit.at(cell), Vector3(0.022, 0.012, 0.022), t.color_dark)
	var low := _rect(-0.17, 0.02, -0.08, 0.08)
	var high := _rect(-0.14, -0.01, -0.06, 0.06)
	_loft(st, Transform3D.IDENTITY, low, 0.097, high, 0.23, t.color)
	MeshKit.box(st, MeshKit.at(Vector3(0.0, 0.2, 0)), Vector3(0.02, 0.025, 0.14), GLASS_DARK)
	MeshKit.column(st, MeshKit.at(Vector3(-0.08, 0.23, 0)), 0.02, 0.01, 0.15, 4, METAL)
	MeshKit.box(st, MeshKit.at(Vector3(-0.08, 0.33, 0)), Vector3(0.03, 0.04, 0.12), t.color_light)
	MeshKit.block(st, MeshKit.at(Vector3(-0.22, 0.097, 0)), Vector3(0.07, 0.07, 0.07), t.color_dark)
	_slab(st, Transform3D.IDENTITY, _rect(-0.37, -0.28, -0.07, 0.07), 0.097, 0.1, t.color_light)


static func _lander(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_hull(st, 0.8, 0.34, 0.07, 0.07, t)
	_slab(st, Transform3D.IDENTITY, _rect(-0.18, 0.3, -0.13, 0.13), 0.07, 0.074, METAL)
	MeshKit.block(st, MeshKit.at(Vector3(0.1, 0.074, -0.04)), Vector3(0.1, 0.06, 0.08), DECK)
	MeshKit.block(st, MeshKit.at(Vector3(-0.02, 0.074, 0.05)), Vector3(0.1, 0.06, 0.08), DECK)
	for z in [-0.155, 0.155]:
		MeshKit.block(st, MeshKit.at(Vector3(0.04, 0.07, z)), Vector3(0.62, 0.07, 0.03), t.color)
		MeshKit.block(
			st, MeshKit.at(Vector3(0.04, 0.14, z)), Vector3(0.62, 0.012, 0.036), t.color_light
		)
	var ramp := _pitch(Vector3(0.34, 0.07, 0), 70)
	MeshKit.box(st, ramp * MeshKit.at(Vector3(0.06, 0, 0)), Vector3(0.12, 0.02, 0.3), t.color_dark)
	var bridge_low := _rect(-0.38, -0.2, -0.15, 0.15)
	var bridge_high := _rect(-0.38, -0.23, -0.13, 0.13)
	_loft(st, Transform3D.IDENTITY, bridge_low, 0.07, bridge_high, 0.2, t.color)
	MeshKit.box(st, MeshKit.at(Vector3(-0.225, 0.17, 0)), Vector3(0.012, 0.03, 0.22), GLASS_DARK)
	MeshKit.block(st, MeshKit.at(Vector3(-0.31, 0.2, 0)), Vector3(0.08, 0.04, 0.08), t.color_light)
	MeshKit.column(st, MeshKit.at(Vector3(-0.31, 0.24, 0)), 0.008, 0.006, 0.06, 4, METAL)


static func _sub(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	var squash := Basis.from_scale(Vector3(1.0, 0.65, 1.0))
	MeshKit.tube(st, Transform3D(squash, Vector3(-0.02, 0.02, 0)), 0.11, 0.56, 10, t.color)
	var bow := Transform3D(squash * Basis.from_scale(Vector3(1.4, 1, 1)), Vector3(0.26, 0.02, 0))
	MeshKit.ball(st, bow, 0.108, 4, 10, t.color)
	_nose(
		st,
		Transform3D(squash, Vector3(-0.3, 0.02, 0)).rotated_local(Vector3.UP, PI),
		0.108,
		0.12,
		10,
		t.color_dark
	)
	var low := _rect(0.0, 0.16, -0.035, 0.035)
	var high := _rect(0.03, 0.13, -0.028, 0.028)
	_loft(st, Transform3D.IDENTITY, low, 0.06, high, 0.2, t.color_dark)
	MeshKit.box(st, MeshKit.at(Vector3(0.09, 0.15, 0)), Vector3(0.03, 0.012, 0.16), t.color_dark)
	MeshKit.column(st, MeshKit.at(Vector3(0.06, 0.2, 0)), 0.006, 0.006, 0.05, 4, METAL)
	MeshKit.box(st, MeshKit.at(Vector3(-0.38, 0.03, 0)), Vector3(0.05, 0.012, 0.18), TRACK)
	MeshKit.box(st, MeshKit.at(Vector3(-0.38, 0.03, 0)), Vector3(0.05, 0.14, 0.012), TRACK)
	MeshKit.box(st, MeshKit.at(Vector3(0.0, 0.085, 0)), Vector3(0.42, 0.008, 0.05), t.color_light)
