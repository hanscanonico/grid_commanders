class_name TrackedModels3D
extends RefCounted
## The five tracked hulls for `LandModels3D`: tank, medium tank, APC, artillery
## and anti-air, built facing +X standing on the origin, all on one set of
## tracks whose road wheels are the same hex hub on every hull.
##
## What tells them apart at board scale is stated in their shapes: the medium
## tank is the biggest hull with the thickest gun, the APC the lowest with an
## open bay, the artillery's barrel the tallest thing on the land roster, and
## the anti-air's guns one dark mount raised steeply.

## Every road wheel's hub, whatever the track it runs on.
const ROAD_WHEEL := 0.042
## The guns' radii: the medium tank's is the tank's and three-fifths again.
const TANK_GUN := 0.029
const MD_TANK_GUN := 0.046
## The howitzer's trunnion, elevation and muzzle reach from it: the gun is built
## from them and the cut-in's muzzle flash is placed by them.
const HOWITZER_PIVOT := Vector3(-0.19, 0.21, 0)
const HOWITZER_ELEVATION := 53.0
const HOWITZER_REACH := 0.68
## The tank's deck: its hull a step under the medium tank's, so the tiers part.
const TANK_DECK := 0.18


static func build(st: SurfaceTool, type_id: StringName, r: FactionRamp3D) -> bool:
	match type_id:
		&"apc":
			_apc(st, r)
		&"tank":
			_tank(st, r)
		&"md_tank":
			_md_tank(st, r)
		&"artillery":
			_artillery(st, r)
		&"anti_air":
			_anti_air(st, r)
		_:
			return false
	return true


## Where a hull's shot leaves it, in the model's frame, when that is not the
## front of its footprint: `Vector3.INF` for every hull but the artillery's.
static func muzzle_of(type_id: StringName) -> Vector3:
	if type_id != &"artillery":
		return Vector3.INF
	return UnitParts3D.pitch(HOWITZER_PIVOT, HOWITZER_ELEVATION) * Vector3(HOWITZER_REACH, 0, 0)


## Two tracks under a hull, with `wheels` steel road-wheel hubs a side and a
## guard over each run.
static func _tracks(
	st: SurfaceTool,
	length: float,
	height: float,
	width: float,
	gap: float,
	r: FactionRamp3D,
	wheels: int = 4
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
		for i in wheels:
			var x := lerpf(-l + height * 0.55, l - height * 0.55, float(i) / float(wheels - 1))
			var hub := Vector3(x, ROAD_WHEEL + 0.018, side * (gap + width / 2.0))
			MeshKit.tube(st, MeshKit.at(hub, 90), ROAD_WHEEL, 0.016, 6, UnitPalette3D.STEEL)
		var guard := Vector3(0, height + 0.012, z)
		MeshKit.box(st, MeshKit.at(guard), Vector3(length * 0.96, 0.024, width + 0.03), r.dark)


## A low, long hull: a raised cab at the front with a slit visor, and behind it
## an open bay ribbed across its dark floor.
static func _apc(st: SurfaceTool, r: FactionRamp3D) -> void:
	_tracks(st, 0.79, 0.12, 0.14, 0.215, r)
	var low := UnitParts3D.rect(-0.4, 0.4, -0.19, 0.19)
	var high := UnitParts3D.rect(-0.39, 0.34, -0.18, 0.18)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.08, high, 0.17, r.base)
	MeshKit.block(st, MeshKit.at(Vector3(-0.15, 0.17, 0)), Vector3(0.48, 0.006, 0.34), r.dark)
	for z in [-0.165, 0.165]:
		MeshKit.block(st, MeshKit.at(Vector3(-0.15, 0.17, z)), Vector3(0.48, 0.045, 0.03), r.base)
	MeshKit.block(st, MeshKit.at(Vector3(-0.375, 0.17, 0)), Vector3(0.03, 0.045, 0.36), r.base)
	for x in [-0.31, -0.22, -0.13, -0.04, 0.05]:
		MeshKit.box(st, MeshKit.at(Vector3(x, 0.205, 0)), Vector3(0.03, 0.02, 0.33), r.base)
	var cab_low := UnitParts3D.rect(0.08, 0.36, -0.17, 0.17)
	var cab_high := UnitParts3D.rect(0.08, 0.25, -0.15, 0.15)
	UnitParts3D.loft(st, Transform3D.IDENTITY, cab_low, 0.17, cab_high, 0.265, r.base)
	var slit := MeshKit.at(Vector3(0.305, 0.235, 0)) * Transform3D(Basis(Vector3.BACK, 0.94))
	MeshKit.box(st, slit, Vector3(0.012, 0.035, 0.24), UnitPalette3D.GLASS)
	for z in [-0.07, 0.07]:
		MeshKit.block(st, MeshKit.at(Vector3(0.15, 0.265, z)), Vector3(0.08, 0.015, 0.09), r.light)


