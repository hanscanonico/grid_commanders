extends RefCounted
## Draws one commander portrait as an SVG document — the heroic character bust
## the "Heroic Commander Portraits" design handoff specifies, transcribed from
## its CommanderFace.jsx drawing source.
##
## Each general is a row in FACES: a face spec (skin, hair, brow, eyes, mouth,
## facial hair, accessory), a pose (tilt, zoom, mirror), one of six dramatic
## backdrops, and a signature prop. Everything is drawn in the handoff's
## coordinate system — a 110x134 viewBox holding a 98x96 inner window at (6, 24),
## with the bust anchored bottom-centre so the head breaks over the window's top
## edge and the shoulders bleed off its sides.
##
## Only the faction colours enter from outside (accent, accent-dark and the ink
## outline are constructor arguments), so this file never declares a faction hue
## and CommanderVisuals stays the one authority on them. The generator rasterises
## what `build()` returns; nothing here loads or writes a file.
##
## Not a class_name: this is offline art tooling, reached by preload from
## tools/generate_portraits.gd, and the game never sees it.

## The drawing surface. The window is the ink-bordered box the backdrop is
## clipped to; the bust is deliberately larger than it.
const VIEW_BOX := "0 -14 110 134"
const WINDOW := Rect2(6, 24, 98, 96)
## The two eye centres every brow, lash and pupil is placed against.
const EYE_X: Array[float] = [45.0, 65.0]
## Nia Rowan's freckles, three to a cheek.
const FRECKLES: Array[Vector2] = [
	Vector2(42, 66),
	Vector2(45, 68),
	Vector2(48, 66),
	Vector2(62, 66),
	Vector2(65, 68),
	Vector2(68, 66),
]

const SKIN := {
	&"light": "#f2c9a0",
	&"medium": "#d9a066",
	&"tan": "#c68642",
	&"dark": "#8a5a3c",
	&"pale": "#f6dcc2",
}
const HAIR := {
	&"auburn": "#8c4a2f",
	&"grey": "#bdbdbd",
	&"black": "#262626",
	&"brown": "#5a3c28",
	&"platinum": "#e7e0cc",
	&"blonde": "#e0b84c",
	&"darkbrown": "#33251a",
}

