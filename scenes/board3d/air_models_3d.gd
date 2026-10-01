class_name AirModels3D
extends RefCounted
## The four aircraft's bodies for `UnitModels3D`, built facing +X with the
## origin at the belly, and the helicopters' rotors, which spin as their own
## parts. Faction surfaces are painted `ramp.base` and placed by `FactionRamp3D`.
##
## The bomber is the biggest thing in the air: the cell's full span, a quarter
## again the fighter's girth. The jets tip their wings and fins and band their
## noses in `UnitPalette3D.LIVERY`, as the sprites paint them white: the army's
## light tone already covers every face that looks up, so a cap in it would not
## show, and a lighter edge is what the darkest army needs.

## Each rotor's pivot on the body, fore to aft: the gunship's one main rotor,
## the transport's tandem pair, the aft one on its raised pylon.
const ROTOR_HUBS: Dictionary[StringName, Array] = {
	&"b_copter": [Vector3(0.0, 0.265, 0.0)],
	&"t_copter": [Vector3(0.17, 0.26, 0.0), Vector3(-0.2, 0.315, 0.0)],
}
## A rotor blade's width across its sweep: what the board camera sees of it,
## so it is held to `UnitParts3D.MIN_THICKNESS` and wide enough that a spinning
## rotor reads as a disc.
const BLADE_CHORD := 0.08
## How far up a fin its light cap starts, as a fraction of its height.
const FIN_CAP := 0.72
## The fighter's fuselage axis and nose tip, where its cannon fires from.
const FIGHTER_AXIS := 0.075
const FIGHTER_NOSE := 0.41
## The gunship's chin gun: its breech and length.
const CHIN_GUN := Vector3(0.22, 0.035, 0)
const CHIN_GUN_LENGTH := 0.14
## The bomber's bomb bay, on its belly behind the wing.
const BOMB_BAY := Vector3(-0.2, 0.02, 0)

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


## Where an aircraft's shot leaves it, in the model's frame; `Vector3.INF` for
## one with no gun.
static func muzzle_of(type_id: StringName) -> Vector3:
	match type_id:
		&"fighter":
			return Vector3(FIGHTER_NOSE, FIGHTER_AXIS, 0)
		&"bomber":
			return BOMB_BAY
		&"b_copter":
			return CHIN_GUN + Vector3(CHIN_GUN_LENGTH, 0, 0)
	return Vector3.INF


## A main rotor: blades radiate from the hub at the part's origin, which
## `ROTOR_HUBS` places on its mast. Shared by every army and by both of a
## tandem pair.
static func rotor_mesh(type_id: StringName) -> ArrayMesh:
	if not _rotors.has(type_id):
		var blades := 4 if type_id == &"b_copter" else 3
		var radius := 0.38 if type_id == &"b_copter" else 0.23
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


## A fin's side profile between its leading and trailing edges (each low to
## high), standing at `z`, its top capped.
static func _fin(
	st: SurfaceTool, lead: PackedVector2Array, trail: PackedVector2Array, z: float, r: FactionRamp3D
) -> void:
	var outline := PackedVector2Array([lead[0], trail[0], trail[1], lead[1]])
	UnitParts3D.profile(st, outline, z - 0.01, z + 0.01, r.dark)
	var cap := PackedVector2Array(
		[lead[0].lerp(lead[1], FIN_CAP), trail[0].lerp(trail[1], FIN_CAP), trail[1], lead[1]]
	)
	UnitParts3D.profile(st, cap, z - 0.013, z + 0.013, UnitPalette3D.LIVERY)


