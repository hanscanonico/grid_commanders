class_name LandModels3D
extends RefCounted
## The ten land units' bodies for `UnitModels3D`: the two foot squads, the
## tracked hulls and the wheeled trucks, built facing +X standing on the origin.
## Faction surfaces are painted `ramp.base` and placed by `FactionRamp3D`; every
## other part wears its role's colour from `UnitPalette3D`.


## Builds `type_id`'s body into `st`; false when it is not a land unit.
static func build(st: SurfaceTool, type_id: StringName, r: FactionRamp3D) -> bool:
	match type_id:
		&"infantry":
			_infantry(st, r)
		&"mech":
			_mech(st, r)
		&"recon":
			_recon(st, r)
		&"apc":
			_apc(st, r)
		&"tank":
			_tank(st, r)
		&"md_tank":
			_md_tank(st, r)
		&"artillery":
			_artillery(st, r)
		&"rockets":
			_rockets(st, r)
		&"anti_air":
			_anti_air(st, r)
		&"missiles":
			_missiles(st, r)
		_:
			return false
	return true


## One soldier at `pos`, scaled `s`; `heavy` shoulders a mech's tube.
static func soldier(st: SurfaceTool, pos: Vector3, s: float, r: FactionRamp3D, heavy: bool) -> void:
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * s), pos)
	for z in [-0.022, 0.022]:
		MeshKit.block(
			st, xf * MeshKit.at(Vector3(0, 0, z)), Vector3(0.045, 0.08, 0.034), UnitPalette3D.RUBBER
		)
	MeshKit.block(st, xf * MeshKit.at(Vector3(0, 0.075, 0)), Vector3(0.075, 0.1, 0.1), r.base)
	for z in [-0.062, 0.062]:
		MeshKit.block(st, xf * MeshKit.at(Vector3(0.01, 0.1, z)), Vector3(0.04, 0.07, 0.03), r.base)
	var pack := Vector3(0.05, 0.08, 0.09) if heavy else Vector3(0.035, 0.07, 0.07)
	MeshKit.block(st, xf * MeshKit.at(Vector3(-0.05, 0.09, 0)), pack, r.dark)
	MeshKit.ball(st, xf * MeshKit.at(Vector3(0.012, 0.205, 0)), 0.036, 3, 6, UnitPalette3D.SKIN)
	MeshKit.ball(st, xf * MeshKit.at(Vector3(-0.006, 0.222, 0)), 0.04, 3, 8, r.dark)
	MeshKit.block(st, xf * MeshKit.at(Vector3(0.0, 0.2, 0)), Vector3(0.1, 0.012, 0.09), r.dark)
	if heavy:
		var tube := xf * MeshKit.at(Vector3(-0.13, 0.2, 0.065))
		UnitParts3D.barrel(st, tube, 0.24, 0.026, UnitPalette3D.STEEL)
		MeshKit.tube(
			st, tube * MeshKit.at(Vector3(0.23, 0, 0)), 0.032, 0.03, 6, UnitPalette3D.GUNMETAL
		)
	else:
		var rifle := xf * UnitParts3D.pitch(Vector3(-0.02, 0.13, 0.05), 20)
		UnitParts3D.barrel(st, rifle, 0.14, 0.01, UnitPalette3D.STEEL)


static func _infantry(st: SurfaceTool, r: FactionRamp3D) -> void:
	for pos in [Vector3(0.15, 0, 0), Vector3(-0.12, 0, -0.2), Vector3(-0.1, 0, 0.2)]:
		soldier(st, pos, 1.3, r, false)


static func _mech(st: SurfaceTool, r: FactionRamp3D) -> void:
	for pos in [Vector3(0.13, 0, -0.03), Vector3(-0.14, 0, -0.2), Vector3(-0.1, 0, 0.2)]:
		soldier(st, pos, 1.4, r, true)


# --- running gear ------------------------------------------------------------


## A rubber tyre with a steel hub cap, its axle across Z.
static func _wheel(st: SurfaceTool, pos: Vector3, radius: float, width: float) -> void:
	MeshKit.tube(st, MeshKit.at(pos, 90), radius, width, 8, UnitPalette3D.RUBBER)
	MeshKit.tube(st, MeshKit.at(pos, 90), radius * 0.45, width + 0.012, 6, UnitPalette3D.STEEL)


