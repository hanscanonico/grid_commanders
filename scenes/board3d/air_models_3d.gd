class_name AirModels3D
extends RefCounted
## The four aircraft's bodies for `UnitModels3D`, built facing +X with the
## origin at the belly, and the helicopters' rotors, which spin as their own
## part. Faction surfaces are painted `ramp.base` and placed by `FactionRamp3D`.

## Where a spinning part's pivot sits on the body, for the types that have one.
const ROTOR_HUB: Dictionary[StringName, Vector3] = {
	&"b_copter": Vector3(0.0, 0.225, 0.0),
	&"t_copter": Vector3(-0.02, 0.29, 0.0),
}
## A rotor blade's width across its sweep: what the board camera sees of it,
## so it is held to `UnitParts3D.MIN_THICKNESS` and wide enough that a spinning
## rotor reads as a disc.
const BLADE_CHORD := 0.08

static var _rotors: Dictionary[StringName, ArrayMesh] = {}


## Builds `type_id`'s body into `st`; false when it is not an aircraft.
static func build(st: SurfaceTool, type_id: StringName, r: FactionRamp3D) -> bool:
	match type_id:
		&"fighter":
			_fighter(st, r)
		&"bomber":
			_bomber(st, r)
		&"b_copter":
			_b_copter(st, r)
		&"t_copter":
			_t_copter(st, r)
		_:
			return false
	return true


## A main rotor: blades radiate from the hub at the part's origin, which
## `ROTOR_HUB` places on the mast. Shared by every army.
static func rotor_mesh(type_id: StringName) -> ArrayMesh:
	if not _rotors.has(type_id):
		var blades := 4 if type_id == &"b_copter" else 3
		var radius := 0.38 if type_id == &"b_copter" else 0.42
		var chord := maxf(BLADE_CHORD, UnitParts3D.MIN_THICKNESS)
		var st := MeshKit.begin()
		MeshKit.column(
			st, MeshKit.at(Vector3(0, -0.01, 0)), 0.035, 0.025, 0.03, 6, UnitPalette3D.GUNMETAL
		)
		for i in blades:
			var xf := MeshKit.at(Vector3.ZERO, 360.0 * i / blades + 20.0)
			var blade := xf * MeshKit.at(Vector3(radius / 2.0, 0.008, 0))
			MeshKit.box(st, blade, Vector3(radius, 0.01, chord), UnitPalette3D.ROTOR)
		_rotors[type_id] = st.commit()
	return _rotors[type_id]


## One wing of a pair: `outline` is the +Z wing in (x, z), mirrored for -Z.
static func _wings(
	st: SurfaceTool, outline: PackedVector2Array, y: float, thick: float, c: Color
) -> void:
	var mirrored := PackedVector2Array()
	for p in outline:
		mirrored.append(Vector2(p.x, -p.y))
	UnitParts3D.slab(st, Transform3D.IDENTITY, outline, y, y + thick, c)
	UnitParts3D.slab(st, Transform3D.IDENTITY, mirrored, y, y + thick, c)