## Per-commander spec, straight from the handoff's FACES table. `pose` is
## [tilt degrees, zoom, mirrored].
const FACES := {
	&"alina_ward":
	{
		"skin": &"light",
		"hair": &"auburn",
		"style": &"long",
		"brow": &"soft",
		"eyes": &"f",
		"mouth": &"smile",
		"facial": &"none",
		"acc": &"none",
		"earring": true,
		"pose": [-5.0, 1.2, false],
		"bg": &"rays",
		"prop": &"sabre",
	},
	&"gideon_holt":
	{
		"skin": &"medium",
		"hair": &"grey",
		"style": &"short",
		"brow": &"soft",
		"eyes": &"m",
		"mouth": &"smile",
		"facial": &"beard",
		"acc": &"glasses",
		"pose": [3.0, 1.14, false],
		"bg": &"halftone",
		"prop": &"pipe",
	},
	&"rhea_sol":
	{
		"skin": &"tan",
		"hair": &"black",
		"style": &"ponytail",
		"brow": &"angled",
		"eyes": &"narrow",
		"mouth": &"grin",
		"facial": &"none",
		"acc": &"goggles",
		"pose": [-8.0, 1.24, true],
		"bg": &"speed",
		"prop": &"wrench",
	},
	&"cass_orlov":
	{
		"skin": &"light",
		"hair": &"brown",
		"style": &"buzz",
		"brow": &"angled",
		"eyes": &"m",
		"mouth": &"smirk",
		"facial": &"stubble",
		"acc": &"scar",
		"pose": [6.0, 1.22, false],
		"bg": &"wedge",
		"prop": &"cigar",
	},
	&"mara_voss":
	{
		"skin": &"medium",
		"hair": &"black",
		"style": &"bun",
		"brow": &"angled",
		"eyes": &"f",
		"mouth": &"stern",
		"facial": &"none",
		"acc": &"none",
		"pose": [0.0, 1.18, false],
		"bg": &"bars",
		"prop": &"baton",
	},
	&"viktor_draeg":
	{
		"skin": &"light",
		"hair": &"grey",
		"style": &"bald",
		"brow": &"angled",
		"eyes": &"m",
		"mouth": &"snarl",
		"facial": &"mustache",
		"acc": &"eyepatch",
		"pose": [-3.0, 1.26, false],
		"bg": &"burst",
		"prop": &"medal",
	},
	&"cassian_rook":
	{
		"skin": &"light",
		"hair": &"blonde",
		"style": &"sidepart",
		"brow": &"raised",
		"eyes": &"m",
		"mouth": &"smirk",
		"facial": &"none",
		"acc": &"none",
		"pose": [8.0, 1.18, true],
		"bg": &"halftone",
		"prop": &"card",
	},
	&"lyra_quill":
	{
		"skin": &"pale",
		"hair": &"platinum",
		"style": &"bob",
		"brow": &"soft",
		"eyes": &"closed",
		"mouth": &"smile",
		"facial": &"none",
		"acc": &"glasses",
		"pose": [-4.0, 1.12, false],
		"bg": &"rays",
		"prop": &"book",
	},
	&"orin_flux":
	{
		"skin": &"medium",
		"hair": &"black",
		"style": &"spiky",
		"brow": &"raised",
		"eyes": &"m",
		"mouth": &"grin",
		"facial": &"none",
		"acc": &"headset",
		"pose": [-9.0, 1.22, false],
		"bg": &"speed",
		"prop": &"drone",
	},
	&"nia_rowan":
	{
		"skin": &"tan",
		"hair": &"brown",
		"style": &"braid",
		"brow": &"soft",
		"eyes": &"f",
		"mouth": &"smile",
		"facial": &"none",
		"acc": &"headband",
		"freckles": true,
		"pose": [4.0, 1.16, false],
		"bg": &"rays",
		"prop": &"falcon",
	},
	&"sable_wren":
	{
		"skin": &"pale",
		"hair": &"black",
		"style": &"hood",
		"brow": &"angled",
		"eyes": &"narrow",
		"mouth": &"neutral",
		"facial": &"none",
		"acc": &"hood",
		"pose": [0.0, 1.24, false],
		"bg": &"wedge",
		"prop": &"dagger",
	},
	&"tomas_reed":
	{
		"skin": &"dark",
		"hair": &"black",
		"style": &"curly",
		"brow": &"soft",
		"eyes": &"m",
		"mouth": &"grin",
		"facial": &"stubble",
		"acc": &"bandana",
		"pose": [-6.0, 1.2, false],
		"bg": &"burst",
		"prop": &"radio",
	},
	&"ines_calder":
	{
		"skin": &"dark",
		"hair": &"black",
		"style": &"bun",
		"brow": &"angled",
		"eyes": &"f",
		"mouth": &"smirk",
		"facial": &"none",
		"acc": &"glasses",
		"pose": [-4.0, 1.18, false],
		"bg": &"bars",
		"prop": &"book",
	},
	&"konrad_vale":
	{
		"skin": &"pale",
		"hair": &"platinum",
		"style": &"sidepart",
		"brow": &"angled",
		"eyes": &"narrow",
		"mouth": &"stern",
		"facial": &"mustache",
		"acc": &"none",
		"pose": [5.0, 1.25, false],
		"bg": &"wedge",
		"prop": &"medal",
	},
	&"perrin_ash":
	{
		"skin": &"tan",
		"hair": &"auburn",
		"style": &"short",
		"brow": &"raised",
		"eyes": &"m",
		"mouth": &"grin",
		"facial": &"none",
		"acc": &"goggles",
		"pose": [-7.0, 1.2, true],
		"bg": &"speed",
		"prop": &"card",
	},
	&"halden_marr":
	{
		"skin": &"medium",
		"hair": &"grey",
		"style": &"curly",
		"brow": &"soft",
		"eyes": &"m",
		"mouth": &"neutral",
		"facial": &"beard",
		"acc": &"none",
		"pose": [3.0, 1.16, false],
		"bg": &"rays",
		"prop": &"pipe",
	},
	&"dane_ferrow":
	{
		"skin": &"dark",
		"hair": &"black",
		"style": &"buzz",
		"brow": &"angled",
		"eyes": &"narrow",
		"mouth": &"snarl",
		"facial": &"stubble",
		"acc": &"scar",
		"pose": [7.0, 1.24, false],
		"bg": &"burst",
		"prop": &"cigar",
	},
	&"iris_colt":
	{
		"skin": &"light",
		"hair": &"blonde",
		"style": &"ponytail",
		"brow": &"raised",
		"eyes": &"f",
		"mouth": &"smile",
		"facial": &"none",
		"acc": &"headset",
		"pose": [-6.0, 1.22, false],
		"bg": &"halftone",
		"prop": &"sabre",
	},
	&"sera_lark":
	{
		"skin": &"dark",
		"hair": &"darkbrown",
		"style": &"ponytail",
		"brow": &"raised",
		"eyes": &"f",
		"mouth": &"grin",
		"facial": &"none",
		"acc": &"bandana",
		"pose": [5.0, 1.2, true],
		"bg": &"wedge",
		"prop": &"baton",
	},
	&"iona_vance":
	{
		"skin": &"tan",
		"hair": &"brown",
		"style": &"bob",
		"brow": &"soft",
		"eyes": &"f",
		"mouth": &"stern",
		"facial": &"none",
		"acc": &"none",
		"pose": [0.0, 1.16, false],
		"bg": &"bars",
		"prop": &"baton",
	},
}