static func _fighter(st: SurfaceTool, r: FactionRamp3D) -> void:
	var axis := FIGHTER_AXIS
	MeshKit.tube(st, MeshKit.at(Vector3(-0.06, axis, 0)), 0.07, 0.56, 8, r.base)
	UnitParts3D.nose(st, MeshKit.at(Vector3(0.22, axis, 0)), 0.07, FIGHTER_NOSE - 0.22, 8, r.base)
	MeshKit.tube(st, MeshKit.at(Vector3(0.2, axis, 0)), 0.074, 0.03, 8, UnitPalette3D.LIVERY)
	var wing := PackedVector2Array(
		[Vector2(0.14, 0.05), Vector2(-0.18, 0.36), Vector2(-0.28, 0.36), Vector2(-0.28, 0.05)]
	)
	_wings(st, wing, 0.055, 0.025, r.base)
	var tip := PackedVector2Array(
		[Vector2(-0.14, 0.32), Vector2(-0.18, 0.36), Vector2(-0.28, 0.36), Vector2(-0.28, 0.32)]
	)
	_wings(st, tip, 0.056, 0.026, UnitPalette3D.LIVERY)
	var tail := PackedVector2Array(
		[Vector2(-0.22, 0.11), Vector2(-0.34, 0.14), Vector2(-0.38, 0.14), Vector2(-0.34, 0.11)]
	)
	_wings(st, tail, 0.065, 0.02, r.dark)
	var lead := PackedVector2Array([Vector2(-0.2, 0.12), Vector2(-0.31, 0.27)])
	var trail := PackedVector2Array([Vector2(-0.31, 0.12), Vector2(-0.37, 0.27)])
	for z in [-0.055, 0.055]:
		_fin(st, lead, trail, z, r)
	var canopy := Transform3D(Basis.from_scale(Vector3(2.4, 1.0, 1.0)), Vector3(0.1, 0.13, 0))
	MeshKit.ball(st, canopy, 0.05, 3, 8, UnitPalette3D.GLASS)
	MeshKit.tube(st, MeshKit.at(Vector3(-0.35, axis, 0)), 0.055, 0.04, 8, UnitPalette3D.RUBBER)
	MeshKit.tube(st, MeshKit.at(Vector3(-0.372, axis, 0)), 0.04, 0.006, 8, UnitPalette3D.EXHAUST)


## A fat fuselage under wings swept back a third, four engine pods, and a dark
## bomb bay on each flank behind the wing.
static func _bomber(st: SurfaceTool, r: FactionRamp3D) -> void:
	var axis := 0.115
	MeshKit.tube(st, MeshKit.at(Vector3(-0.05, axis, 0)), 0.112, 0.56, 8, r.base)
	var nose := Transform3D(Basis.from_scale(Vector3(1.4, 1.0, 1.0)), Vector3(0.23, axis, 0))
	MeshKit.ball(st, nose, 0.11, 4, 8, r.base)
	MeshKit.tube(st, MeshKit.at(Vector3(0.21, axis, 0)), 0.116, 0.03, 8, UnitPalette3D.LIVERY)
	MeshKit.ball(st, MeshKit.at(Vector3(0.33, axis + 0.03, 0)), 0.055, 3, 8, UnitPalette3D.GLASS)
	var wing := PackedVector2Array(
		[Vector2(0.14, 0.08), Vector2(-0.08, 0.42), Vector2(-0.19, 0.42), Vector2(-0.12, 0.08)]
	)
	_wings(st, wing, 0.1, 0.03, r.base)
	var tip := PackedVector2Array(
		[Vector2(-0.054, 0.38), Vector2(-0.08, 0.42), Vector2(-0.19, 0.42), Vector2(-0.18, 0.38)]
	)
	_wings(st, tip, 0.101, 0.031, UnitPalette3D.LIVERY)
	for z in [-0.3, -0.17, 0.17, 0.3]:
		var lead := 0.14 - 0.22 * (absf(z) - 0.08) / 0.34
		var pod := MeshKit.at(Vector3(lead - 0.05, 0.075, z))
		MeshKit.tube(st, pod, 0.04, 0.18, 6, r.dark)
		MeshKit.tube(st, pod * MeshKit.at(Vector3(0.09, 0, 0)), 0.03, 0.02, 6, UnitPalette3D.RUBBER)
	for side: float in [-1.0, 1.0]:
		var bay := MeshKit.at(BOMB_BAY + Vector3(0, 0.04, side * 0.1))
		MeshKit.box(st, bay, Vector3(0.18, 0.055, 0.02), r.dark)
	var tail := PackedVector2Array(
		[Vector2(-0.26, 0.08), Vector2(-0.34, 0.2), Vector2(-0.4, 0.2), Vector2(-0.38, 0.08)]
	)
	_wings(st, tail, 0.13, 0.02, r.base)
	var lead_edge := PackedVector2Array([Vector2(-0.22, 0.17), Vector2(-0.34, 0.315)])
	var trail_edge := PackedVector2Array([Vector2(-0.34, 0.17), Vector2(-0.41, 0.315)])
	_fin(st, lead_edge, trail_edge, 0.0, r)


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


## A rotor's mast standing on the body under each of `type_id`'s hubs.
static func _masts(st: SurfaceTool, type_id: StringName, height: float) -> void:
	for hub: Vector3 in ROTOR_HUBS[type_id]:
		var foot := MeshKit.at(hub - Vector3(0, height, 0))
		MeshKit.column(st, foot, 0.035, 0.025, height, 6, UnitPalette3D.GUNMETAL)


