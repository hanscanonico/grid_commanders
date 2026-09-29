class_name CommanderFigure3D
extends RefCounted
## A general as a chibi low-poly figure: the meshes `CommanderActor3D` hangs on
## its pivots, built from a `CommanderLooks3D` look and the army's theme. Node-
## free, so the figure's geometry is checkable without a scene.
##
## Each part is built in its own pivot's frame: the figure faces -Z, its right
## hand is on +X, and a limb hangs down from its pivot. `PIVOTS` places every
## pivot on its parent at rest, and `rest_mesh` merges the lot where they stand.

const HEIGHT := 0.62
const HIP_Y := 0.19
## Where the top of the head and the eyes are above the head's own pivot.
const HEAD_TOP := HEIGHT - 0.37
const EYE_Y := 0.105
const HAND := Vector3(0, -0.17, 0)

const PARTS: Array[StringName] = [
	&"hips", &"torso", &"head", &"arm_l", &"arm_r", &"leg_l", &"leg_r", &"prop"
]
const PARENTS: Dictionary[StringName, StringName] = {
	&"hips": &"",
	&"torso": &"hips",
	&"head": &"torso",
	&"arm_l": &"torso",
	&"arm_r": &"torso",
	&"leg_l": &"hips",
	&"leg_r": &"hips",
	&"prop": &"arm_r",
}
const PIVOTS: Dictionary[StringName, Vector3] = {
	&"hips": Vector3(0, HIP_Y, 0),
	&"torso": Vector3(0, 0.035, 0),
	&"head": Vector3(0, 0.145, 0),
	&"arm_l": Vector3(-0.13, 0.12, 0),
	&"arm_r": Vector3(0.13, 0.12, 0),
	&"leg_l": Vector3(-0.05, 0, 0),
	&"leg_r": Vector3(0.05, 0, 0),
	&"prop": HAND,
}

## What the figure knows how to draw, column by column. `CommanderLooks3D` rows
## are held to these by `tests/unit/test_commander_looks_3d.gd`.
const STYLES: Array[StringName] = [
	&"bald",
	&"buzz",
	&"short",
	&"sidepart",
	&"long",
	&"ponytail",
	&"bun",
	&"braid",
	&"bob",
	&"curly",
	&"spiky",
	&"hood",
]
const ACCESSORIES: Array[StringName] = [
	&"none",
	&"glasses",
	&"goggles",
	&"eyepatch",
	&"headset",
	&"headband",
	&"bandana",
	&"fieldcap",
	&"cap",
	&"hood",
	&"visor",
	&"scar",
]
const FACIALS: Array[StringName] = [&"none", &"beard", &"stubble", &"mustache"]
const COLLARS: Array[StringName] = [&"v", &"mandarin", &"double"]
const CHESTS: Array[StringName] = [
	&"plain",
	&"sash",
	&"crossbelt",
	&"bandolier",
	&"boards",
	&"epaulette",
	&"placket",
	&"loops",
	&"lanyard",
	&"pouch",
	&"mapcase",
	&"harness",
	&"scarf",
]

const INK := Color8(19, 23, 27)
const KIT := Color8(43, 47, 52)
const GOLD := Color8(224, 169, 46)
const GLASS := Color8(188, 214, 224)
const SHIRT := Color8(232, 226, 208)
const LEATHER := Color8(95, 62, 38)
const TROUSERS := Color8(52, 56, 64)
const BOOTS := Color8(34, 30, 28)
const MOUTH := Color8(96, 44, 42)
const SCAR := Color8(181, 107, 90)
const CANVAS := Color8(112, 106, 72)
const VISOR := Color8(62, 112, 92)

## The head's box, in its pivot's frame.
const HEAD_SIZE := Vector3(0.22, 0.2, 0.2)
const HEAD_Y := 0.11
const FACE_Z := -0.1
## The torso: a box narrower at the waist than the shoulders.
const TORSO_H := 0.14
const WAIST := Vector2(0.19, 0.13)
const CHEST := Vector2(0.25, 0.15)


