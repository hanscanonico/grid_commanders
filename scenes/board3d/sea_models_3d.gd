class_name SeaModels3D
extends RefCounted
## The four ships' bodies for `UnitModels3D`, built facing +X with the origin
## on the waterline. Faction surfaces are painted `ramp.base` and placed by
## `FactionRamp3D`; every other part wears its role's colour from `UnitPalette3D`.


## Builds `type_id`'s body into `st`; false when it is not a ship.
static func build(st: SurfaceTool, type_id: StringName, r: FactionRamp3D) -> bool:
	match type_id:
		&"battleship":
			_battleship(st, r)
		&"cruiser":
			_cruiser(st, r)
		&"lander":
			_lander(st, r)
		&"sub":
			_sub(st, r)
		_:
			return false
	return true


## A hull from keel (y -0.06) to deck: a pointed bow at +X, a narrower keel,
## and a dark boot-topping band where it meets the water.
static func _hull(
	st: SurfaceTool, length: float, beam: float, deck: float, bow: float, r: FactionRamp3D
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
	UnitParts3D.loft(st, Transform3D.IDENTITY, keel, -0.06, mid, 0.02, r.dark)
	UnitParts3D.loft(st, Transform3D.IDENTITY, mid, 0.02, top, deck, r.base)


static func _turret(st: SurfaceTool, pos: Vector3, yaw: float, guns: int, r: FactionRamp3D) -> void:
	var xf := (
		MeshKit.at(pos, yaw) * Transform3D(Basis.from_scale(Vector3.ONE * (1.0 + guns * 0.12)))
	)
	var low := UnitParts3D.rect(-0.05, 0.05, -0.05, 0.05)
	var high := UnitParts3D.rect(-0.05, 0.03, -0.04, 0.04)
	UnitParts3D.loft(st, xf, low, 0.0, high, 0.05, r.base)
	for g in guns:
		var z := (float(g) - (guns - 1) / 2.0) * 0.026
		var gun := xf * UnitParts3D.pitch(Vector3(0.03, 0.028, z), 4)
		UnitParts3D.barrel(st, gun, 0.11, 0.01, UnitPalette3D.STEEL)


static func _battleship(st: SurfaceTool, r: FactionRamp3D) -> void:
	_hull(st, 0.84, 0.28, 0.1, 0.22, r)
	var deck := UnitParts3D.rect(-0.38, 0.18, -0.12, 0.12)
	UnitParts3D.slab(st, Transform3D.IDENTITY, deck, 0.1, 0.108, UnitPalette3D.DECK)
	_turret(st, Vector3(0.23, 0.108, 0), 0, 3, r)
	_turret(st, Vector3(0.1, 0.13, 0), 0, 3, r)
	MeshKit.block(st, MeshKit.at(Vector3(0.1, 0.108, 0)), Vector3(0.1, 0.022, 0.1), r.base)
	_turret(st, Vector3(-0.24, 0.108, 0), 180, 2, r)
	MeshKit.block(st, MeshKit.at(Vector3(-0.08, 0.108, 0)), Vector3(0.2, 0.09, 0.17), r.base)
	MeshKit.block(st, MeshKit.at(Vector3(-0.05, 0.198, 0)), Vector3(0.12, 0.08, 0.12), r.base)
	MeshKit.box(
		st, MeshKit.at(Vector3(0.012, 0.25, 0)), Vector3(0.01, 0.025, 0.1), UnitPalette3D.GLASS
	)
	MeshKit.block(st, MeshKit.at(Vector3(-0.04, 0.278, 0)), Vector3(0.07, 0.04, 0.08), r.light)
	UnitParts3D.mast(st, MeshKit.at(Vector3(-0.04, 0.318, 0)), 0.12, 0.012, UnitPalette3D.STEEL)
	var yard := MeshKit.at(Vector3(-0.04, 0.39, -0.05), -90)
	UnitParts3D.barrel(st, yard, 0.1, 0.006, UnitPalette3D.STEEL)
	MeshKit.column(st, MeshKit.at(Vector3(-0.17, 0.198, 0)), 0.04, 0.035, 0.1, 8, r.dark)
	MeshKit.column(
		st, MeshKit.at(Vector3(-0.17, 0.298, 0)), 0.036, 0.036, 0.012, 8, UnitPalette3D.RUBBER
	)


static func _cruiser(st: SurfaceTool, r: FactionRamp3D) -> void:
	_hull(st, 0.8, 0.22, 0.09, 0.26, r)
	var deck := UnitParts3D.rect(-0.38, 0.12, -0.09, 0.09)
	UnitParts3D.slab(st, Transform3D.IDENTITY, deck, 0.09, 0.097, r.dark)
	_turret(st, Vector3(0.2, 0.097, 0), 0, 1, r)
	for row in 2:
		for col in 3:
			var cell := Vector3(0.07 + 0.03 * row, 0.097, -0.03 + 0.03 * col)
			MeshKit.block(st, MeshKit.at(cell), Vector3(0.022, 0.012, 0.022), r.dark)
	var low := UnitParts3D.rect(-0.17, 0.02, -0.08, 0.08)
	var high := UnitParts3D.rect(-0.14, -0.01, -0.06, 0.06)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.097, high, 0.23, r.base)
	MeshKit.box(
		st, MeshKit.at(Vector3(0.0, 0.2, 0)), Vector3(0.02, 0.025, 0.14), UnitPalette3D.GLASS
	)
	UnitParts3D.mast(st, MeshKit.at(Vector3(-0.08, 0.23, 0)), 0.15, 0.015, UnitPalette3D.STEEL)
	MeshKit.box(st, MeshKit.at(Vector3(-0.08, 0.33, 0)), Vector3(0.03, 0.04, 0.12), r.light)
	MeshKit.block(st, MeshKit.at(Vector3(-0.22, 0.097, 0)), Vector3(0.07, 0.07, 0.07), r.dark)
	var stern := UnitParts3D.rect(-0.37, -0.28, -0.07, 0.07)
	UnitParts3D.slab(st, Transform3D.IDENTITY, stern, 0.097, 0.1, r.light)