static func _tank(st: SurfaceTool, r: FactionRamp3D) -> void:
	_tracks(st, 0.72, 0.13, 0.16, 0.23, r)
	var low := UnitParts3D.rect(-0.35, 0.35, -0.2, 0.2)
	var high := UnitParts3D.rect(-0.33, 0.21, -0.19, 0.19)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.09, high, TANK_DECK, r.base)
	MeshKit.column(st, MeshKit.at(Vector3(-0.04, TANK_DECK, 0)), 0.165, 0.165, 0.02, 8, r.dark)
	var turret := MeshKit.at(Vector3(-0.04, TANK_DECK + 0.02, 0))
	MeshKit.column(st, turret, 0.15, 0.115, 0.085, 8, r.base)
	var cupola := MeshKit.at(Vector3(-0.08, TANK_DECK + 0.105, 0.04))
	MeshKit.column(st, cupola, 0.045, 0.04, 0.025, 6, r.light)
	var gun := MeshKit.at(Vector3(0.1, TANK_DECK + 0.06, 0))
	MeshKit.box(st, gun, Vector3(0.05, 0.06, 0.08), UnitPalette3D.GUNMETAL)
	UnitParts3D.barrel(st, gun, 0.29, TANK_GUN, UnitPalette3D.STEEL)


## Out to the cell's edge: a taller hull skirted over its six-wheeled tracks, a
## stepped two-tier turret and a thick gun ending in a boxy muzzle brake.
static func _md_tank(st: SurfaceTool, r: FactionRamp3D) -> void:
	_tracks(st, 0.84, 0.15, 0.18, 0.25, r, 6)
	for side: float in [-1.0, 1.0]:
		var skirt := MeshKit.at(Vector3(0, 0.135, side * 0.35))
		MeshKit.box(st, skirt, Vector3(0.8, 0.06, 0.02), r.base)
	var low := UnitParts3D.rect(-0.42, 0.42, -0.25, 0.25)
	var high := UnitParts3D.rect(-0.4, 0.28, -0.24, 0.24)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.1, high, 0.235, r.base)
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
	UnitParts3D.loft(st, Transform3D.IDENTITY, t_low, 0.235, t_high, 0.33, r.base)
	var tier_low := UnitParts3D.rect(-0.2, 0.03, -0.11, 0.11)
	var tier_high := UnitParts3D.rect(-0.18, 0.01, -0.1, 0.1)
	UnitParts3D.loft(st, Transform3D.IDENTITY, tier_low, 0.33, tier_high, 0.38, r.base)
	MeshKit.column(st, MeshKit.at(Vector3(-0.1, 0.38, -0.05)), 0.04, 0.035, 0.03, 6, r.light)
	MeshKit.block(st, MeshKit.at(Vector3(-0.3, 0.235, 0)), Vector3(0.08, 0.06, 0.26), r.base)
	var gun := MeshKit.at(Vector3(0.15, 0.285, 0))
	MeshKit.box(st, gun, Vector3(0.06, 0.09, 0.12), UnitPalette3D.GUNMETAL)
	UnitParts3D.barrel(st, gun, 0.24, MD_TANK_GUN, UnitPalette3D.STEEL)
	var brake := MeshKit.at(Vector3(0.395, 0.285, 0))
	MeshKit.box(st, brake, Vector3(0.05, 0.11, 0.12), UnitPalette3D.GUNMETAL)