static func _fighter(st: SurfaceTool, r: FactionRamp3D) -> void:
	MeshKit.tube(st, MeshKit.at(Vector3(-0.06, 0.075, 0)), 0.07, 0.56, 8, r.base)
	UnitParts3D.nose(st, MeshKit.at(Vector3(0.22, 0.075, 0)), 0.07, 0.19, 8, r.light)
	var wing := PackedVector2Array(
		[Vector2(0.14, 0.05), Vector2(-0.2, 0.4), Vector2(-0.3, 0.4), Vector2(-0.3, 0.05)]
	)
	_wings(st, wing, 0.055, 0.025, r.base)
	var tip := PackedVector2Array(
		[Vector2(-0.19, 0.36), Vector2(-0.2, 0.4), Vector2(-0.3, 0.4), Vector2(-0.3, 0.36)]
	)
	_wings(st, tip, 0.056, 0.026, r.light)
	var tail := PackedVector2Array(
		[Vector2(-0.22, 0.11), Vector2(-0.34, 0.14), Vector2(-0.38, 0.14), Vector2(-0.34, 0.11)]
	)
	_wings(st, tail, 0.065, 0.02, r.dark)
	for z in [-0.055, 0.055]:
		var fin := PackedVector2Array(
			[Vector2(-0.2, 0.12), Vector2(-0.31, 0.12), Vector2(-0.37, 0.27), Vector2(-0.31, 0.27)]
		)
		UnitParts3D.profile(st, fin, z - 0.01, z + 0.01, r.dark)
	var canopy := Transform3D(Basis.from_scale(Vector3(2.4, 1.0, 1.0)), Vector3(0.1, 0.13, 0))
	MeshKit.ball(st, canopy, 0.05, 3, 8, UnitPalette3D.GLASS)
	MeshKit.tube(st, MeshKit.at(Vector3(-0.35, 0.075, 0)), 0.055, 0.04, 8, UnitPalette3D.RUBBER)


static func _bomber(st: SurfaceTool, r: FactionRamp3D) -> void:
	MeshKit.tube(st, MeshKit.at(Vector3(-0.03, 0.1, 0)), 0.09, 0.6, 8, r.base)
	var nose := Transform3D(Basis.from_scale(Vector3(1.4, 1.0, 1.0)), Vector3(0.27, 0.1, 0))
	MeshKit.ball(st, nose, 0.09, 4, 8, r.light)
	MeshKit.ball(
		st, Transform3D(Basis.IDENTITY, Vector3(0.36, 0.11, 0)), 0.05, 3, 8, UnitPalette3D.GLASS
	)
	var wing := PackedVector2Array(
		[Vector2(0.12, 0.06), Vector2(0.02, 0.42), Vector2(-0.08, 0.42), Vector2(-0.12, 0.06)]
	)
	_wings(st, wing, 0.1, 0.03, r.base)
	var band := PackedVector2Array(
		[Vector2(0.05, 0.25), Vector2(0.04, 0.3), Vector2(-0.1, 0.3), Vector2(-0.09, 0.25)]
	)
	_wings(st, band, 0.101, 0.031, r.dark)
	for z in [-0.3, -0.16, 0.16, 0.3]:
		var pod := MeshKit.at(Vector3(0.04 - absf(z) * 0.25, 0.08, z))
		MeshKit.tube(st, pod, 0.04, 0.18, 6, r.dark)
		MeshKit.tube(st, pod * MeshKit.at(Vector3(0.09, 0, 0)), 0.03, 0.02, 6, UnitPalette3D.RUBBER)
	var tail := PackedVector2Array(
		[Vector2(-0.26, 0.06), Vector2(-0.33, 0.2), Vector2(-0.39, 0.2), Vector2(-0.38, 0.06)]
	)
	_wings(st, tail, 0.12, 0.02, r.base)
	var fin := PackedVector2Array(
		[Vector2(-0.22, 0.15), Vector2(-0.34, 0.15), Vector2(-0.4, 0.3), Vector2(-0.33, 0.3)]
	)
	UnitParts3D.profile(st, fin, -0.012, 0.012, r.dark)


static func _skids(st: SurfaceTool, half_gap: float, length: float) -> void:
	for z in [-half_gap, half_gap]:
		MeshKit.box(
			st, MeshKit.at(Vector3(0, 0.008, z)), Vector3(length, 0.016, 0.02), UnitPalette3D.RUBBER
		)
		for x in [-length * 0.3, length * 0.3]:
			MeshKit.box(
				st,
				MeshKit.at(Vector3(x, 0.03, z * 0.8)),
				Vector3(0.015, 0.05, 0.015),
				UnitPalette3D.RUBBER
			)