var _accent: String
var _accent_dark: String
var _ink: String
## Design-system tokens the props borrow, each read from the authority that
## already owns it rather than re-declared here: the gold a medal and a baton cap
## are struck in, the dark plastic of a radio and a drone, and the two lights a
## cigar ember and a drone's status LED glow with.
var _gold := hex(UiTheme.AMMO)
var _slate := hex(UiTheme.SLATE_800)
var _ember := hex(CommanderVisuals.theme_for_key(&"meridian").color_light)
var _led := hex(CommanderVisuals.theme_for_key(&"aurora").color_light)


## The portrait wears its general's faction: the window and uniform take the
## dark shade, the chevron and backdrop highlights the bright one.
func _init(theme: CommanderVisuals.FactionTheme) -> void:
	_accent = hex(theme.color)
	_accent_dark = hex(theme.color_dark)
	_ink = hex(UiTheme.HARD_BORDER)


static func hex(color: Color) -> String:
	return "#" + color.to_html(false)


## The commanders this file can draw. The generator falls back to the neutral
## silhouette for anything else, so a general added without a face spec renders
## rather than crashing.
static func has_face(id: StringName) -> bool:
	return FACES.has(id)


## The full portrait document for one commander.
func build(id: StringName) -> String:
	var face: Dictionary = FACES[id]
	var out := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s">' % VIEW_BOX
	out += _clip_def()
	out += _window()
	out += '<g clip-path="url(#win)">%s</g>' % _backdrop(face["bg"])
	out += '<g transform="%s">%s</g>' % [_pose(face), _bust(face)]
	return out + "</svg>"


## "No Commander": the same framed window with a featureless bust in it, so an
## empty seat reads as a deliberate styled choice rather than a missing file.
func build_neutral() -> String:
	var out := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s">' % VIEW_BOX
	out += _clip_def()
	out += _window()
	out += '<g clip-path="url(#win)">%s</g>' % _backdrop(&"bars")
	var body := _shoulders() + _neck(_accent_dark) + _head(_accent_dark)
	out += '<g transform="translate(55 120) scale(1.18) translate(-55 -120)">'
	return out + body + "</g></svg>"


# --- frame -------------------------------------------------------------------


func _clip_def() -> String:
	return (
		'<clipPath id="win"><rect x="%s" y="%s" width="%s" height="%s"/></clipPath>'
		% [WINDOW.position.x, WINDOW.position.y, WINDOW.size.x, WINDOW.size.y]
	)


func _window() -> String:
	return (
		'<rect x="%s" y="%s" width="%s" height="%s" fill="%s" stroke="%s" stroke-width="3"/>'
		% [
			WINDOW.position.x,
			WINDOW.position.y,
			WINDOW.size.x,
			WINDOW.size.y,
			_accent_dark,
			_ink,
		]
	)


func _pose(face: Dictionary) -> String:
	var pose: Array = face["pose"]
	var mirror := "translate(110 0) scale(-1 1) " if bool(pose[2]) else ""
	return (
		"%srotate(%s 55 70) translate(55 120) scale(%s) translate(-55 -120)"
		% [mirror, pose[0], pose[1]]
	)


# --- stroke helpers ----------------------------------------------------------


## The signature ink outline: 2.4 units, round joins. `width` overrides it for
## the thinner line work (brows, the nose, a mouth).
func _line(width := 2.4) -> String:
	return (
		' stroke="%s" stroke-width="%s" stroke-linejoin="round" stroke-linecap="round"'
		% [_ink, width]
	)


