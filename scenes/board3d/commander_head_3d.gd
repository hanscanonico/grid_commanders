class_name CommanderHead3D
extends RefCounted
## A general's head for `CommanderFigure3D`: the skull and face, the hair mass
## the look's `style` names, what is worn on it (`acc`, `acc2`) and the facial
## hair. Built in the head pivot's frame — the neck at the origin, the face
## toward -Z — and big on purpose, since at board scale the head is the part of
## a general a player recognises.

const SKULL := CommanderFigure3D.HEAD_SIZE
const CY := CommanderFigure3D.HEAD_Y
const FACE := CommanderFigure3D.FACE_Z
const EYE := CommanderFigure3D.EYE_Y
## The skull's crown, where every cap and top of hair sits.
const CROWN := CY + SKULL.y / 2.0
const INK := CommanderFigure3D.INK
const KIT := CommanderFigure3D.KIT
const GOLD := CommanderFigure3D.GOLD
const GLASS := CommanderFigure3D.GLASS


static func build(
	st: SurfaceTool, xf: Transform3D, look: Dictionary, t: CommanderVisuals.FactionTheme
) -> void:
	var skin: Color = look[&"skin_color"]
	var hair: Color = look[&"hair_color"]
	MeshKit.box(st, _at(xf, 0, CY, 0), SKULL, skin)
	for side: float in [-1.0, 1.0]:
		MeshKit.box(
			st, _at(xf, 0.116 * side, EYE - 0.005, 0.005), Vector3(0.02, 0.045, 0.035), skin
		)
	var wears: Array[StringName] = [look[&"acc"], look[&"acc2"]]
	var covered := wears.has(&"eyepatch")
	_face(st, xf, skin, hair, look[&"facial"], covered)
	var style: StringName = look[&"style"]
	if _covers_crown(wears) and (style == &"curly" or style == &"spiky"):
		style = &"short"
	if style == &"hood" or wears.has(&"hood"):
		_hood(st, xf, t.color_dark)
	else:
		_hair(st, xf, style, hair)
	for acc in wears:
		_wear(st, xf, acc, t)
	if look[&"prop"] == &"monocle":
		_frame(st, _at(xf, 0.048, EYE, FACE - 0.012), Vector2(0.05, 0.05), 0.008, GOLD)
		MeshKit.box(st, _at(xf, 0.072, EYE - 0.06, FACE - 0.01), Vector3(0.004, 0.09, 0.004), GOLD)


## Headwear over the crown, under which a tall style is pressed flat.
static func _covers_crown(wears: Array[StringName]) -> bool:
	for acc: StringName in [&"bandana", &"fieldcap", &"cap"]:
		if wears.has(acc):
			return true
	return false


static func _at(xf: Transform3D, x: float, y: float, z: float, roll: float = 0.0) -> Transform3D:
	return CommanderFigure3D.at(xf, Vector3(x, y, z), roll)


static func _face(
	st: SurfaceTool, xf: Transform3D, skin: Color, hair: Color, facial: StringName, patched: bool
) -> void:
	for side: float in [-1.0, 1.0]:
		if not (patched and side < 0.0):
			MeshKit.box(st, _at(xf, 0.048 * side, EYE, FACE), Vector3(0.032, 0.042, 0.012), INK)
		var brow := _at(xf, 0.048 * side, EYE + 0.037, FACE - 0.002)
		MeshKit.box(st, brow, Vector3(0.046, 0.012, 0.012), hair.darkened(0.15))
	MeshKit.box(
		st, _at(xf, 0, EYE - 0.03, FACE - 0.008), Vector3(0.026, 0.03, 0.02), skin.darkened(0.08)
	)
	var mouth_z := FACE - 0.002
	match facial:
		&"beard":
			MeshKit.box(st, _at(xf, 0, 0.045, FACE + 0.006), Vector3(0.2, 0.065, 0.03), hair)
			MeshKit.box(st, _at(xf, 0, 0.004, FACE + 0.012), Vector3(0.12, 0.03, 0.032), hair)
			for side: float in [-1.0, 1.0]:
				MeshKit.box(st, _at(xf, 0.1 * side, 0.07, -0.03), Vector3(0.026, 0.09, 0.13), hair)
			_mustache(st, xf, hair)
			mouth_z = FACE - 0.012
		&"stubble":
			var shade := skin.lerp(hair, 0.4)
			MeshKit.box(st, _at(xf, 0, 0.042, FACE - 0.002), Vector3(0.19, 0.06, 0.006), shade)
			mouth_z = FACE - 0.006
		&"mustache":
			_mustache(st, xf, hair)
	MeshKit.box(st, _at(xf, 0, 0.042, mouth_z), Vector3(0.05, 0.009, 0.01), CommanderFigure3D.MOUTH)