static func _lander(st: SurfaceTool, r: FactionRamp3D) -> void:
	_hull(st, 0.8, 0.34, 0.07, 0.07, r)
	var well := UnitParts3D.rect(-0.18, 0.3, -0.13, 0.13)
	UnitParts3D.slab(st, Transform3D.IDENTITY, well, 0.07, 0.074, UnitPalette3D.GUNMETAL)
	MeshKit.block(
		st, MeshKit.at(Vector3(0.1, 0.074, -0.04)), Vector3(0.1, 0.06, 0.08), UnitPalette3D.DECK
	)
	MeshKit.block(
		st, MeshKit.at(Vector3(-0.02, 0.074, 0.05)), Vector3(0.1, 0.06, 0.08), UnitPalette3D.DECK
	)
	for z in [-0.155, 0.155]:
		MeshKit.block(st, MeshKit.at(Vector3(0.04, 0.07, z)), Vector3(0.62, 0.07, 0.03), r.base)
		MeshKit.block(st, MeshKit.at(Vector3(0.04, 0.14, z)), Vector3(0.62, 0.012, 0.036), r.light)
	var ramp := UnitParts3D.pitch(Vector3(0.34, 0.07, 0), 70)
	MeshKit.box(st, ramp * MeshKit.at(Vector3(0.06, 0, 0)), Vector3(0.12, 0.02, 0.3), r.dark)
	var bridge_low := UnitParts3D.rect(-0.38, -0.2, -0.15, 0.15)
	var bridge_high := UnitParts3D.rect(-0.38, -0.23, -0.13, 0.13)
	UnitParts3D.loft(st, Transform3D.IDENTITY, bridge_low, 0.07, bridge_high, 0.2, r.base)
	MeshKit.box(
		st, MeshKit.at(Vector3(-0.225, 0.17, 0)), Vector3(0.012, 0.03, 0.22), UnitPalette3D.GLASS
	)
	MeshKit.block(st, MeshKit.at(Vector3(-0.31, 0.2, 0)), Vector3(0.08, 0.04, 0.08), r.light)
	UnitParts3D.mast(st, MeshKit.at(Vector3(-0.31, 0.24, 0)), 0.06, 0.008, UnitPalette3D.STEEL)


static func _sub(st: SurfaceTool, r: FactionRamp3D) -> void:
	var squash := Basis.from_scale(Vector3(1.0, 0.65, 1.0))
	MeshKit.tube(st, Transform3D(squash, Vector3(-0.02, 0.02, 0)), 0.11, 0.56, 10, r.base)
	var bow := Transform3D(squash * Basis.from_scale(Vector3(1.4, 1, 1)), Vector3(0.26, 0.02, 0))
	MeshKit.ball(st, bow, 0.108, 4, 10, r.base)
	UnitParts3D.nose(
		st,
		Transform3D(squash, Vector3(-0.3, 0.02, 0)).rotated_local(Vector3.UP, PI),
		0.108,
		0.12,
		10,
		r.dark
	)
	var low := UnitParts3D.rect(0.0, 0.16, -0.035, 0.035)
	var high := UnitParts3D.rect(0.03, 0.13, -0.028, 0.028)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, 0.06, high, 0.2, r.dark)
	MeshKit.box(st, MeshKit.at(Vector3(0.09, 0.15, 0)), Vector3(0.03, 0.012, 0.16), r.dark)
	UnitParts3D.mast(st, MeshKit.at(Vector3(0.06, 0.2, 0)), 0.05, 0.006, UnitPalette3D.STEEL)
	MeshKit.box(
		st, MeshKit.at(Vector3(-0.38, 0.03, 0)), Vector3(0.05, 0.012, 0.18), UnitPalette3D.GUNMETAL
	)
	MeshKit.box(
		st, MeshKit.at(Vector3(-0.38, 0.03, 0)), Vector3(0.05, 0.14, 0.012), UnitPalette3D.GUNMETAL
	)
	MeshKit.box(st, MeshKit.at(Vector3(0.0, 0.085, 0)), Vector3(0.42, 0.008, 0.05), r.light)
