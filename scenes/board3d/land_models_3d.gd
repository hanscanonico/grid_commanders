class_name LandModels3D
extends RefCounted
## The ten land units' bodies for `UnitModels3D`: the two foot squads and the
## wheeled trucks here, the tracked hulls in `TrackedModels3D`, all built facing
## +X standing on the origin. Faction surfaces are painted `ramp.base` and
## placed by `FactionRamp3D`; every other part wears its role's colour from
## `UnitPalette3D`.
##
## Sizes step up the roster as the sprites do — a recon under a tank under a
## medium tank, the trucks and the medium tank out to the cell's edge — so a
## tier reads by bulk before it reads by detail.

## A mech squad is two heavier troopers where infantry is three riflemen.
const MECH_SCALE := 1.5
const RIFLEMAN_SCALE := 1.3
## How much broader a mech trooper stands than a rifleman.
const HEAVY_BULK := 1.15
## A mech trooper's tube: its tilt up off his shoulder, and how far ahead of the
## shoulder its warhead's tip stands.
const BAZOOKA_TILT := 15.0
const BAZOOKA_REACH := 0.16
## The rocket rack's hinge and raise, and its bottom tier's length, rise and
## width; each tier above is set back and narrowed.
const ROCKET_RACK := Vector3(-0.355, 0.13, 0)
const ROCKET_RAISE := 25.0
const ROCKET_TIER := Vector3(0.36, 0.05, 0.28)
## The missile rail's hinge and raise, and a missile's lift off it, body and tip.
const MISSILE_RAIL := Vector3(-0.35, 0.13, 0)
const MISSILE_RAISE := 32.0
const MISSILE_LIFT := 0.065
const MISSILE_BODY := 0.33
const MISSILE_TIP := 0.08


## Builds `type_id`'s body into `st`; false when it is not a land unit.
static func build(st: SurfaceTool, type_id: StringName, r: FactionRamp3D) -> bool:
	match type_id:
		&"infantry":
			for pos in [Vector3(0.12, 0, 0), Vector3(-0.12, 0, -0.2), Vector3(-0.1, 0, 0.2)]:
				soldier(st, pos, RIFLEMAN_SCALE, r, false)
		&"mech":
			for pos in [Vector3(0.1, 0, -0.13), Vector3(-0.1, 0, 0.14)]:
				soldier(st, pos, MECH_SCALE, r, true)
		&"recon":
			_recon(st, r)
		&"rockets":
			_rockets(st, r)
		&"missiles":
			_missiles(st, r)
		_:
			return TrackedModels3D.build(st, type_id, r)
	return true


## One soldier at `pos`, scaled `s`; `heavy` is a mech trooper — broader, booted
## heavier, packed bigger, shouldering a tube where a rifleman holds a rifle.
## Where a launcher's shot leaves it, in the model's frame: the rocket rack's
## middle row of mouths, the missiles' tips, a mech trooper's warhead for one
## trooper scaled `lone`; `Vector3.INF` for the rest.
static func muzzle_of(type_id: StringName, lone: float) -> Vector3:
	match type_id:
		&"mech":
			var tube := UnitParts3D.pitch(Vector3(0, 0.2, _shoulder(true)), BAZOOKA_TILT)
			return tube * Vector3(BAZOOKA_REACH, 0, 0) * lone
		&"rockets":
			var mouth := Vector3(ROCKET_TIER.x - 0.06, ROCKET_TIER.y * 1.5, 0)
			return UnitParts3D.pitch(ROCKET_RACK, ROCKET_RAISE) * mouth
		&"missiles":
			var tip := Vector3(MISSILE_BODY + MISSILE_TIP, MISSILE_LIFT, 0)
			return UnitParts3D.pitch(MISSILE_RAIL, MISSILE_RAISE) * tip
	return Vector3.INF


static func _shoulder(heavy: bool) -> float:
	return 0.062 * (HEAVY_BULK if heavy else 1.0)