func _path(d: String, fill: String, extra := "") -> String:
	return '<path d="%s" fill="%s"%s/>' % [d, fill, extra]


## An outlined path with no fill — the shape of every brow, lash and crease.
func _stroke_path(d: String, width: float, color := "") -> String:
	var pen := _line(width) if color.is_empty() else _tint(color, width)
	return _path(d, "none", pen)


func _tint(color: String, width: float) -> String:
	return ' stroke="%s" stroke-width="%s" stroke-linecap="round"' % [color, width]


func _circle(cx: float, cy: float, r: float, fill: String, extra := "") -> String:
	return '<circle cx="%s" cy="%s" r="%s" fill="%s"%s/>' % [cx, cy, r, fill, extra]


func _rect(x: float, y: float, w: float, h: float, fill: String, extra := "") -> String:
	return '<rect x="%s" y="%s" width="%s" height="%s" fill="%s"%s/>' % [x, y, w, h, fill, extra]


# --- the bust ----------------------------------------------------------------


func _bust(face: Dictionary) -> String:
	var skin: String = SKIN[face["skin"]]
	var hair: String = HAIR[face["hair"]]
	var out := _prop(face["prop"], &"back", skin)
	if face["style"] == &"hood":
		out += _path("M20,120 Q12,64 55,50 Q98,64 90,120 Z", _accent_dark, _line())
	out += _hair_back(face["style"], hair)
	out += _shoulders()
	out += _neck(skin)
	out += _circle(31, 58, 5, skin, _line()) + _circle(79, 58, 5, skin, _line())
	if face.get("earring", false):
		out += _circle(31, 63.5, 1.9, _gold, ' stroke="%s" stroke-width="1.2"' % _ink)
	out += _head(skin)
	out += _facial(face["facial"], hair)
	out += _hair_front(face["style"], hair)
	out += _headwear(face["acc"])
	out += _brows(face["brow"])
	out += _eyes(face["eyes"])
	out += _eyewear(face["acc"])
	out += _stroke_path("M55,60 L53.5,65 Q55,66.5 57,65.2", 1.8)
	out += _mouth(face["mouth"])
	out += _details(face)
	return out + _prop(face["prop"], &"front", skin)


## Uniform shoulders rising off the bottom edge, with the ink V of a collar and
## the faction chevron under it.
func _shoulders() -> String:
	var mass := "M6,120 L6,110 Q6,93 32,90 L78,90 Q104,93 104,110 L104,120 Z"
	var out := _path(mass, _accent_dark, _line())
	out += _stroke_path("M44,90 L55,101 L66,90", 2.4)
	return out + _path("M40,90 L55,104 L70,90 L70,94 L55,108 L40,94 Z", _accent)


func _neck(skin: String) -> String:
	return _path("M47,76 L47,90 Q55,95 63,90 L63,76 Z", skin, _line())


func _head(skin: String) -> String:
	var d := "M32,52 Q32,27 55,27 Q78,27 78,52 L78,60 Q78,84 55,89 Q32,84 32,60 Z"
	return _path(d, skin, _line())


func _facial(kind: StringName, hair: String) -> String:
	if kind == &"beard":
		var d := "M33,60 Q34,84 55,89 Q76,84 77,60 Q70,74 55,74 Q40,74 33,60 Z"
		return _path(d, hair)
	if kind == &"stubble":
		var d := "M34,62 Q36,84 55,89 Q74,84 76,62 Q68,73 55,73 Q42,73 34,62 Z"
		return _path(d, hair, ' opacity="0.32"')
	if kind == &"mustache":
		return _path("M46,66 Q55,64 64,66 Q60,70 55,69 Q50,70 46,66 Z", hair)
	return ""


func _hair_back(style: StringName, hair: String) -> String:
	var pen := _line()
	match style:
		&"long":
			var d := "M27,58 Q22,22 55,20 Q88,22 83,58 L86,104 L72,96"
			d += " Q80,54 55,50 Q30,54 38,96 L24,104 Z"
			return _path(d, hair, pen)
		&"ponytail":
			var cap := "M30,54 Q28,24 55,22 Q82,24 80,54 Q80,42 55,40 Q30,42 30,54 Z"
			var tail := "M78,40 Q98,46 96,74 Q92,86 84,84 Q92,64 82,50 Z"
			return _path(cap, hair, pen) + _path(tail, hair, pen)
		&"bob":
			var d := "M28,56 Q24,24 55,22 Q86,24 82,56 L82,80 L74,76"
			d += " Q80,52 55,48 Q30,52 36,76 L28,80 Z"
			return _path(d, hair, pen)
		&"braid":
			var cap := "M30,54 Q28,24 55,22 Q82,24 80,54 Q80,42 55,40 Q30,42 30,54 Z"
			var plait := "M31,50 Q20,60 24,80 Q26,92 33,90 Q28,74 38,58 Z"
			var beads := _circle(28, 70, 4.5, hair, pen) + _circle(30, 82, 4.5, hair, pen)
			return _path(cap, hair, pen) + _path(plait, hair, pen) + beads
	return ""