## A chunky gunship: a light nose, a chin gun, and stub wings carrying two
## rocket pods a side.
static func _b_copter(st: SurfaceTool, r: FactionRamp3D) -> void:
	_skids(st, 0.12, 0.42)
	var low := UnitParts3D.rect(-0.18, 0.29, -0.08, 0.08)
	var high := UnitParts3D.rect(-0.16, 0.12, -0.07, 0.07)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.035, high, 0.205, r.base)
	var cap := Transform3D(Basis.from_scale(Vector3(1.3, 1.0, 1.0)), Vector3(0.28, 0.09, 0))
	MeshKit.ball(st, cap, 0.062, 3, 8, UnitPalette3D.LIVERY)
	var canopy := Transform3D(Basis.from_scale(Vector3(2.6, 1.0, 1.0)), Vector3(0.15, 0.165, 0))
	MeshKit.ball(st, canopy, 0.06, 3, 8, UnitPalette3D.GLASS)
	MeshKit.tube(st, MeshKit.at(Vector3(-0.29, 0.15, 0)), 0.032, 0.26, 6, r.base)
	var fin := PackedVector2Array(
		[Vector2(-0.35, 0.13), Vector2(-0.42, 0.13), Vector2(-0.42, 0.3), Vector2(-0.38, 0.3)]
	)
	UnitParts3D.profile(st, fin, -0.01, 0.01, r.dark)
	var tail_rotor := Vector3(maxf(0.02, UnitParts3D.MIN_THICKNESS), 0.12, 0.008)
	MeshKit.box(st, MeshKit.at(Vector3(-0.395, 0.22, 0.02)), tail_rotor, UnitPalette3D.ROTOR)
	MeshKit.box(st, MeshKit.at(Vector3(-0.02, 0.1, 0)), Vector3(0.11, 0.018, 0.42), r.base)
	for z in [-0.185, -0.125, 0.125, 0.185]:
		var pod := MeshKit.at(Vector3(-0.02, 0.07, z))
		MeshKit.box(st, pod, Vector3(0.13, 0.042, 0.048), r.dark)
		var nose := pod * MeshKit.at(Vector3(0.075, 0, 0))
		MeshKit.box(st, nose, Vector3(0.02, 0.036, 0.042), UnitPalette3D.STEEL)
	MeshKit.block(
		st,
		MeshKit.at(CHIN_GUN - Vector3(0, 0.025, 0)),
		Vector3(0.05, 0.03, 0.05),
		UnitPalette3D.GUNMETAL
	)
	UnitParts3D.barrel(st, MeshKit.at(CHIN_GUN), CHIN_GUN_LENGTH, 0.012, UnitPalette3D.STEEL)
	_masts(st, &"b_copter", 0.06)


## A long tandem-rotor transport: one rotor over the cab, one on a raised
## pylon at the tail, a light nose, a side door and a rear ramp.
static func _t_copter(st: SurfaceTool, r: FactionRamp3D) -> void:
	_skids(st, 0.14, 0.5)
	var low := UnitParts3D.rect(-0.32, 0.28, -0.125, 0.125)
	var high := UnitParts3D.rect(-0.3, 0.18, -0.11, 0.11)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.04, high, 0.23, r.base)
	var cap := Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.0)), Vector3(0.29, 0.1, 0))
	MeshKit.ball(st, cap, 0.1, 3, 8, UnitPalette3D.LIVERY)
	var shield := MeshKit.at(Vector3(0.235, 0.19, 0)) * Transform3D(Basis(Vector3.BACK, 0.7))
	MeshKit.box(st, shield, Vector3(0.012, 0.07, 0.2), UnitPalette3D.GLASS)
	for z in [-0.123, 0.123]:
		MeshKit.box(st, MeshKit.at(Vector3(0.04, 0.12, z)), Vector3(0.14, 0.12, 0.008), r.dark)
		MeshKit.box(st, MeshKit.at(Vector3(-0.04, 0.2, z)), Vector3(0.5, 0.03, 0.008), r.light)
	MeshKit.box(st, MeshKit.at(Vector3(-0.316, 0.1, 0)), Vector3(0.012, 0.012, 0.22), r.dark)
	for z in [-0.1, 0.1]:
		MeshKit.box(st, MeshKit.at(Vector3(-0.316, 0.07, z)), Vector3(0.012, 0.06, 0.012), r.dark)
	var pylon_low := UnitParts3D.rect(-0.3, -0.1, -0.08, 0.08)
	var pylon_high := UnitParts3D.rect(-0.27, -0.13, -0.06, 0.06)
	UnitParts3D.loft(st, Transform3D.IDENTITY, pylon_low, 0.22, pylon_high, 0.29, r.base)
	_masts(st, &"t_copter", 0.03)