static func soldier(st: SurfaceTool, pos: Vector3, s: float, r: FactionRamp3D, heavy: bool) -> void:
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * s), pos)
	var bulk := HEAVY_BULK if heavy else 1.0
	var leg := Vector3(0.05, 0.085, 0.036) if heavy else Vector3(0.042, 0.08, 0.03)
	var stance := 0.03 if heavy else 0.026
	for z in [-stance, stance]:
		MeshKit.block(st, xf * MeshKit.at(Vector3(0, 0, z)), leg, UnitPalette3D.RUBBER)
	var torso := Vector3(0.075 * bulk, 0.1, 0.1 * bulk)
	MeshKit.block(st, xf * MeshKit.at(Vector3(0, 0.075, 0)), torso, r.base)
	var shoulder := _shoulder(heavy)
	for z in [-shoulder, shoulder]:
		MeshKit.block(st, xf * MeshKit.at(Vector3(0.01, 0.1, z)), Vector3(0.04, 0.07, 0.03), r.base)
	var pack := Vector3(0.05, 0.085, 0.1) if heavy else Vector3(0.035, 0.07, 0.07)
	MeshKit.block(st, xf * MeshKit.at(Vector3(-0.045 * bulk, 0.09, 0)), pack, r.dark)
	MeshKit.ball(st, xf * MeshKit.at(Vector3(0.012, 0.205, 0)), 0.036, 3, 6, UnitPalette3D.SKIN)
	MeshKit.ball(st, xf * MeshKit.at(Vector3(-0.006, 0.222, 0)), 0.04, 3, 8, r.light)
	MeshKit.block(st, xf * MeshKit.at(Vector3(0.0, 0.2, 0)), Vector3(0.1, 0.012, 0.09), r.light)
	if heavy:
		_bazooka(st, xf * UnitParts3D.pitch(Vector3(0, 0.2, shoulder), BAZOOKA_TILT))
	else:
		var rifle := (
			xf * MeshKit.at(Vector3(0.03, 0.12, -0.04), -20) * UnitParts3D.pitch(Vector3.ZERO, 20)
		)
		UnitParts3D.barrel(st, rifle, 0.2, 0.01, UnitPalette3D.STEEL)


## A shoulder tube pivoting at the frame's origin, its warhead forward.
static func _bazooka(st: SurfaceTool, xf: Transform3D) -> void:
	var tube := xf * MeshKit.at(Vector3(BAZOOKA_REACH - 0.23, 0, 0))
	UnitParts3D.barrel(st, tube, 0.17, 0.026, UnitPalette3D.STEEL)
	MeshKit.tube(st, tube * MeshKit.at(Vector3(0.17, 0, 0)), 0.032, 0.02, 6, UnitPalette3D.RUBBER)
	UnitParts3D.nose(
		st, tube * MeshKit.at(Vector3(0.18, 0, 0)), 0.03, 0.05, 6, UnitPalette3D.ORDNANCE_TIP
	)


# --- wheeled -----------------------------------------------------------------


## A rubber tyre with a steel hub cap, its axle across Z.
static func _wheel(st: SurfaceTool, pos: Vector3, radius: float, width: float) -> void:
	MeshKit.tube(st, MeshKit.at(pos, 90), radius, width, 8, UnitPalette3D.RUBBER)
	MeshKit.tube(st, MeshKit.at(pos, 90), radius * 0.55, width + 0.012, 6, UnitPalette3D.STEEL)


static func _recon(st: SurfaceTool, r: FactionRamp3D) -> void:
	for x in [-0.2, 0.2]:
		for z in [-0.2, 0.2]:
			_wheel(st, Vector3(x, 0.094, z), 0.094, 0.075)
	var low := UnitParts3D.rect(-0.32, 0.33, -0.155, 0.155)
	var high := UnitParts3D.rect(-0.27, 0.13, -0.13, 0.13)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.075, high, 0.22, r.base)
	for z in [-0.16, 0.16]:
		MeshKit.box(st, MeshKit.at(Vector3(-0.02, 0.17, z)), Vector3(0.56, 0.02, 0.03), r.dark)
	var cabin := MeshKit.at(Vector3(0.03, 0.22, 0))
	MeshKit.block(st, cabin, Vector3(0.16, 0.055, 0.22), UnitPalette3D.LIVERY)
	var shield := MeshKit.at(Vector3(0.125, 0.25, 0)) * Transform3D(Basis(Vector3.BACK, 0.52))
	MeshKit.box(st, shield, Vector3(0.012, 0.07, 0.2), UnitPalette3D.GLASS)
	MeshKit.column(st, MeshKit.at(Vector3(-0.13, 0.22, 0)), 0.065, 0.055, 0.035, 8, r.dark)
	UnitParts3D.barrel(st, MeshKit.at(Vector3(-0.1, 0.245, 0)), 0.2, 0.014, UnitPalette3D.STEEL)
	MeshKit.block(
		st, MeshKit.at(Vector3(-0.15, 0.255, 0)), Vector3(0.06, 0.03, 0.05), UnitPalette3D.GUNMETAL
	)
	var whip := MeshKit.at(Vector3(-0.25, 0.22, -0.11))
	UnitParts3D.mast(st, whip, 0.15, 0.006, UnitPalette3D.STEEL)