func _hair_front(style: StringName, hair: String) -> String:
	var pen := _line()
	match style:
		&"long":
			var d := "M32,46 Q34,30 55,28 Q76,30 78,46 Q70,36 60,38"
			d += " Q56,30 47,36 Q40,34 40,44 Q36,40 32,46 Z"
			return _path(d, hair, pen)
		&"short":
			return _path("M31,48 Q30,28 55,26 Q80,28 79,48 Q74,36 55,35 Q36,35 31,48 Z", hair, pen)
		&"ponytail":
			var d := "M31,48 Q30,28 55,26 Q80,28 79,48 Q72,37 55,36 Q40,36 40,45 Q35,42 31,48 Z"
			return _path(d, hair, pen)
		&"bob":
			return _path("M30,48 Q29,27 55,25 Q81,27 80,48 Q73,35 55,34 Q37,35 30,48 Z", hair, pen)
		&"braid":
			return _path("M31,48 Q30,28 55,26 Q80,28 79,48 Q72,37 55,36 Q38,36 31,48 Z", hair, pen)
		&"buzz":
			var d := "M33,46 Q34,31 55,30 Q76,31 77,46 Q70,40 55,40 Q40,40 33,46 Z"
			return _path(d, hair, ' opacity="0.85"')
		&"sidepart":
			var d := "M31,47 Q30,28 55,26 Q80,28 79,45 Q75,35 52,35 Q50,33 44,38 Q38,36 31,47 Z"
			return _path(d, hair, pen)
		&"spiky":
			var d := "M31,47 L34,30 L41,40 L46,27 L52,39 L58,27 L64,39 L70,29 L76,41"
			d += " L79,47 Q70,38 55,38 Q40,38 31,47 Z"
			return _path(d, hair, pen)
		&"curly":
			var curls := _circle(38, 36, 8, hair, pen) + _circle(50, 31, 8.5, hair, pen)
			curls += _circle(62, 31, 8.5, hair, pen) + _circle(73, 37, 8, hair, pen)
			var d := "M32,48 Q34,40 40,40 L70,40 Q76,40 78,48 Q70,42 55,42 Q40,42 32,48 Z"
			return curls + _path(d, hair, pen)
		&"bald":
			var d := "M34,44 Q36,36 44,35 Q40,40 40,46 Z M76,44 Q74,36 66,35 Q70,40 70,46 Z"
			return _path(d, hair)
		&"bun":
			var d := "M31,48 Q30,30 55,28 Q80,30 79,48 Q72,38 55,38 Q38,38 31,48 Z"
			return _path(d, hair, pen) + _circle(55, 24, 9, hair, pen)
	return ""


func _headwear(acc: StringName) -> String:
	var pen := _line()
	match acc:
		&"bandana":
			var d := "M30,44 Q30,30 55,29 Q80,30 80,44 Q80,40 76,40 L34,40 Q30,40 30,44 Z"
			return _path(d, _accent, pen)
		&"headband":
			return _rect(30, 41, 50, 6, _accent, pen + ' rx="2"')
		&"goggles":
			var strap := _rect(30, 37, 50, 6, _accent_dark, pen + ' rx="2"')
			var glass := _circle(43, 40, 6.5, "#bcd6e0", pen) + _circle(67, 40, 6.5, "#bcd6e0", pen)
			return strap + glass
		&"hood":
			var d := "M24,64 Q18,30 55,26 Q92,30 86,64 Q80,44 55,44 Q30,44 24,64 Z"
			return _path(d, _accent_dark, pen)
	return ""


func _eyewear(acc: StringName) -> String:
	if acc == &"eyepatch":
		var strap := _stroke_path("M28,50 L82,45", 2.6)
		return strap + _rect(38, 52, 15, 12, _ink, ' rx="3"')
	if acc == &"glasses":
		var pen := ' fill="none" stroke="%s" stroke-width="2"' % _ink
		var lenses := '<rect x="38" y="52" width="15" height="11" rx="3"%s/>' % pen
		lenses += '<rect x="57" y="52" width="15" height="11" rx="3"%s/>' % pen
		return lenses + _path("M53,56 H57", "none", ' stroke="%s" stroke-width="2"' % _ink)
	return ""


