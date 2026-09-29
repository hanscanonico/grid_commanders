class_name CommanderProps3D
extends RefCounted
## The signature prop a general carries in their right hand, the FACES `prop`
## column made small and solid. Built in the hand's frame: the fist at the
## origin, -Y out of the bottom of the fist, -Z the way the general faces. A
## long piece — a blade, a haft — is tipped forward out of the fist (`_grip`),
## so it hangs clear of the legs at rest and swings up with a raised arm.

const PROPS: Array[StringName] = [
	&"none",
	&"sabre",
	&"pipe",
	&"wrench",
	&"cigar",
	&"baton",
	&"medal",
	&"card",
	&"book",
	&"drone",
	&"monocle",
	&"dagger",
	&"radio",
	&"ledger",
	&"helm",
	&"plane",
	&"anchor",
	&"coins",
	&"whistle",
	&"compass",
	&"scales",
	&"axe",
	&"hammer",
]

const STEEL := Color8(206, 211, 219)
const METAL := Color8(91, 96, 104)
const WOOD := Color8(112, 74, 44)
const EMBER := Color8(240, 120, 48)
const RIBBON := Color8(176, 44, 44)
const COVER := Color8(122, 42, 40)
const GREEN_COVER := Color8(50, 86, 62)
const OLIVE := Color8(86, 96, 70)
const GOLD := CommanderFigure3D.GOLD
const INK := CommanderFigure3D.INK
const KIT := CommanderFigure3D.KIT
const LEATHER := CommanderFigure3D.LEATHER
const PAPER := CommanderFigure3D.SHIRT
const GLASS := CommanderFigure3D.GLASS
const GRIP_TILT := 0.8


static func build(st: SurfaceTool, hand: Transform3D, prop: StringName) -> void:
	var g := _grip(hand)
	match prop:
		&"sabre":
			_box(st, g, Vector3(0, -0.028, 0), Vector3(0.05, 0.012, 0.03), GOLD)
			_box(st, g, Vector3(0, -0.12, 0), Vector3(0.014, 0.17, 0.006), STEEL)
		&"dagger":
			_box(st, g, Vector3(0, -0.028, 0), Vector3(0.036, 0.01, 0.018), GOLD)
			_box(st, g, Vector3(0, -0.068, 0), Vector3(0.014, 0.07, 0.005), STEEL)
		&"baton":
			_box(st, g, Vector3(0, -0.04, 0), Vector3(0.02, 0.13, 0.02), INK)
			_box(st, g, Vector3(0, -0.105, 0), Vector3(0.026, 0.018, 0.026), GOLD)
			_box(st, g, Vector3(0, 0.025, 0), Vector3(0.026, 0.018, 0.026), GOLD)
		&"axe":
			_box(st, g, Vector3(0, -0.07, 0), Vector3(0.018, 0.2, 0.018), WOOD)
			_box(st, g, Vector3(0, -0.15, -0.03), Vector3(0.012, 0.06, 0.06), STEEL)
		&"hammer":
			_box(st, g, Vector3(0, -0.06, 0), Vector3(0.018, 0.17, 0.018), WOOD)
			_box(st, g, Vector3(0, -0.15, 0), Vector3(0.05, 0.045, 0.085), METAL)
		&"wrench":
			_box(st, g, Vector3(0, -0.05, 0), Vector3(0.02, 0.11, 0.01), METAL)
			_box(st, g, Vector3(0, -0.105, 0), Vector3(0.052, 0.016, 0.012), METAL)
			for side: float in [-1.0, 1.0]:
				_box(st, g, Vector3(0.019 * side, -0.123, 0), Vector3(0.014, 0.03, 0.012), METAL)
		&"anchor":
			_anchor(st, g)
		_:
			_held(st, hand, prop)