## A six-wheeled truck out to the cell's edge: chassis, wheels and a cab at the
## front. The launcher trucks differ only in what rides behind the cab.
static func _truck(st: SurfaceTool, r: FactionRamp3D) -> void:
	for x in [-0.3, -0.14, 0.29]:
		for z in [-0.21, 0.21]:
			_wheel(st, Vector3(x, 0.078, z), 0.078, 0.07)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.07, 0)), Vector3(0.84, 0.06, 0.3), r.dark)
	var cab_low := UnitParts3D.rect(0.16, 0.42, -0.17, 0.17)
	var cab_high := UnitParts3D.rect(0.16, 0.33, -0.15, 0.15)
	UnitParts3D.loft(st, Transform3D.IDENTITY, cab_low, 0.13, cab_high, 0.28, r.base)
	var shield := MeshKit.at(Vector3(0.38, 0.215, 0)) * Transform3D(Basis(Vector3.BACK, 0.5))
	MeshKit.box(st, shield, Vector3(0.012, 0.08, 0.26), UnitPalette3D.GLASS)
	MeshKit.block(st, MeshKit.at(Vector3(0.37, 0.1, 0)), Vector3(0.1, 0.04, 0.32), r.light)


## A stepped rack of three tube tiers, each set back from the one below, every
## tier grooved on its top and sides so its rows read from the board's 52°.
static func _rockets(st: SurfaceTool, r: FactionRamp3D) -> void:
	_truck(st, r)
	MeshKit.block(
		st, MeshKit.at(Vector3(-0.13, 0.13, 0)), Vector3(0.06, 0.12, 0.14), UnitPalette3D.GUNMETAL
	)
	var pod := UnitParts3D.pitch(ROCKET_RACK, ROCKET_RAISE)
	var rise := ROCKET_TIER.y
	for tier in 3:
		var length := ROCKET_TIER.x - 0.06 * tier
		var width := ROCKET_TIER.z - 0.02 * tier
		var mid := pod * MeshKit.at(Vector3(length / 2.0, rise * (tier + 0.5), 0))
		MeshKit.box(st, mid, Vector3(length, rise, width), UnitPalette3D.STEEL)
		var run := length - 0.02
		for z in [-width / 6.0, width / 6.0]:
			var groove := mid * MeshKit.at(Vector3(0, rise / 2.0, z))
			MeshKit.box(st, groove, Vector3(run, 0.008, 0.016), UnitPalette3D.RUBBER)
		for side: float in [-1.0, 1.0]:
			var seam := mid * MeshKit.at(Vector3(0, 0, side * width / 2.0))
			MeshKit.box(st, seam, Vector3(run, 0.014, 0.008), UnitPalette3D.RUBBER)
		for col in 3:
			var mouth := mid * MeshKit.at(Vector3(length / 2.0, 0, (col - 1) * width / 3.0))
			var bore := Vector3(0.008, rise * 0.64, width / 3.0 - 0.025)
			MeshKit.box(st, mouth, bore, UnitPalette3D.RUBBER)


static func _missiles(st: SurfaceTool, r: FactionRamp3D) -> void:
	_truck(st, r)
	var rail := UnitParts3D.pitch(MISSILE_RAIL, MISSILE_RAISE)
	var bed := rail * MeshKit.at(Vector3(0.2, 0.01, 0))
	MeshKit.box(st, bed, Vector3(0.4, 0.03, 0.26), UnitPalette3D.GUNMETAL)
	MeshKit.block(
		st, MeshKit.at(Vector3(-0.08, 0.1, 0)), Vector3(0.05, 0.14, 0.08), UnitPalette3D.GUNMETAL
	)
	for z in [-0.075, 0.075]:
		var body := rail * MeshKit.at(Vector3(0.0, MISSILE_LIFT, z))
		UnitParts3D.barrel(st, body, MISSILE_BODY, 0.046, UnitPalette3D.ORDNANCE)
		var tip := body * MeshKit.at(Vector3(MISSILE_BODY, 0, 0))
		UnitParts3D.nose(st, tip, 0.046, MISSILE_TIP, 6, UnitPalette3D.ORDNANCE_TIP)
		MeshKit.tube(st, body * MeshKit.at(Vector3(0.1, 0, 0)), 0.05, 0.04, 6, r.base)
		MeshKit.box(
			st,
			body * MeshKit.at(Vector3(0.02, 0, 0)),
			Vector3(0.05, 0.13, 0.012),
			UnitPalette3D.GUNMETAL
		)