## Everything drawn over the face: a scar, freckles, a headset boom.
func _details(face: Dictionary) -> String:
	var out := ""
	if face["acc"] == &"scar":
		var cuts: Array[String] = ["M67,49 L71,60", "M65,52 L68,53", "M67,56 L70,57"]
		for d: String in cuts:
			out += _stroke_path(d, 1.6, "#b56b5a")
	if face.get("freckles", false):
		var dots := ""
		for spot: Vector2 in FRECKLES:
			dots += _circle(spot.x, spot.y, 1, "#b56b5a")
		out += '<g opacity="0.5">%s</g>' % dots
	if face["acc"] == &"headset":
		out += _stroke_path("M30,50 Q30,32 55,32 Q80,32 80,50", 3)
		out += _rect(26, 50, 8, 12, _accent_dark, _line() + ' rx="3"')
		out += _stroke_path("M28,60 Q24,68 40,70", 2.4)
		out += _circle(41, 70.5, 2.4, _accent, ' stroke="%s" stroke-width="1.4"' % _ink)
	return out


# --- face parts --------------------------------------------------------------


func _eyes(kind: StringName) -> String:
	var out := ""
	if kind == &"closed":
		for x: float in EYE_X:
			out += _stroke_path("M%s,57 Q%s,60.5 %s,57" % [x - 4.5, x, x + 4.5], 2.4)
		return out
	var ry := 2.6 if kind == &"narrow" else 4.4
	for x: float in EYE_X:
		out += '<ellipse cx="%s" cy="57" rx="4.1" ry="%s" fill="#ffffff"%s/>' % [x, ry, _line()]
		out += _circle(x, 57.4, 2.1, _ink)
		out += _circle(x + 1.1, 56, 0.9, "#ffffff")
	if kind == &"f":
		for x: float in EYE_X:
			out += _stroke_path("M%s,53.6 Q%s,51.2 %s,53.6" % [x - 5, x, x + 5], 2.8)
	return out


func _brows(kind: StringName) -> String:
	var out := ""
	for x: float in EYE_X:
		var d := ""
		if kind == &"angled":
			var rise := 48.5 if x == 45.0 else 52.0
			var fall := 52.0 if x == 45.0 else 48.5
			d = "M%s,%s L%s,%s" % [x - 5.5, rise, x + 5.5, fall]
		elif kind == &"raised":
			d = "M%s,48 Q%s,45.5 %s,48" % [x - 5, x, x + 5]
		else:
			d = "M%s,49.5 Q%s,47.5 %s,49.5" % [x - 5, x, x + 5]
		out += _stroke_path(d, 3)
	return out


func _mouth(kind: StringName) -> String:
	match kind:
		&"smile":
			return _stroke_path("M47.5,70 Q55,78 62.5,70", 2.6)
		&"smirk":
			return _stroke_path("M48.5,72 Q56,74 62.5,69", 2.6)
		&"stern":
			return _stroke_path("M49,72 Q55,70.5 61,72.5", 2.6)
		&"snarl":
			var jaw := _path("M47,68.5 Q55,66.5 63,68.5 L61,76 Q55,79 49,76 Z", _ink, _line())
			return jaw + _stroke_path("M48.5,70 H61.5", 2.4, "#ffffff")
		&"grin":
			var open := _path("M47,68.5 Q55,80 63,68.5 Z", _ink, _line())
			return open + _stroke_path("M49.5,70.5 H60.5", 2.2, "#ffffff")
	return _stroke_path("M49,71.5 H61", 2.6)


# --- backdrops ---------------------------------------------------------------


## One of six dramatic treatments behind the bust, clipped to the window.
func _backdrop(kind: StringName) -> String:
	match kind:
		&"rays":
			return _rays()
		&"burst":
			return _burst()
		&"speed":
			return _speed()
		&"halftone":
			return _halftone()
		&"wedge":
			return _wedge()
	return _bars()