## Two tracks under a hull, with steel road-wheel hubs and a recessed guard.
static func _tracks(
	st: SurfaceTool, length: float, height: float, width: float, gap: float, r: FactionRamp3D
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
		UnitParts3D.profile(st, outline, z - width / 2.0, z + width / 2.0, UnitPalette3D.RUBBER)
		for i in 4:
			var x := lerpf(-l + height * 0.55, l - height * 0.55, float(i) / 3.0)
			var hub := Vector3(x, height * 0.45, side * (gap + width / 2.0))
			MeshKit.tube(st, MeshKit.at(hub, 90), height * 0.3, 0.016, 6, UnitPalette3D.STEEL)
		var guard := Vector3(0, height + 0.012, z)
		MeshKit.box(st, MeshKit.at(guard), Vector3(length * 0.96, 0.024, width + 0.03), r.dark)


## A six-wheeled truck: chassis, wheels and a cab at the front. The launcher
## trucks differ only in what rides the flatbed behind the cab.
static func _truck(st: SurfaceTool, r: FactionRamp3D) -> void:
	for x in [-0.27, -0.11, 0.25]:
		for z in [-0.2, 0.2]:
			_wheel(st, Vector3(x, 0.075, z), 0.075, 0.07)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.07, 0)), Vector3(0.78, 0.06, 0.3), r.dark)
	var cab_low := UnitParts3D.rect(0.14, 0.4, -0.17, 0.17)
	var cab_high := UnitParts3D.rect(0.14, 0.31, -0.15, 0.15)
	UnitParts3D.loft(st, Transform3D.IDENTITY, cab_low, 0.13, cab_high, 0.28, r.base)
	var shield := MeshKit.at(Vector3(0.36, 0.215, 0)) * Transform3D(Basis(Vector3.BACK, 0.5))
	MeshKit.box(st, shield, Vector3(0.012, 0.08, 0.26), UnitPalette3D.GLASS)
	MeshKit.block(st, MeshKit.at(Vector3(0.36, 0.1, 0)), Vector3(0.1, 0.04, 0.32), r.light)


# --- ground vehicles -------------------------------------------------------


static func _recon(st: SurfaceTool, r: FactionRamp3D) -> void:
	for x in [-0.22, 0.22]:
		for z in [-0.215, 0.215]:
			_wheel(st, Vector3(x, 0.085, z), 0.085, 0.08)
	var low := UnitParts3D.rect(-0.36, 0.38, -0.17, 0.17)
	var high := UnitParts3D.rect(-0.3, 0.16, -0.14, 0.14)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.07, high, 0.22, r.base)
	var shield := MeshKit.at(Vector3(0.235, 0.18, 0)) * Transform3D(Basis(Vector3.BACK, 0.9))
	MeshKit.box(st, shield, Vector3(0.012, 0.09, 0.22), UnitPalette3D.GLASS)
	for z in [-0.18, 0.18]:
		MeshKit.box(st, MeshKit.at(Vector3(0, 0.17, z)), Vector3(0.6, 0.02, 0.03), r.dark)
	MeshKit.column(st, MeshKit.at(Vector3(-0.08, 0.22, 0)), 0.075, 0.065, 0.04, 8, r.dark)
	UnitParts3D.barrel(st, MeshKit.at(Vector3(-0.04, 0.245, 0)), 0.22, 0.014, UnitPalette3D.STEEL)
	MeshKit.block(
		st, MeshKit.at(Vector3(-0.1, 0.26, 0)), Vector3(0.06, 0.03, 0.05), UnitPalette3D.GUNMETAL
	)


static func _apc(st: SurfaceTool, r: FactionRamp3D) -> void:
	_tracks(st, 0.72, 0.12, 0.15, 0.225, r)
	var low := UnitParts3D.rect(-0.36, 0.36, -0.2, 0.2)
	var high := UnitParts3D.rect(-0.34, 0.14, -0.18, 0.18)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.08, high, 0.31, r.base)
	for z in [-0.184, 0.184]:
		MeshKit.box(st, MeshKit.at(Vector3(-0.1, 0.22, z)), Vector3(0.44, 0.035, 0.012), r.light)
	MeshKit.box(st, MeshKit.at(Vector3(-0.35, 0.17, 0)), Vector3(0.015, 0.16, 0.2), r.dark)
	MeshKit.block(st, MeshKit.at(Vector3(-0.2, 0.31, 0)), Vector3(0.16, 0.025, 0.2), r.dark)
	MeshKit.block(st, MeshKit.at(Vector3(0.04, 0.31, 0)), Vector3(0.1, 0.03, 0.12), r.light)
	var slit := MeshKit.at(Vector3(0.25, 0.26, 0)) * Transform3D(Basis(Vector3.BACK, 1.1))
	MeshKit.box(st, slit, Vector3(0.012, 0.05, 0.26), UnitPalette3D.GLASS)


