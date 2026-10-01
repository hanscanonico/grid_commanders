class_name SeaModels3D
extends RefCounted
## The four ships' bodies for `UnitModels3D`, built facing +X with the origin
## on the waterline. Faction surfaces are painted `ramp.base` and placed by
## `FactionRamp3D`; every other part wears its role's colour from `UnitPalette3D`.
##
## The battleship and the lander fill the cell's length; the cruiser runs about
## four-fifths of it and the sub a little more, riding low.

## The battleship's turret guns: their thickness across the flats, how far
## apart a pair stands — wide enough that two read as two at board scale — and
## their length. Long and slim, so a turret reads as a housing with two guns.
const GUN_THICKNESS := 0.055
const GUN_SPACING := 0.1
const GUN_LENGTH := 0.18
## The cruiser's one forward gun: at the weapons' least thickness, and shorter.
const CRUISER_GUN_LENGTH := 0.12
## Where a turret's guns leave it, ahead of and above the turret's own origin.
const GUN_TRUNNION := Vector3(0.03, 0.03, 0)
const GUN_PITCH := 4.0
## The battleship's deck and forward turret, from which its shells are lobbed.
const BATTLESHIP_DECK := 0.09
const BATTLESHIP_FORE_TURRET := Vector3(0.205, BATTLESHIP_DECK, 0)
## The cruiser's deck and its one forward gun.
const CRUISER_DECK := 0.08
const CRUISER_TURRET := Vector3(0.17, CRUISER_DECK, 0)
## The sub's round hull, its centre under the waterline so only its top clears
## the water: `SUB_HULL_RISE` above the centre, the same below.
const SUB_HULL_CENTRE := -0.022
const SUB_HULL_RISE := 0.0715
## The sub's bow tip, where its torpedo leaves at the waterline.
const SUB_BOW := 0.355
## How far the stern fin's dark stub stands out of the water.
const SUB_FIN_CLEAR := 0.022
## Where the hull meets the water: the wake runs down each flank at this
## half-beam and closes in a V at the bow.
const SUB_WATERLINE := 0.106


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


## Where a ship's shot leaves it, in the model's frame: the forward gun's mouth,
## the sub's bow at the waterline; `Vector3.INF` for a ship with no gun.
static func muzzle_of(type_id: StringName) -> Vector3:
	match type_id:
		&"battleship":
			return _gun_mouth(BATTLESHIP_FORE_TURRET, GUN_LENGTH)
		&"cruiser":
			return _gun_mouth(CRUISER_TURRET, CRUISER_GUN_LENGTH)
		&"sub":
			return Vector3(SUB_BOW, 0.0, 0.0)
	return Vector3.INF


static func _gun_mouth(turret: Vector3, length: float) -> Vector3:
	var gun := UnitParts3D.pitch(turret + GUN_TRUNNION, GUN_PITCH)
	return gun * Vector3(length, 0, 0)


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


## A gunmetal turret house at `pos` turned `yaw` degrees, wider than the
## `guns` it carries `GUN_SPACING` apart, each `length` long and `thickness`
## across in `colour`.
static func _turret(
	st: SurfaceTool,
	pos: Vector3,
	yaw: float,
	guns: int,
	gun: Vector2,
	colour: Color,
) -> void:
	var xf := MeshKit.at(pos, yaw)
	var half := (guns - 1) * GUN_SPACING / 2.0 + gun.y / 2.0 + 0.03
	var low := UnitParts3D.rect(-0.06, 0.06, -half, half)
	var high := UnitParts3D.rect(-0.06, 0.035, -half + 0.012, half - 0.012)
	UnitParts3D.loft(st, xf, low, 0.0, high, 0.06, UnitPalette3D.GUNMETAL)
	var radius := gun.y / 2.0 / cos(PI / UnitParts3D.ROD_SIDES)
	for g in guns:
		var z := (float(g) - (guns - 1) / 2.0) * GUN_SPACING
		var mount := xf * UnitParts3D.pitch(GUN_TRUNNION + Vector3(0, 0, z), GUN_PITCH)
		UnitParts3D.gun(st, mount, gun.x, radius, colour)