func _rays() -> String:
	var wedges := ""
	var spokes: Array[float] = [-170.0, -147.0, -124.0, -101.0, -78.0, -55.0, -32.0]
	for deg: float in spokes:
		var a := deg_to_rad(deg)
		var b := deg_to_rad(deg + 11.0)
		wedges += (
			"<path d='M55,118 L%.1f,%.1f L%.1f,%.1f Z'/>"
			% [55 + 170 * cos(a), 118 + 170 * sin(a), 55 + 170 * cos(b), 118 + 170 * sin(b)]
		)
	return '<g fill="#ffffff" opacity="0.13">%s</g>' % wedges


func _burst() -> String:
	var pts := PackedStringArray()
	for i in 20:
		var a := deg_to_rad(i * 18.0 - 9.0)
		var r := 30.0 if i % 2 == 1 else 62.0
		pts.append("%.1f,%.1f" % [55 + r * cos(a), 70 + r * sin(a)])
	var points := " ".join(pts)
	var out := '<polygon points="%s" fill="#ffffff" opacity="0.14"/>' % points
	var ring := 'fill="none" stroke="%s" stroke-width="2" opacity="0.5"' % _accent
	var move := 'transform="rotate(9 55 70) scale(0.8) translate(13.75 17.5)"'
	return out + '<polygon points="%s" %s %s/>' % [points, ring, move]


func _speed() -> String:
	var bands := ""
	var ys: Array[float] = [26.0, 40.0, 54.0, 68.0, 82.0, 96.0]
	for i in ys.size():
		var thin := i % 2 == 1
		var offset := 16.0 if thin else 0.0
		bands += _rect(-20.0 + offset, ys[i], 150, 3.0 if thin else 4.5, "#ffffff")
	return '<g transform="rotate(-16 55 70)" opacity="0.13">%s</g>' % bands


func _halftone() -> String:
	var dots := ""
	for row in 10:
		for col in 11:
			var stagger := 4.5 if row % 2 == 1 else 0.0
			dots += _circle(10.0 + col * 9 + stagger, 30.0 + row * 9, 2 - row * 0.12, "#ffffff")
	return '<g opacity="0.16">%s</g>' % dots


func _wedge() -> String:
	var shade := _path("M6,120 L104,22 L104,120 Z", "#000000", ' opacity="0.2"')
	var edge := ' stroke="#ffffff" stroke-width="2.5" opacity="0.35"'
	return shade + _path("M6,120 L104,22", "none", edge)


func _bars() -> String:
	var bars := _rect(17, 46, 13, 80, "#ffffff")
	bars += _rect(48, 30, 13, 96, "#ffffff")
	bars += _rect(79, 58, 13, 68, "#ffffff")
	return '<g opacity="0.15">%s</g>' % bars


# --- signature props ---------------------------------------------------------


## The one object each general is never without. Two are shouldered, so they are
## drawn behind the bust; the rest are held, and sit in front of it.
func _prop(id: StringName, layer: StringName, skin: String) -> String:
	return _prop_back(id) if layer == &"back" else _prop_front(id, skin)


func _prop_back(id: StringName) -> String:
	if id == &"sabre":
		var blade := _path("M82,96 L95,32 L101,35 L88,98 Z", "#cfd6dd", _line())
		return blade + _stroke_path("M79,91 L93,96", 4)
	if id == &"wrench":
		var shaft := _path("M80,96 L89,55 L97,57 L88,98 Z", "#aab3bb", _line())
		var jaw := "M86,57 Q82,44 93,41 Q104,39 103,50 L95,49 L94,55 Z"
		return shaft + _path(jaw, "#aab3bb", _line())
	return ""


func _prop_front(id: StringName, skin: String) -> String:
	match id:
		&"pipe":
			return _pipe()
		&"cigar":
			return _cigar()
		&"baton":
			return _baton(skin)
		&"medal":
			return _medal()
		&"card":
			return _card(skin)
		&"book":
			return _book(skin)
		&"drone":
			return _drone()
		&"falcon":
			return _falcon()
		&"dagger":
			return _dagger(skin)
		&"radio":
			return _radio(skin)
	return ""


func _hand(x: float, y: float, skin: String) -> String:
	return _circle(x, y, 5.5, skin, _line())


## Rising smoke — the shared puff trail behind a pipe and a cigar. Each puff is
## (x, y, radius), growing as it climbs.
func _smoke(puffs: Array[Vector3], opacity: String) -> String:
	var drawn := ""
	for puff: Vector3 in puffs:
		drawn += _circle(puff.x, puff.y, puff.z, "#ffffff")
	return '<g opacity="%s">%s</g>' % [opacity, drawn]