## A small thing held out in front of the fist.
static func _held(st: SurfaceTool, hand: Transform3D, prop: StringName) -> void:
	match prop:
		&"pipe":
			_box(st, hand, Vector3(0, -0.02, -0.018), Vector3(0.008, 0.008, 0.04), INK)
			MeshKit.column(st, _at(hand, Vector3(0, -0.028, -0.042)), 0.014, 0.014, 0.03, 6, WOOD)
		&"cigar":
			_box(st, hand, Vector3(0, -0.02, -0.03), Vector3(0.012, 0.012, 0.05), LEATHER)
			_box(st, hand, Vector3(0, -0.02, -0.058), Vector3(0.013, 0.013, 0.008), EMBER)
		&"medal":
			_box(st, hand, Vector3(0, -0.035, -0.03), Vector3(0.022, 0.03, 0.005), RIBBON)
			_disc(st, hand, Vector3(0, -0.062, -0.03), 0.02, GOLD)
		&"card":
			_box(st, hand, Vector3(0, -0.045, -0.03), Vector3(0.042, 0.058, 0.004), PAPER)
		&"book":
			_book(st, hand, Vector3(0.062, 0.078, 0.024), COVER)
		&"ledger":
			_book(st, hand, Vector3(0.072, 0.09, 0.028), GREEN_COVER)
		&"drone":
			_box(st, hand, Vector3(0, -0.035, -0.06), Vector3(0.042, 0.016, 0.042), KIT)
			for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var rotor := Vector3(0.034 * corner.x, -0.026, -0.06 + 0.034 * corner.y)
				_box(st, hand, rotor, Vector3(0.028, 0.004, 0.028), GLASS)
		&"radio":
			_box(st, hand, Vector3(0, -0.045, -0.03), Vector3(0.046, 0.07, 0.03), OLIVE)
			_box(st, hand, Vector3(0.014, 0.025, -0.03), Vector3(0.006, 0.08, 0.006), INK)
		&"helm":
			MeshKit.ball(st, _at(hand, Vector3(0, -0.06, -0.035)), 0.05, 4, 8, METAL)
			_box(st, hand, Vector3(0, -0.085, -0.035), Vector3(0.11, 0.01, 0.11), METAL)
		&"plane":
			_box(st, hand, Vector3(0, -0.03, -0.06), Vector3(0.022, 0.022, 0.1), STEEL)
			_box(st, hand, Vector3(0, -0.03, -0.065), Vector3(0.11, 0.006, 0.026), STEEL)
			_box(st, hand, Vector3(0, -0.015, -0.015), Vector3(0.006, 0.03, 0.02), RIBBON)
		&"coins":
			MeshKit.ball(st, _at(hand, Vector3(0, -0.05, -0.02)), 0.032, 3, 6, LEATHER)
			_disc(st, hand, Vector3(0, -0.04, -0.056), 0.018, GOLD)
		&"whistle":
			_box(st, hand, Vector3(0, -0.022, -0.03), Vector3(0.014, 0.014, 0.04), STEEL)
		&"compass":
			_disc(st, hand, Vector3(0, -0.04, -0.03), 0.026, GOLD)
			_disc(st, hand, Vector3(0, -0.04, -0.038), 0.019, PAPER)
		&"scales":
			_box(st, hand, Vector3(0, -0.03, -0.07), Vector3(0.12, 0.008, 0.008), GOLD)
			_box(st, hand, Vector3(0, -0.01, -0.07), Vector3(0.008, 0.05, 0.008), GOLD)
			for side: float in [-1.0, 1.0]:
				_box(
					st,
					hand,
					Vector3(0.055 * side, -0.055, -0.07),
					Vector3(0.004, 0.05, 0.004),
					GOLD
				)
				MeshKit.column(
					st, _at(hand, Vector3(0.055 * side, -0.085, -0.07)), 0.026, 0.03, 0.008, 6, GOLD
				)


## The hand's frame tipped forward, so -Y runs forward and down out of the fist.
static func _grip(hand: Transform3D) -> Transform3D:
	return hand * Transform3D(Basis(Vector3.RIGHT, GRIP_TILT), Vector3.ZERO)


static func _at(xf: Transform3D, pos: Vector3) -> Transform3D:
	return xf * Transform3D(Basis.IDENTITY, pos)


static func _box(st: SurfaceTool, xf: Transform3D, pos: Vector3, size: Vector3, c: Color) -> void:
	MeshKit.box(st, _at(xf, pos), size, c)


## A coin-flat disc facing forward.
static func _disc(st: SurfaceTool, xf: Transform3D, pos: Vector3, r: float, c: Color) -> void:
	MeshKit.tube(st, xf * Transform3D(Basis(Vector3.UP, PI / 2.0), pos), r, 0.006, 8, c)


static func _book(st: SurfaceTool, hand: Transform3D, size: Vector3, cover: Color) -> void:
	var pos := Vector3(0, -0.04, -0.035)
	_box(st, hand, pos, size, cover)
	_box(st, hand, pos + Vector3(0.004, 0, 0), size - Vector3(0, 0.008, 0.008), PAPER)


static func _anchor(st: SurfaceTool, g: Transform3D) -> void:
	_box(st, g, Vector3(0, -0.075, 0), Vector3(0.016, 0.15, 0.016), METAL)
	_box(st, g, Vector3(0, -0.025, 0), Vector3(0.07, 0.012, 0.012), METAL)
	for side: float in [-1.0, 1.0]:
		var arm := g * Transform3D(Basis(Vector3.BACK, 0.9 * side), Vector3(0.026 * side, -0.14, 0))
		MeshKit.box(st, arm, Vector3(0.012, 0.055, 0.014), METAL)