## Two twin turrets forward, the second superfiring over the first, one aft,
## and a stepped pagoda between them.
static func _battleship(st: SurfaceTool, r: FactionRamp3D) -> void:
	_hull(st, 0.84, 0.28, BATTLESHIP_DECK, 0.22, r)
	var top := BATTLESHIP_DECK + 0.008
	var deck := UnitParts3D.rect(-0.38, 0.18, -0.12, 0.12)
	UnitParts3D.slab(st, Transform3D.IDENTITY, deck, BATTLESHIP_DECK, top, UnitPalette3D.DECK)
	var heavy := Vector2(GUN_LENGTH, GUN_THICKNESS)
	var steel := UnitPalette3D.STEEL_MID
	_turret(st, BATTLESHIP_FORE_TURRET, 0, 2, heavy, steel)
	var barbette := MeshKit.at(Vector3(0.07, top, 0))
	MeshKit.block(st, barbette, Vector3(0.12, 0.17 - top, 0.16), r.base)
	_turret(st, Vector3(0.07, 0.17, 0), 0, 2, heavy, steel)
	_turret(st, Vector3(-0.205, top, 0), 180, 2, heavy, steel)
	var tiers: Array[Vector3] = [
		Vector3(0.2, 0.08, 0.18), Vector3(0.14, 0.07, 0.14), Vector3(0.1, 0.06, 0.1)
	]
	var floor_y := top
	for tier in tiers:
		MeshKit.block(
			st, MeshKit.at(Vector3(-0.06 + (0.2 - tier.x) / 3.0, floor_y, 0)), tier, r.base
		)
		floor_y += tier.y
	var glass := MeshKit.at(Vector3(0.025, floor_y - 0.03, 0))
	MeshKit.box(st, glass, Vector3(0.01, 0.022, 0.09), UnitPalette3D.GLASS)
	MeshKit.block(st, MeshKit.at(Vector3(-0.03, floor_y, 0)), Vector3(0.07, 0.03, 0.08), r.light)
	var mast := MeshKit.at(Vector3(-0.03, floor_y + 0.03, 0))
	UnitParts3D.mast(st, mast, 0.08, 0.0, UnitPalette3D.STEEL)
	var yard := (
		MeshKit.at(Vector3(-0.03, floor_y + 0.09, -0.05))
		* Transform3D(Basis(Vector3.RIGHT, PI / 2.0))
	)
	UnitParts3D.mast(st, yard, 0.1, 0.0, UnitPalette3D.STEEL)
	MeshKit.column(st, MeshKit.at(Vector3(-0.13, top + 0.08, 0)), 0.04, 0.035, 0.08, 8, r.dark)
	var funnel_cap := MeshKit.at(Vector3(-0.13, top + 0.16, 0))
	MeshKit.column(st, funnel_cap, 0.036, 0.036, 0.012, 8, UnitPalette3D.RUBBER)


## One gun forward in a gunmetal house, a steel missile block aft with its cells
## open on top — the anti-air and anti-sub cue — and a radar dish on a mast
## tall enough to clear the superstructure.
static func _cruiser(st: SurfaceTool, r: FactionRamp3D) -> void:
	_hull(st, 0.68, 0.22, CRUISER_DECK, 0.2, r)
	var top := CRUISER_DECK + 0.007
	var deck := UnitParts3D.rect(-0.31, 0.1, -0.09, 0.09)
	UnitParts3D.slab(st, Transform3D.IDENTITY, deck, CRUISER_DECK, top, UnitPalette3D.PLATING)
	var light_gun := Vector2(CRUISER_GUN_LENGTH, UnitParts3D.MIN_THICKNESS)
	_turret(st, CRUISER_TURRET, 0, 1, light_gun, UnitPalette3D.STEEL)
	var low := UnitParts3D.rect(-0.12, 0.06, -0.08, 0.08)
	var high := UnitParts3D.rect(-0.09, 0.03, -0.06, 0.06)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, top, high, 0.21, r.base)
	MeshKit.box(
		st, MeshKit.at(Vector3(0.043, 0.18, 0)), Vector3(0.02, 0.025, 0.12), UnitPalette3D.GLASS
	)
	UnitParts3D.mast(st, MeshKit.at(Vector3(-0.04, 0.21, 0)), 0.127, 0.0, UnitPalette3D.STEEL)
	var dish := MeshKit.at(Vector3(-0.04, 0.32, 0)) * Transform3D(Basis(Vector3.BACK, 0.6))
	MeshKit.column(st, dish, 0.012, 0.065, 0.03, 8, UnitPalette3D.STEEL)
	var block := Vector3(-0.21, top, 0)
	MeshKit.block(st, MeshKit.at(block), Vector3(0.12, 0.06, 0.12), UnitPalette3D.STEEL)
	for row in 2:
		for col in 3:
			var cell := block + Vector3(-0.025 + 0.05 * row, 0.06, -0.04 + 0.04 * col)
			MeshKit.box(st, MeshKit.at(cell), Vector3(0.03, 0.008, 0.024), UnitPalette3D.RUBBER)
	var stern := UnitParts3D.rect(-0.335, -0.29, -0.07, 0.07)
	UnitParts3D.slab(st, Transform3D.IDENTITY, stern, top, top + 0.003, r.light)