func _pipe() -> String:
	var stem := _stroke_path("M61,72 Q72,75 74,83", 3.5, "#5a3c28")
	var bowl := _circle(74.5, 86, 4.2, "#5a3c28", _line())
	var puffs: Array[Vector3] = [Vector3(82, 70, 3), Vector3(87, 59, 4), Vector3(92, 46, 5)]
	return stem + bowl + _smoke(puffs, "0.45")


func _cigar() -> String:
	var pen := ' stroke="%s" stroke-width="2" stroke-linejoin="round"' % _ink
	var roll := _rect(60, 70.5, 14, 4.8, "#7a4a2b", pen + ' rx="2" transform="rotate(20 60 71)"')
	var ember := _circle(73.5, 76.8, 2, _ember)
	var puffs: Array[Vector3] = [Vector3(79, 66, 2.6), Vector3(84, 56, 3.4)]
	return roll + ember + _smoke(puffs, "0.4")


func _baton(skin: String) -> String:
	var pen := ' stroke="%s" stroke-width="1.6" stroke-linejoin="round"' % _ink
	var stick := _path("M28,110 L84,92", "none", _tint("#5a3c28", 5))
	var caps := _circle(28, 110, 3, _gold, pen) + _circle(84, 92, 3, _gold, pen)
	return stick + caps + _hand(58, 101, skin)


func _medal() -> String:
	var pen := ' stroke="%s" stroke-width="1.8" stroke-linejoin="round"' % _ink
	var boards := _rect(10, 92, 15, 6, _gold, pen) + _rect(85, 92, 15, 6, _gold, pen)
	var ribbon := _path("M35,96 L44,96 L42.5,105 L36.5,105 Z", _accent, pen)
	return boards + ribbon + _circle(39.5, 109, 4.5, _gold, pen)


func _card(skin: String) -> String:
	var pen := ' stroke="%s" stroke-width="2.2" stroke-linejoin="round"' % _ink
	var face := _rect(75, 63, 15, 21, "#ffffff", pen + ' rx="2"')
	var pip := _path("M82.5,69 L86,73.5 L82.5,78 L79,73.5 Z", _accent)
	var held := '<g transform="rotate(-12 82 74)">%s%s</g>' % [face, pip]
	return held + _hand(80, 87, skin)


func _book(skin: String) -> String:
	var pages := _path("M14,106 Q26,97 38,106 L38,119 Q26,110 14,119 Z", "#ffffff", _line())
	return pages + _stroke_path("M26,101.5 L26,113", 2) + _hand(37, 112, skin)


func _drone() -> String:
	var arc := _stroke_path("M74,25 Q80,21 86,25", 2, "#ffffff")
	var rotors := _rect(76, 27, 9, 2.5, _accent) + _rect(89, 27, 9, 2.5, _accent)
	var body := _rect(80, 29.5, 14, 8, _slate, _line() + ' rx="2.5"')
	return '<g opacity="0.4">%s</g>' % arc + rotors + body + _circle(87, 33.5, 1.8, _led)


func _falcon() -> String:
	var body := _path("M22,77 Q13,81 14,92 Q15,99 23,99 Q31,97 30,86 Z", "#8c5a30", _line())
	var wing := _stroke_path("M17,83 Q12,90 18,96", 1.8)
	var head := _circle(25, 73.5, 6, "#f2ead8", _line())
	var pen := ' stroke="%s" stroke-width="1.6" stroke-linejoin="round"' % _ink
	var beak := _path("M30.5,73 L35,75 L30.5,77.5 Z", _gold, pen)
	return body + wing + head + beak + _circle(26, 72.5, 1.4, _ink)


func _dagger(skin: String) -> String:
	var blade := _path("M85,48 L89,72 L81,72 Z", "#cfd6dd", _line())
	var grip := _rect(83.3, 72, 3.4, 7, _ink)
	var ring := _circle(85, 85.5, 3, "none", _line(2))
	return blade + grip + _hand(85, 78, skin) + ring


func _radio(skin: String) -> String:
	var antenna := _stroke_path("M76,83 Q68,95 77,104 Q84,110 79,118", 2.2)
	var body := _rect(71, 65, 11, 18, _slate, _line(2.2) + ' rx="3"')
	var grille := _path("M73.5,69 H79.5 M73.5,72 H79.5", "none", _tint("#ffffff", 1.4))
	return antenna + body + '<g opacity="0.7">%s</g>' % grille + _hand(77, 85, skin)