static func _tank(st: SurfaceTool, r: FactionRamp3D) -> void:
	_tracks(st, 0.7, 0.13, 0.16, 0.23, r)
	var low := UnitParts3D.rect(-0.33, 0.34, -0.2, 0.2)
	var high := UnitParts3D.rect(-0.31, 0.2, -0.19, 0.19)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.09, high, 0.19, r.base)
	MeshKit.column(st, MeshKit.at(Vector3(-0.04, 0.19, 0)), 0.165, 0.165, 0.02, 8, r.dark)
	MeshKit.column(st, MeshKit.at(Vector3(-0.04, 0.21, 0)), 0.15, 0.115, 0.085, 8, r.base)
	MeshKit.column(st, MeshKit.at(Vector3(-0.08, 0.295, 0.04)), 0.045, 0.04, 0.025, 6, r.light)
	MeshKit.box(
		st, MeshKit.at(Vector3(0.1, 0.25, 0)), Vector3(0.05, 0.06, 0.08), UnitPalette3D.GUNMETAL
	)
	UnitParts3D.barrel(st, MeshKit.at(Vector3(0.1, 0.25, 0)), 0.32, 0.027, UnitPalette3D.STEEL)


static func _md_tank(st: SurfaceTool, r: FactionRamp3D) -> void:
	_tracks(st, 0.8, 0.15, 0.18, 0.25, r)
	for side: float in [-1.0, 1.0]:
		var skirt := MeshKit.at(Vector3(0, 0.11, side * 0.345))
		MeshKit.box(st, skirt, Vector3(0.72, 0.08, 0.02), r.dark)
	var low := UnitParts3D.rect(-0.38, 0.38, -0.24, 0.24)
	var high := UnitParts3D.rect(-0.36, 0.24, -0.23, 0.23)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.1, high, 0.22, r.base)
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
	UnitParts3D.loft(st, Transform3D.IDENTITY, t_low, 0.22, t_high, 0.33, r.base)
	MeshKit.block(st, MeshKit.at(Vector3(-0.28, 0.24, 0)), Vector3(0.08, 0.07, 0.26), r.dark)
	MeshKit.column(st, MeshKit.at(Vector3(-0.1, 0.33, -0.07)), 0.05, 0.045, 0.035, 6, r.light)
	UnitParts3D.barrel(st, MeshKit.at(Vector3(0.12, 0.275, 0)), 0.29, 0.036, UnitPalette3D.STEEL)
	MeshKit.box(
		st,
		MeshKit.at(Vector3(0.39, 0.275, 0)),
		Vector3(0.055, 0.065, 0.075),
		UnitPalette3D.GUNMETAL
	)


static func _artillery(st: SurfaceTool, r: FactionRamp3D) -> void:
	_tracks(st, 0.66, 0.12, 0.14, 0.2, r)
	var low := UnitParts3D.rect(-0.31, 0.32, -0.18, 0.18)
	var high := UnitParts3D.rect(-0.3, 0.22, -0.17, 0.17)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.08, high, 0.17, r.base)
	for side: float in [-1.0, 1.0]:
		var cheek := PackedVector2Array(
			[Vector2(-0.24, 0.17), Vector2(0.02, 0.17), Vector2(-0.04, 0.29), Vector2(-0.2, 0.29)]
		)
		UnitParts3D.profile(st, cheek, side * 0.13 - 0.02, side * 0.13 + 0.02, r.base)
	var shield := UnitParts3D.pitch(Vector3(0.02, 0.17, 0), 60)
	MeshKit.box(st, shield * MeshKit.at(Vector3(0.07, 0, 0)), Vector3(0.14, 0.012, 0.3), r.dark)
	var gun := UnitParts3D.pitch(Vector3(-0.12, 0.24, 0), 24)
	MeshKit.tube(st, gun * MeshKit.at(Vector3(0.02, 0, 0)), 0.06, 0.18, 8, UnitPalette3D.GUNMETAL)
	UnitParts3D.barrel(st, gun, 0.34, 0.032, UnitPalette3D.STEEL)
	MeshKit.tube(st, gun * MeshKit.at(Vector3(0.31, 0, 0)), 0.042, 0.05, 6, UnitPalette3D.GUNMETAL)
	MeshKit.wedge(
		st,
		MeshKit.at(Vector3(-0.35, 0.02, 0), 180),
		Vector3(0.06, 0.08, 0.28),
		UnitPalette3D.GUNMETAL
	)