static func _mustache(st: SurfaceTool, xf: Transform3D, hair: Color) -> void:
	MeshKit.box(st, _at(xf, 0, 0.062, FACE - 0.008), Vector3(0.08, 0.018, 0.016), hair)
	for side: float in [-1.0, 1.0]:
		MeshKit.box(
			st, _at(xf, 0.042 * side, 0.05, FACE - 0.008), Vector3(0.016, 0.026, 0.014), hair
		)


## The hair as a shell over the skull: a top `thick` deep, a back reaching down
## to `back_to`, sides down to `sides_to` and `side_w` thick, and a fringe.
static func _shell(
	st: SurfaceTool,
	xf: Transform3D,
	c: Color,
	thick: float,
	back_to: float,
	sides_to: float,
	fringe: float,
	side_w: float = 0.018,
	framing := false
) -> void:
	var w := SKULL.x + 0.016
	MeshKit.box(st, _at(xf, 0, CROWN + thick / 2.0 - 0.012, 0.002), Vector3(w, thick, 0.216), c)
	MeshKit.box(
		st, _at(xf, 0, (CROWN + back_to) / 2.0, 0.108), Vector3(w, CROWN - back_to, 0.024), c
	)
	for side: float in [-1.0, 1.0]:
		var x := (SKULL.x / 2.0 + side_w / 2.0 - 0.006) * side
		var depth := 0.17 if framing else 0.12
		var box := Vector3(side_w, CROWN - sides_to, depth)
		MeshKit.box(st, _at(xf, x, (CROWN + sides_to) / 2.0, 0.105 - depth / 2.0), box, c)
	if fringe > 0.0:
		MeshKit.box(st, _at(xf, 0, CROWN - fringe / 2.0, FACE - 0.006), Vector3(w, fringe, 0.02), c)


static func _hair(st: SurfaceTool, xf: Transform3D, style: StringName, c: Color) -> void:
	match style:
		&"bald":
			MeshKit.box(st, _at(xf, 0, 0.1, 0.104), Vector3(0.21, 0.05, 0.02), c)
			for side: float in [-1.0, 1.0]:
				MeshKit.box(st, _at(xf, 0.112 * side, 0.12, 0.05), Vector3(0.012, 0.05, 0.1), c)
		&"buzz":
			_shell(st, xf, c, 0.02, 0.08, 0.13, 0.02, 0.01)
		&"short":
			_shell(st, xf, c, 0.036, 0.05, 0.1, 0.035)
		&"sidepart":
			_shell(st, xf, c, 0.034, 0.05, 0.1, 0.03)
			MeshKit.box(st, _at(xf, -0.04, CROWN + 0.022, -0.06, 0.18), Vector3(0.15, 0.04, 0.1), c)
			MeshKit.box(
				st, _at(xf, -0.07, CROWN - 0.03, FACE - 0.01, -0.3), Vector3(0.09, 0.04, 0.022), c
			)
		&"long":
			_shell(st, xf, c, 0.036, -0.1, -0.02, 0.035, 0.026, true)
		&"ponytail":
			_shell(st, xf, c, 0.036, 0.06, 0.1, 0.035)
			MeshKit.ball(st, _at(xf, 0, 0.17, 0.126), 0.026, 3, 6, c)
			var tail := xf * Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.1, 0.15))
			MeshKit.box(st, tail, Vector3(0.05, 0.14, 0.04), c)
		&"bun":
			_shell(st, xf, c, 0.034, 0.05, 0.1, 0.03)
			MeshKit.ball(st, _at(xf, 0, CROWN - 0.005, 0.1), 0.05, 3, 6, c)
		&"braid":
			_shell(st, xf, c, 0.036, 0.06, 0.1, 0.035)
			for i in 5:
				var link := _at(xf, 0.006 * (1 - 2 * (i % 2)), 0.15 - 0.05 * i, 0.125)
				MeshKit.box(st, link, Vector3(0.042, 0.046, 0.036), c)
		&"bob":
			_shell(st, xf, c, 0.04, 0.02, 0.03, 0.045, 0.03, true)
		&"curly":
			_shell(st, xf, c, 0.03, 0.05, 0.09, 0.03)
			for x: float in [-0.07, 0.0, 0.07]:
				for z: float in [-0.05, 0.05]:
					MeshKit.ball(st, _at(xf, x, CROWN + 0.004 - absf(x) * 0.15, z), 0.042, 3, 5, c)
		&"spiky":
			_shell(st, xf, c, 0.03, 0.06, 0.1, 0.02)
			for i in 5:
				var lean := Basis(Vector3.BACK, -0.35 * (i - 2)) * Basis(Vector3.RIGHT, 0.4)
				var spike := xf * Transform3D(lean, Vector3(0.045 * (i - 2), CROWN - 0.01, -0.02))
				MeshKit.column(st, spike, 0.032, 0.0, 0.06, 4, c)
		_:
			_shell(st, xf, c, 0.036, 0.05, 0.1, 0.035)