## One part's mesh in its own pivot's frame, or null for a part with nothing
## to draw (a general with no hand prop).
static func part_mesh(
	part: StringName, look: Dictionary, theme: CommanderVisuals.FactionTheme
) -> ArrayMesh:
	if part == &"prop" and look[&"prop"] == &"none":
		return null
	var st := MeshKit.begin()
	build_part(st, part, Transform3D.IDENTITY, look, theme)
	return st.commit()


## The whole figure at rest, every part where its pivot stands: the model the
## height and footprint contract is read off.
static func rest_mesh(look: Dictionary, theme: CommanderVisuals.FactionTheme) -> ArrayMesh:
	var st := MeshKit.begin()
	for part in PARTS:
		build_part(st, part, rest_transform(part), look, theme)
	return st.commit()


## Where `part`'s pivot stands in the figure's own frame at rest.
static func rest_transform(part: StringName) -> Transform3D:
	var xf := Transform3D(Basis.IDENTITY, PIVOTS[part])
	var parent: StringName = PARENTS[part]
	if parent.is_empty():
		return xf
	return rest_transform(parent) * xf


static func build_part(
	st: SurfaceTool,
	part: StringName,
	xf: Transform3D,
	look: Dictionary,
	theme: CommanderVisuals.FactionTheme
) -> void:
	match part:
		&"hips":
			_hips(st, xf, theme)
		&"torso":
			_torso(st, xf, look, theme)
		&"head":
			CommanderHead3D.build(st, xf, look, theme)
		&"arm_l", &"arm_r":
			_arm(st, xf, look, theme)
		&"leg_l", &"leg_r":
			_leg(st, xf)
		&"prop":
			CommanderProps3D.build(st, xf, look[&"prop"])


static func at(xf: Transform3D, pos: Vector3, roll: float = 0.0) -> Transform3D:
	return xf * Transform3D(Basis(Vector3.BACK, roll), pos)


## A box whose bottom face is `bottom` (x by z) and top face `top`, standing
## on the frame's origin.
static func frustum_box(
	st: SurfaceTool, xf: Transform3D, bottom: Vector2, top: Vector2, height: float, color: Color
) -> void:
	var b := bottom / 2.0
	var t := top / 2.0
	var c: Array[Vector3] = [
		xf * Vector3(-b.x, 0, -b.y),
		xf * Vector3(b.x, 0, -b.y),
		xf * Vector3(b.x, 0, b.y),
		xf * Vector3(-b.x, 0, b.y),
		xf * Vector3(-t.x, height, -t.y),
		xf * Vector3(t.x, height, -t.y),
		xf * Vector3(t.x, height, t.y),
		xf * Vector3(-t.x, height, t.y),
	]
	MeshKit.quad(st, c[4], c[7], c[6], c[5], color)
	MeshKit.quad(st, c[0], c[1], c[2], c[3], color)
	MeshKit.quad(st, c[3], c[2], c[6], c[7], color)
	MeshKit.quad(st, c[1], c[0], c[4], c[5], color)
	MeshKit.quad(st, c[2], c[1], c[5], c[6], color)
	MeshKit.quad(st, c[0], c[3], c[7], c[4], color)


## A triangle turned to face `outward` whatever order its corners came in.
static func face_tri(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color
) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		MeshKit.tri(st, a, c, b, color)
	else:
		MeshKit.tri(st, a, b, c, color)


static func _hips(st: SurfaceTool, xf: Transform3D, t: CommanderVisuals.FactionTheme) -> void:
	frustum_box(st, at(xf, Vector3(0, -0.075, 0)), Vector2(0.24, 0.16), WAIST, 0.11, t.color)
	MeshKit.box(st, at(xf, Vector3(0, 0.028, 0)), Vector3(0.205, 0.028, 0.142), t.color_dark)
	MeshKit.box(st, at(xf, Vector3(0, 0.028, -0.072)), Vector3(0.032, 0.022, 0.01), GOLD)