static func _b_copter(st: SurfaceTool, r: FactionRamp3D) -> void:
	_skids(st, 0.1, 0.34)
	var low := UnitParts3D.rect(-0.14, 0.24, -0.065, 0.065)
	var high := UnitParts3D.rect(-0.12, 0.1, -0.06, 0.06)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.04, high, 0.17, r.base)
	var canopy := Transform3D(Basis.from_scale(Vector3(2.6, 1.0, 1.0)), Vector3(0.12, 0.14, 0))
	MeshKit.ball(st, canopy, 0.055, 3, 8, UnitPalette3D.GLASS)
	var boom := MeshKit.at(Vector3(-0.27, 0.13, 0))
	MeshKit.tube(st, boom, 0.028, 0.28, 6, r.base)
	var fin := PackedVector2Array(
		[Vector2(-0.34, 0.12), Vector2(-0.41, 0.12), Vector2(-0.41, 0.26), Vector2(-0.37, 0.26)]
	)
	UnitParts3D.profile(st, fin, -0.01, 0.01, r.dark)
	var tail_rotor := Vector3(maxf(0.02, UnitParts3D.MIN_THICKNESS), 0.12, 0.008)
	MeshKit.box(st, MeshKit.at(Vector3(-0.39, 0.2, 0.02)), tail_rotor, UnitPalette3D.ROTOR)
	MeshKit.box(st, MeshKit.at(Vector3(-0.02, 0.09, 0)), Vector3(0.09, 0.016, 0.34), r.dark)
	for z in [-0.15, 0.15]:
		MeshKit.tube(
			st, MeshKit.at(Vector3(-0.01, 0.065, z)), 0.028, 0.14, 6, UnitPalette3D.GUNMETAL
		)
	UnitParts3D.barrel(st, MeshKit.at(Vector3(0.2, 0.035, 0)), 0.12, 0.012, UnitPalette3D.STEEL)
	MeshKit.column(
		st, MeshKit.at(Vector3(0, 0.17, 0)), 0.035, 0.025, 0.06, 6, UnitPalette3D.GUNMETAL
	)


static func _t_copter(st: SurfaceTool, r: FactionRamp3D) -> void:
	_skids(st, 0.14, 0.4)
	var low := UnitParts3D.rect(-0.24, 0.24, -0.125, 0.125)
	var high := UnitParts3D.rect(-0.2, 0.14, -0.11, 0.11)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.04, high, 0.23, r.base)
	var shield := MeshKit.at(Vector3(0.19, 0.19, 0)) * Transform3D(Basis(Vector3.BACK, 0.7))
	MeshKit.box(st, shield, Vector3(0.012, 0.07, 0.2), UnitPalette3D.GLASS)
	for z in [-0.123, 0.123]:
		MeshKit.box(st, MeshKit.at(Vector3(-0.02, 0.12, z)), Vector3(0.14, 0.12, 0.008), r.dark)
		MeshKit.box(st, MeshKit.at(Vector3(-0.02, 0.2, z)), Vector3(0.4, 0.03, 0.008), r.light)
	var boom_low := UnitParts3D.rect(-0.42, -0.2, -0.04, 0.04)
	var boom_high := UnitParts3D.rect(-0.42, -0.2, -0.03, 0.03)
	UnitParts3D.loft(st, Transform3D.IDENTITY, boom_low, 0.13, boom_high, 0.21, r.base)
	var fin := PackedVector2Array(
		[Vector2(-0.33, 0.2), Vector2(-0.42, 0.2), Vector2(-0.42, 0.31), Vector2(-0.37, 0.31)]
	)
	UnitParts3D.profile(st, fin, -0.012, 0.012, r.dark)
	MeshKit.block(st, MeshKit.at(Vector3(-0.04, 0.23, 0)), Vector3(0.2, 0.04, 0.12), r.dark)
	MeshKit.column(
		st, MeshKit.at(Vector3(-0.02, 0.26, 0)), 0.03, 0.025, 0.03, 6, UnitPalette3D.GUNMETAL
	)