static func _lander(st: SurfaceTool, r: FactionRamp3D) -> void:
	_hull(st, 0.8, 0.34, 0.07, 0.07, r)
	var well := UnitParts3D.rect(-0.18, 0.3, -0.13, 0.13)
	UnitParts3D.slab(st, Transform3D.IDENTITY, well, 0.07, 0.074, UnitPalette3D.GUNMETAL)
	MeshKit.block(
		st,
		MeshKit.at(Vector3(0.1, 0.074, -0.04)),
		Vector3(0.1, 0.06, 0.08),
		UnitPalette3D.STEEL_LIGHT
	)
	MeshKit.block(
		st,
		MeshKit.at(Vector3(-0.02, 0.074, 0.05)),
		Vector3(0.1, 0.06, 0.08),
		UnitPalette3D.STEEL_LIGHT
	)
	for z in [-0.155, 0.155]:
		MeshKit.block(st, MeshKit.at(Vector3(0.04, 0.07, z)), Vector3(0.62, 0.07, 0.03), r.base)
		MeshKit.block(st, MeshKit.at(Vector3(0.04, 0.14, z)), Vector3(0.62, 0.012, 0.036), r.light)
	var ramp := UnitParts3D.pitch(Vector3(0.34, 0.07, 0), 60)
	MeshKit.box(st, ramp * MeshKit.at(Vector3(0.06, 0, 0)), Vector3(0.12, 0.02, 0.3), r.dark)
	var bridge_low := UnitParts3D.rect(-0.38, -0.2, -0.15, 0.15)
	var bridge_high := UnitParts3D.rect(-0.38, -0.23, -0.13, 0.13)
	UnitParts3D.loft(st, Transform3D.IDENTITY, bridge_low, 0.07, bridge_high, 0.24, r.base)
	MeshKit.box(
		st, MeshKit.at(Vector3(-0.225, 0.2, 0)), Vector3(0.012, 0.035, 0.22), UnitPalette3D.GLASS
	)
	MeshKit.block(st, MeshKit.at(Vector3(-0.31, 0.24, 0)), Vector3(0.08, 0.04, 0.08), r.light)
	UnitParts3D.mast(st, MeshKit.at(Vector3(-0.31, 0.28, 0)), 0.06, 0.0, UnitPalette3D.STEEL)


## A round hull sunk to its top third, so the sail is the mass that shows, and
## a white wake along the waterline and off the bow.
static func _sub(st: SurfaceTool, r: FactionRamp3D) -> void:
	var squash := Basis.from_scale(Vector3(1.0, SUB_HULL_RISE / 0.11, 1.0))
	MeshKit.tube(
		st, Transform3D(squash, Vector3(-0.02, SUB_HULL_CENTRE, 0)), 0.11, 0.46, 10, r.base
	)
	var bow := Transform3D(
		squash * Basis.from_scale(Vector3(1.4, 1, 1)), Vector3(0.21, SUB_HULL_CENTRE, 0)
	)
	MeshKit.ball(st, bow, 0.104, 4, 10, r.base)
	var stern := Transform3D(squash, Vector3(-0.25, SUB_HULL_CENTRE, 0))
	UnitParts3D.nose(st, stern.rotated_local(Vector3.UP, PI), 0.108, 0.11, 10, r.dark)
	var deck_line := SUB_HULL_CENTRE + SUB_HULL_RISE
	var low := UnitParts3D.rect(-0.02, 0.14, -0.036, 0.036)
	var high := UnitParts3D.rect(0.01, 0.11, -0.028, 0.028)
	UnitParts3D.loft(st, Transform3D.IDENTITY, low, deck_line - 0.02, high, 0.205, r.base)
	MeshKit.box(st, MeshKit.at(Vector3(0.07, 0.16, 0)), Vector3(0.03, 0.012, 0.16), r.dark)
	UnitParts3D.mast(st, MeshKit.at(Vector3(0.04, 0.205, 0)), 0.06, 0.0, UnitPalette3D.STEEL)
	var rudder := MeshKit.at(Vector3(-0.33, SUB_HULL_CENTRE, 0))
	MeshKit.box(st, rudder, Vector3(0.05, 0.012, 0.18), UnitPalette3D.RUBBER)
	var stub := MeshKit.at(Vector3(-0.32, SUB_HULL_CENTRE - SUB_HULL_RISE, 0))
	MeshKit.block(
		st, stub, Vector3(0.04, SUB_HULL_RISE + SUB_FIN_CLEAR, 0.012), UnitPalette3D.RUBBER
	)
	MeshKit.box(st, MeshKit.at(Vector3(0.0, deck_line, 0)), Vector3(0.36, 0.008, 0.05), r.light)
	_wake(st)


## The sub's wake, laid on the water against the hull: one strip down each
## flank at the waterline, closing in a V on the bow.
static func _wake(st: SurfaceTool) -> void:
	var foam := UnitPalette3D.WAKE
	var shoulder := 0.21
	for side: float in [-1.0, 1.0]:
		var flank := MeshKit.at(Vector3((shoulder - 0.26) / 2.0, 0.004, side * SUB_WATERLINE))
		MeshKit.box(st, flank, Vector3(shoulder + 0.26, 0.008, 0.02), foam)
		var from := Vector2(shoulder, side * SUB_WATERLINE)
		var to := Vector2(SUB_BOW + 0.01, 0.0)
		var run := to - from
		var bow := MeshKit.at(Vector3((from.x + to.x) / 2.0, 0.004, (from.y + to.y) / 2.0))
		bow = bow * Transform3D(Basis(Vector3.UP, -run.angle()), Vector3.ZERO)
		MeshKit.box(st, bow, Vector3(run.length() + 0.01, 0.008, 0.02), foam)