static func _leg(st: SurfaceTool, xf: Transform3D) -> void:
	MeshKit.box(st, at(xf, Vector3(0, -0.07, 0)), Vector3(0.072, 0.14, 0.078), TROUSERS)
	MeshKit.box(st, at(xf, Vector3(0, -0.16, -0.012)), Vector3(0.078, 0.06, 0.104), BOOTS)


static func _arm(
	st: SurfaceTool, xf: Transform3D, look: Dictionary, t: CommanderVisuals.FactionTheme
) -> void:
	MeshKit.box(st, at(xf, Vector3(0, -0.065, 0)), Vector3(0.062, 0.14, 0.066), t.color)
	MeshKit.box(st, at(xf, Vector3(0, -0.135, 0)), Vector3(0.066, 0.026, 0.07), t.color_dark)
	MeshKit.box(st, at(xf, HAND), Vector3(0.05, 0.044, 0.05), look[&"skin_color"])


## How far the torso's front face stands forward of its pivot at height `y`.
static func front_z(y: float) -> float:
	return -lerpf(WAIST.y, CHEST.y, clampf(y / TORSO_H, 0.0, 1.0)) / 2.0 - 0.004


static func _torso(
	st: SurfaceTool, xf: Transform3D, look: Dictionary, t: CommanderVisuals.FactionTheme
) -> void:
	frustum_box(st, xf, WAIST, CHEST, TORSO_H, t.color)
	MeshKit.column(st, at(xf, Vector3(0, TORSO_H - 0.01, 0)), 0.032, 0.03, 0.03, 6, _neck(look))
	_collar(st, xf, look[&"collar"], t)
	_chest(st, xf, look[&"chest"], t)


static func _neck(look: Dictionary) -> Color:
	var skin: Color = look[&"skin_color"]
	return skin.darkened(0.12)


static func _front(xf: Transform3D, x: float, y: float, roll: float = 0.0) -> Transform3D:
	return at(xf, Vector3(x, y, front_z(y)), roll)


static func _collar(
	st: SurfaceTool, xf: Transform3D, collar: StringName, t: CommanderVisuals.FactionTheme
) -> void:
	var z := front_z(TORSO_H) - 0.002
	var top_l := xf * Vector3(-0.045, TORSO_H, z)
	var top_r := xf * Vector3(0.045, TORSO_H, z)
	var point := xf * Vector3(0, TORSO_H - 0.06, z)
	var forward := xf.basis * Vector3.FORWARD
	match collar:
		&"mandarin":
			MeshKit.box(
				st, at(xf, Vector3(0, TORSO_H + 0.01, 0)), Vector3(0.1, 0.03, 0.09), t.color_dark
			)
		&"double":
			face_tri(st, top_l, top_r, point, forward, SHIRT)
			for row in 3:
				for side: float in [-1.0, 1.0]:
					var y := 0.028 + 0.034 * row
					MeshKit.box(st, _front(xf, 0.036 * side, y), Vector3(0.016, 0.016, 0.01), GOLD)
		_:
			face_tri(st, top_l, top_r, point, forward, SHIRT)
			MeshKit.box(st, _front(xf, -0.03, 0.115, 0.6), Vector3(0.018, 0.06, 0.01), t.color_dark)
			MeshKit.box(st, _front(xf, 0.03, 0.115, -0.6), Vector3(0.018, 0.06, 0.01), t.color_dark)


## A strap from the left shoulder to the right hip, front and back.
static func _diagonal(st: SurfaceTool, xf: Transform3D, width: float, color: Color) -> void:
	var y := TORSO_H / 2.0
	MeshKit.box(st, _front(xf, 0, y, 0.62), Vector3(width, 0.19, 0.01), color)
	var back := at(xf, Vector3(0, y, -front_z(y)), -0.62)
	MeshKit.box(st, back, Vector3(width, 0.19, 0.01), color)