static func _anti_air(st: SurfaceTool, r: FactionRamp3D) -> void:
	_tracks(st, 0.68, 0.12, 0.15, 0.22, r)
	var low := UnitParts3D.rect(-0.33, 0.33, -0.19, 0.19)
	var high := UnitParts3D.rect(-0.31, 0.2, -0.18, 0.18)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.08, high, 0.18, r.base)
	var t_low := UnitParts3D.rect(-0.17, 0.12, -0.12, 0.12)
	var t_high := UnitParts3D.rect(-0.15, 0.07, -0.1, 0.1)
	UnitParts3D.loft(st, Transform3D.IDENTITY, t_low, 0.18, t_high, 0.28, r.base)
	for z in [-0.155, 0.155]:
		MeshKit.box(
			st, MeshKit.at(Vector3(0.0, 0.25, z)), Vector3(0.1, 0.08, 0.05), UnitPalette3D.GUNMETAL
		)
		for dz in [-0.014, 0.014]:
			var pivot := UnitParts3D.pitch(Vector3(0.03, 0.26, z + dz), 32)
			UnitParts3D.barrel(st, pivot, 0.26, 0.012, UnitPalette3D.STEEL)
	UnitParts3D.mast(st, MeshKit.at(Vector3(-0.13, 0.28, 0)), 0.05, 0.012, UnitPalette3D.STEEL)
	var dish := MeshKit.at(Vector3(-0.13, 0.34, 0)) * Transform3D(Basis(Vector3.BACK, -0.35))
	MeshKit.box(st, dish, Vector3(0.02, 0.07, 0.18), r.dark)


static func _rockets(st: SurfaceTool, r: FactionRamp3D) -> void:
	_truck(st, r)
	var pod := UnitParts3D.pitch(Vector3(-0.35, 0.14, 0), 20)
	var size := Vector3(0.4, 0.13, 0.27)
	MeshKit.block(
		st, MeshKit.at(Vector3(0.0, 0.1, 0)), Vector3(0.06, 0.05, 0.12), UnitPalette3D.GUNMETAL
	)
	MeshKit.box(
		st, pod * MeshKit.at(Vector3(size.x / 2.0, size.y / 2.0, 0)), size, UnitPalette3D.GUNMETAL
	)
	for row in 2:
		for col in 3:
			var mouth := Vector3(size.x + 0.002, 0.035 + 0.06 * row, -0.08 + 0.08 * col)
			MeshKit.box(
				st, pod * MeshKit.at(mouth), Vector3(0.012, 0.045, 0.055), UnitPalette3D.RUBBER
			)
	var band := pod * MeshKit.at(Vector3(size.x * 0.3, size.y / 2.0, 0))
	MeshKit.box(st, band, Vector3(0.04, size.y + 0.01, size.z + 0.01), r.dark)


static func _missiles(st: SurfaceTool, r: FactionRamp3D) -> void:
	_truck(st, r)
	var rail := UnitParts3D.pitch(Vector3(-0.37, 0.15, 0), 16)
	MeshKit.box(st, rail * MeshKit.at(Vector3(0.24, 0.01, 0)), Vector3(0.48, 0.03, 0.26), r.dark)
	MeshKit.block(
		st, MeshKit.at(Vector3(0.05, 0.1, 0)), Vector3(0.05, 0.1, 0.08), UnitPalette3D.GUNMETAL
	)
	for z in [-0.075, 0.075]:
		var body := rail * MeshKit.at(Vector3(0.0, 0.07, z))
		UnitParts3D.barrel(st, body, 0.42, 0.046, UnitPalette3D.ORDNANCE)
		UnitParts3D.nose(
			st, body * MeshKit.at(Vector3(0.42, 0, 0)), 0.046, 0.08, 6, UnitPalette3D.ORDNANCE_TIP
		)
		MeshKit.tube(st, body * MeshKit.at(Vector3(0.12, 0, 0)), 0.05, 0.04, 6, r.base)
		MeshKit.box(
			st,
			body * MeshKit.at(Vector3(0.02, 0, 0)),
			Vector3(0.05, 0.13, 0.012),
			UnitPalette3D.GUNMETAL
		)