static func _hood(st: SurfaceTool, xf: Transform3D, c: Color) -> void:
	MeshKit.box(st, _at(xf, 0, CROWN + 0.014, 0.01), Vector3(0.25, 0.034, 0.23), c)
	MeshKit.box(st, _at(xf, 0, 0.095, 0.12), Vector3(0.25, 0.26, 0.03), c)
	for side: float in [-1.0, 1.0]:
		MeshKit.box(st, _at(xf, 0.122 * side, 0.1, 0.01), Vector3(0.022, 0.24, 0.22), c)
	MeshKit.box(
		st, _at(xf, 0, CROWN + 0.004, FACE - 0.008), Vector3(0.25, 0.03, 0.02), c.darkened(0.2)
	)


## A band round the head at height `y`, a little proud of the hair.
static func _band(st: SurfaceTool, xf: Transform3D, y: float, height: float, c: Color) -> void:
	MeshKit.box(st, _at(xf, 0, y, 0.002), Vector3(SKULL.x + 0.03, height, SKULL.z + 0.03), c)


## A rectangle's outline, `size` across, standing on the frame's XY plane.
static func _frame(st: SurfaceTool, xf: Transform3D, size: Vector2, pen: float, c: Color) -> void:
	var h := size / 2.0
	MeshKit.box(st, _at(xf, 0, h.y, 0), Vector3(size.x, pen, pen), c)
	MeshKit.box(st, _at(xf, 0, -h.y, 0), Vector3(size.x, pen, pen), c)
	MeshKit.box(st, _at(xf, h.x, 0, 0), Vector3(pen, size.y, pen), c)
	MeshKit.box(st, _at(xf, -h.x, 0, 0), Vector3(pen, size.y, pen), c)