static func _chest(
	st: SurfaceTool, xf: Transform3D, chest: StringName, t: CommanderVisuals.FactionTheme
) -> void:
	match chest:
		&"sash":
			_diagonal(st, xf, 0.036, t.color_light)
		&"crossbelt":
			_diagonal(st, xf, 0.022, LEATHER)
			MeshKit.box(st, _front(xf, 0, 0.07, 0.62), Vector3(0.028, 0.024, 0.014), GOLD)
		&"bandolier":
			_diagonal(st, xf, 0.03, LEATHER)
			for i in 3:
				var along := Vector2(-0.035 + 0.035 * i, 0.105 - 0.035 * i)
				MeshKit.box(
					st, _front(xf, along.x, along.y, 0.62), Vector3(0.02, 0.026, 0.02), GOLD
				)
		&"boards", &"epaulette":
			_shoulders(st, xf, chest, t)
		&"placket":
			MeshKit.box(st, _front(xf, 0, 0.07), Vector3(0.034, 0.13, 0.01), t.color_dark)
			for i in 3:
				MeshKit.box(st, _front(xf, 0, 0.03 + 0.035 * i), Vector3(0.014, 0.014, 0.016), GOLD)
		&"loops":
			for i in 3:
				var loop := _front(xf, 0.03 + 0.022 * i, 0.09)
				MeshKit.box(st, loop, Vector3(0.01, 0.04, 0.014), LEATHER)
		&"lanyard":
			MeshKit.box(st, _front(xf, -0.022, 0.1, 0.35), Vector3(0.007, 0.08, 0.008), GOLD)
			MeshKit.box(st, _front(xf, 0.022, 0.1, -0.35), Vector3(0.007, 0.08, 0.008), GOLD)
			MeshKit.box(st, _front(xf, 0, 0.045), Vector3(0.036, 0.046, 0.01), SHIRT)
		&"pouch":
			MeshKit.box(st, _front(xf, 0.05, 0.03), Vector3(0.06, 0.05, 0.03), LEATHER)
		&"mapcase":
			_diagonal(st, xf, 0.02, LEATHER)
			MeshKit.box(
				st, at(xf, Vector3(-0.108, 0.02, 0.01)), Vector3(0.026, 0.085, 0.08), CANVAS
			)
		&"harness":
			for side: float in [-1.0, 1.0]:
				MeshKit.box(st, _front(xf, 0.05 * side, 0.07), Vector3(0.022, 0.14, 0.01), LEATHER)
				var back := at(xf, Vector3(0.05 * side, 0.07, -front_z(0.07)))
				MeshKit.box(st, back, Vector3(0.022, 0.14, 0.01), LEATHER)
			MeshKit.box(st, _front(xf, 0, 0.09), Vector3(0.12, 0.018, 0.012), LEATHER)
		&"scarf":
			MeshKit.box(
				st, at(xf, Vector3(0, TORSO_H + 0.005, 0)), Vector3(0.15, 0.04, 0.13), t.color_light
			)
			MeshKit.box(
				st, _front(xf, -0.04, 0.095, 0.15), Vector3(0.04, 0.09, 0.016), t.color_light
			)


static func _shoulders(
	st: SurfaceTool, xf: Transform3D, chest: StringName, t: CommanderVisuals.FactionTheme
) -> void:
	for side: float in [-1.0, 1.0]:
		var top := at(xf, Vector3(0.105 * side, TORSO_H + 0.006, 0))
		if chest == &"boards":
			MeshKit.box(st, top, Vector3(0.07, 0.014, 0.1), t.color_dark)
			MeshKit.box(st, at(top, Vector3(0, 0.008, 0)), Vector3(0.07, 0.004, 0.022), GOLD)
			continue
		MeshKit.box(st, top, Vector3(0.085, 0.02, 0.11), GOLD)
		for i in 4:
			var fringe := at(top, Vector3(0.04 * side, -0.02, -0.042 + 0.028 * i))
			MeshKit.box(st, fringe, Vector3(0.01, 0.03, 0.012), GOLD)