## One very long barrel raised steeply from an open box mount over the rear
## third, so it rises over the low hull higher than anything else on land.
static func _artillery(st: SurfaceTool, r: FactionRamp3D) -> void:
	_tracks(st, 0.66, 0.12, 0.14, 0.2, r)
	var low := UnitParts3D.rect(-0.31, 0.32, -0.18, 0.18)
	var high := UnitParts3D.rect(-0.3, 0.22, -0.17, 0.17)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.08, high, 0.155, r.base)
	var mount := Vector3(HOWITZER_PIVOT.x, 0.155, 0)
	MeshKit.block(st, MeshKit.at(mount), Vector3(0.18, 0.02, 0.18), UnitPalette3D.GUNMETAL)
	for z in [-0.08, 0.08]:
		var cheek := MeshKit.at(mount + Vector3(0, 0, z))
		MeshKit.block(st, cheek, Vector3(0.16, 0.08, 0.025), UnitPalette3D.GUNMETAL)
	var back := MeshKit.at(mount + Vector3(-0.08, 0, 0))
	MeshKit.block(st, back, Vector3(0.025, 0.05, 0.18), UnitPalette3D.GUNMETAL)
	var gun := UnitParts3D.pitch(HOWITZER_PIVOT, HOWITZER_ELEVATION)
	MeshKit.tube(st, gun * MeshKit.at(Vector3(0.04, 0, 0)), 0.045, 0.16, 8, UnitPalette3D.GUNMETAL)
	var breech := gun * MeshKit.at(Vector3(-0.04, 0, 0))
	UnitParts3D.barrel(st, breech, HOWITZER_REACH + 0.04, 0.03, UnitPalette3D.STEEL)
	var mouth := gun * MeshKit.at(Vector3(HOWITZER_REACH - 0.02, 0, 0))
	MeshKit.tube(st, mouth, 0.038, 0.04, 6, UnitPalette3D.GUNMETAL)


## A 2×2 block of short steel barrels raised to 45° out of one dark gunmetal
## mount — a quad, where the artillery has one long tube — and a small radar
## dish behind.
static func _anti_air(st: SurfaceTool, r: FactionRamp3D) -> void:
	_tracks(st, 0.68, 0.12, 0.15, 0.22, r)
	var low := UnitParts3D.rect(-0.33, 0.33, -0.19, 0.19)
	var high := UnitParts3D.rect(-0.31, 0.2, -0.18, 0.18)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.08, high, 0.18, r.base)
	MeshKit.column(st, MeshKit.at(Vector3(-0.04, 0.18, 0)), 0.13, 0.12, 0.03, 8, r.base)
	var mount := MeshKit.at(Vector3(-0.04, 0.21, 0))
	MeshKit.block(st, mount, Vector3(0.15, 0.08, 0.17), UnitPalette3D.GUNMETAL)
	for z in [-0.042, 0.042]:
		for lift in [-0.034, 0.034]:
			var gun := (
				UnitParts3D.pitch(Vector3(-0.01, 0.25, z), 45) * MeshKit.at(Vector3(0, lift, 0))
			)
			UnitParts3D.barrel(st, gun, 0.17, 0.0, UnitPalette3D.STEEL)
	UnitParts3D.mast(st, MeshKit.at(Vector3(-0.25, 0.18, 0)), 0.1, 0.0, UnitPalette3D.STEEL)
	var dish := MeshKit.at(Vector3(-0.25, 0.27, 0)) * Transform3D(Basis(Vector3.BACK, 0.5))
	MeshKit.column(st, dish, 0.012, 0.06, 0.03, 8, UnitPalette3D.GUNMETAL)