static func _wear(
	st: SurfaceTool, xf: Transform3D, acc: StringName, t: CommanderVisuals.FactionTheme
) -> void:
	match acc:
		&"glasses":
			for side: float in [-1.0, 1.0]:
				_frame(
					st, _at(xf, 0.05 * side, EYE, FACE - 0.012), Vector2(0.056, 0.05), 0.009, INK
				)
				MeshKit.box(
					st, _at(xf, 0.112 * side, EYE + 0.02, -0.05), Vector3(0.008, 0.008, 0.1), INK
				)
			MeshKit.box(st, _at(xf, 0, EYE + 0.012, FACE - 0.012), Vector3(0.03, 0.008, 0.008), INK)
		&"goggles":
			_band(st, xf, EYE + 0.064, 0.026, KIT)
			for side: float in [-1.0, 1.0]:
				var lens := (
					xf
					* Transform3D(
						Basis(Vector3.UP, PI / 2.0), Vector3(0.045 * side, EYE + 0.064, FACE - 0.02)
					)
				)
				MeshKit.tube(st, lens, 0.028, 0.03, 6, KIT)
				var glass := (
					xf
					* Transform3D(
						Basis(Vector3.UP, PI / 2.0),
						Vector3(0.045 * side, EYE + 0.064, FACE - 0.036)
					)
				)
				MeshKit.tube(st, glass, 0.02, 0.006, 6, GLASS)
		&"eyepatch":
			MeshKit.box(st, _at(xf, -0.048, EYE, FACE - 0.004), Vector3(0.048, 0.052, 0.012), INK)
			var strap := xf * Transform3D(Basis(Vector3.BACK, -0.35), Vector3(0, EYE + 0.03, 0.002))
			MeshKit.box(st, strap, Vector3(SKULL.x + 0.024, 0.01, SKULL.z + 0.024), INK)
		&"headset":
			MeshKit.box(st, _at(xf, 0, CROWN + 0.036, 0), Vector3(0.25, 0.016, 0.03), KIT)
			for side: float in [-1.0, 1.0]:
				MeshKit.box(
					st, _at(xf, 0.124 * side, CROWN - 0.03, 0), Vector3(0.014, 0.12, 0.03), KIT
				)
				MeshKit.box(
					st, _at(xf, 0.126 * side, EYE - 0.005, 0), Vector3(0.03, 0.06, 0.056), KIT
				)
			MeshKit.box(st, _at(xf, -0.118, 0.06, -0.06, 0.25), Vector3(0.01, 0.01, 0.1), KIT)
			MeshKit.box(st, _at(xf, -0.085, 0.048, FACE - 0.01), Vector3(0.024, 0.016, 0.016), INK)
		&"headband":
			_band(st, xf, CROWN - 0.035, 0.026, t.color_light)
			MeshKit.box(
				st, _at(xf, 0.03, CROWN - 0.05, 0.13, 0.4), Vector3(0.02, 0.06, 0.01), t.color_light
			)
		&"bandana":
			MeshKit.box(
				st,
				_at(xf, 0, CROWN + 0.02, 0.004),
				Vector3(SKULL.x + 0.03, 0.04, SKULL.z + 0.032),
				t.color
			)
			_band(st, xf, CROWN - 0.02, 0.03, t.color)
			for side: float in [-1.0, 1.0]:
				var tail := _at(xf, 0.02 * side, CROWN - 0.07, 0.128, 0.3 * side)
				MeshKit.box(st, tail, Vector3(0.024, 0.07, 0.012), t.color)
		&"fieldcap":
			MeshKit.box(
				st,
				_at(xf, 0, CROWN + 0.018, 0.004),
				Vector3(SKULL.x + 0.034, 0.06, SKULL.z + 0.03),
				t.color_dark
			)
			MeshKit.box(
				st,
				_at(xf, 0, CROWN - 0.012, FACE - 0.03),
				Vector3(0.2, 0.012, 0.05),
				t.color_dark.darkened(0.3)
			)
		&"cap":
			_band(st, xf, CROWN - 0.01, 0.032, t.color_dark)
			MeshKit.box(st, _at(xf, 0, CROWN + 0.022, 0.004), Vector3(0.265, 0.034, 0.25), t.color)
			var peak := (
				xf * Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, CROWN - 0.02, FACE - 0.035))
			)
			MeshKit.box(st, peak, Vector3(0.2, 0.012, 0.06), INK)
			MeshKit.box(
				st, _at(xf, 0, CROWN - 0.004, FACE - 0.018), Vector3(0.03, 0.026, 0.01), GOLD
			)
		&"visor":
			_band(st, xf, CROWN - 0.035, 0.022, KIT)
			var brim := (
				xf * Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, CROWN - 0.04, FACE - 0.04))
			)
			MeshKit.box(st, brim, Vector3(0.2, 0.01, 0.07), CommanderFigure3D.VISOR)
		&"scar":
			MeshKit.box(
				st,
				_at(xf, 0.062, EYE - 0.03, FACE - 0.004, 0.35),
				Vector3(0.008, 0.05, 0.008),
				CommanderFigure3D.SCAR
			)
