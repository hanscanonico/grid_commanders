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
## The figure/ground split, in two numbers: the wash that sinks the window field
## under the accent the uniform is now filled with, and the light along the
## bust's top edge that lifts it off that field.
const WINDOW_SHADE := 0.28
const RIM := "#ffffff"
const RIM_OPACITY := 0.22
## The design system's signature: a hard offset copy of the silhouette, zero
## blur. The offset is applied outside the pose and is the same on all 23 busts
## — the sheet is lit from one direction, so a mirrored general is not lit from
## the other one.
const CAST_OFFSET := Vector2(3, 3)
const CAST_OPACITY := 0.30
const SHADE := "#000000"
## The form shade, flat and hard like the cast: the head's shadow side, the neck
## the head casts down, the shoulder away from the light, and a lit band on the
## crown. Two face values because one is not readable on both ends of the skin
## ramp — 0.14 black is invisible on the darkest two.
const SHADE_FACE := 0.14
const SHADE_FACE_DARK := 0.2
const DARK_SKINS: Array[StringName] = [&"tan", &"dark"]
const SHADE_NECK := 0.22
const SHADE_UNIFORM := 0.24
## The crown highlight is white, so it is drawn only on hair dark enough to take
## one — on grey, platinum or blonde it reads as a bald patch — and only on the
## crowns solid enough to hold it, a shade path having to lie over a single flat
## fill and a spiky fringe's gaps or a bald pate putting it on skin.
const HAIR_LIT := "#ffffff"
const HAIR_LIT_OPACITY := 0.16
const HAIR_LIT_COLOURS: Array[StringName] = [&"auburn", &"black", &"brown", &"darkbrown"]
const HAIR_LIT_STYLES: Array[StringName] = [
	&"long",
	&"short",
	&"ponytail",
	&"bob",
	&"braid",
	&"buzz",
	&"sidepart",
	&"curly",
	&"bun",
]
## The uniform mass every bust rises out of, faction or not.
const SHOULDER_MASS := "M6,120 L6,110 Q6,93 32,90 L78,90 Q104,93 104,110 L104,120 Z"
## The centre of the skull: every head, ear, eye and hat is placed against it,
## and the per-commander width scales about it.
const HEAD_CX := 55.0
## The skull a general is drawn on, the FACES `head` column:
## [width, jaw, crown, spread]. Width scales the head path's x about HEAD_CX
## (0.86-1.14), jaw names its lower half (round, square, tapered), crown lifts
## the top of it (-3..+3, which is what buys age and brow-heaviness), and
## spread walks the eyes apart (0.9-1.1). A row without one gets these, which
## are the single head every bust used to share.
const HEAD_DEFAULT: Array = [1.0, &"round", 0.0, 1.0]
## The jaws `_jaw` knows how to draw. A name outside this vocabulary falls
## through to the round one, which is silent, so the FACES table is linted
## against these rather than against a literal spelled a second time.
const JAW_ROUND := &"round"
const JAW_SQUARE := &"square"
const JAW_TAPERED := &"tapered"
## The FACES `eye` column: the eye — ellipse, pupil and catchlights — scaled
## about its own centre (0.82-1.06). The eyes are the largest feature on the
## bust and the first thing read, so one shared size is the loudest "same
## template avatar" signal there is; this is the dial that breaks it.
const EYE_DEFAULT := 1.0
## Below this a small eye keeps a single catchlight: two sparkles on a small
## eye is what reads as a child's avatar rather than as a general.
const EYE_SINGLE_CATCHLIGHT := 0.92
## How far the eye band rides with the crown, in units per unit of crown. A
## lifted skull spends its lift on forehead, which also stops the 23 pairs of
## eyes sitting on one horizontal line across the contact sheet.
const EYE_CROWN_RATIO := 0.5
## The expression vocabulary the FACES table is linted against, for the reason
## the jaws are: a name outside it falls through to a default and says nothing.
const EYE_KINDS: Array[StringName] = [&"m", &"f", &"narrow", &"closed", &"lidded", &"wide"]
const BROW_KINDS: Array[StringName] = [&"soft", &"angled", &"raised", &"heavy", &"cocked"]
const MOUTH_KINDS: Array[StringName] = [
	&"smile",
	&"smirk",
	&"stern",
	&"snarl",
	&"grin",
	&"neutral",
	&"clench",
	&"laugh",
	&"wry",
	&"open",
]
## The collars a tunic is cut with, the FACES `collar` column: the V-necked
## chevron every general used to share, a standing mandarin band, and a
## double-breasted facing with two gold buttons. A row that names none wears
## COLLAR_DEFAULT, which draws the handoff's chevron unchanged.
const COLLAR_V := &"v"
const COLLAR_MANDARIN := &"mandarin"
const COLLAR_DOUBLE := &"double"
const COLLAR_DEFAULT := COLLAR_V
## The noses `_nose` knows how to draw, the FACES `nose` column. A name outside
## this vocabulary falls through to the tick, which is the one nose every bust
## shared before the column existed, so a row naming none is unchanged.
const NOSE_TICK := &"tick"
const NOSE_HOOK := &"hook"
const NOSE_BROAD := &"broad"
const NOSE_DEFAULT := NOSE_TICK
## The design system's three ink weights. Every ink stroke names one of them:
## the silhouette a bust is read by at chip size, the features inside it, and
## the marks that only pay off at full size — so a scar can never come out as
## heavy as a jaw. Backdrop washes and a coloured stroke drawn as a shape (a
## pipe stem, a baton's shaft) are not ink and carry their own thickness.
const INK_SILHOUETTE := 4.0
const INK_FEATURE := 3.0
const INK_DETAIL := 2.0

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

## Per-commander spec, one row per general. The table and the meaning of
## every column live in its own file now — this file draws it.
const FACES := preload("res://tools/commander_faces.gd").FACES

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
	out += _cast(_silhouette(face), _pose(face))
	out += '<g transform="%s">%s</g>' % [_pose(face), _bust(face)]
	return out + "</svg>"


## "No Commander": the same framed window with a featureless bust in it, so an
## empty seat reads as a deliberate styled choice rather than a missing file.
## Slate rather than the faction shade, so the bust reads as no army at all
## instead of as an unlit one against the window it sits in.
func build_neutral() -> String:
	var out := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s">' % VIEW_BOX
	out += _clip_def()
	out += _window()
	out += '<g clip-path="url(#win)">%s</g>' % _backdrop(&"bars")
	var body := _blank_shoulders() + _neck(_slate) + _head(_slate) + _blank_crown()
	var pose := "translate(55 120) scale(1.18) translate(-55 -120)"
	out += _cast(_path(SHOULDER_MASS, SHADE, _line()) + _neck(SHADE) + _head(SHADE), pose)
	out += '<g transform="%s">' % pose
	return out + body + "</g></svg>"


## The empty seat's uniform: the same mass in slate, under a collar cut shallow
## enough to clear the design system's diamond, struck on the chest where a
## faction chevron goes.
func _blank_shoulders() -> String:
	var out := _path(SHOULDER_MASS, _slate, _line())
	out += _stroke_path("M44,90 L55,93 L66,90", INK_FEATURE)
	return out + _stroke_path("M55,93 L62,100 L55,107 L48,100 Z", INK_FEATURE)


## One hard band down the crown, so a featureless head still has form rather
## than reading as a hole cut out of the window.
func _blank_crown() -> String:
	var lit := hex(UiTheme.SLATE_800.lightened(0.34))
	return _path("M34.5,50 Q35,29.5 55,28.5 L55,34.5 Q41,35.5 40.5,51 Z", lit)


# --- frame -------------------------------------------------------------------


func _clip_def() -> String:
	return (
		'<clipPath id="win"><rect x="%s" y="%s" width="%s" height="%s"/></clipPath>'
		% [WINDOW.position.x, WINDOW.position.y, WINDOW.size.x, WINDOW.size.y]
	)


## The ink-bordered field the backdrop is clipped to, with a black wash over it:
## the uniform below is the accent itself, so the wall has to sit a value deeper
## than the bust or the two merge into one faction rectangle.
func _window() -> String:
	var field := (
		'<rect x="%s" y="%s" width="%s" height="%s" fill="%s" stroke="%s" stroke-width="%s"/>'
		% [
			WINDOW.position.x,
			WINDOW.position.y,
			WINDOW.size.x,
			WINDOW.size.y,
			_accent_dark,
			_ink,
			INK_FEATURE,
		]
	)
	var wash := _rect(
		WINDOW.position.x,
		WINDOW.position.y,
		WINDOW.size.x,
		WINDOW.size.y,
		"#000000",
		' opacity="%s"' % WINDOW_SHADE
	)
	return field + wash


func _pose(face: Dictionary) -> String:
	var pose: Array = face["pose"]
	var mirror := "translate(110 0) scale(-1 1) " if bool(pose[2]) else ""
	return (
		"%srotate(%s 55 70) translate(55 120) scale(%s) translate(-55 -120)"
		% [mirror, pose[0], pose[1]]
	)


# --- stroke helpers ----------------------------------------------------------


## The signature ink outline, round-joined, at one of the three weights. The
## default is the heaviest: the bust's own outline is most of what this draws.
func _line(weight := INK_SILHOUETTE) -> String:
	return (
		' stroke="%s" stroke-width="%s" stroke-linejoin="round" stroke-linecap="round"'
		% [_ink, weight]
	)


func _path(d: String, fill: String, extra := "") -> String:
	return '<path d="%s" fill="%s"%s/>' % [d, fill, extra]


## An outlined path with no fill — the shape of every brow, lash and crease.
func _stroke_path(d: String, weight: float, color := "") -> String:
	var pen := _line(weight) if color.is_empty() else _tint(color, weight)
	return _path(d, "none", pen)


## The lit top edge of the uniform: the design system's hard offset shadow read
## on a bust, and the line that keeps the shoulders off the field behind them.
func _rim() -> String:
	return _tint(RIM, INK_DETAIL) + ' opacity="%s"' % RIM_OPACITY


func _tint(color: String, width: float) -> String:
	return ' stroke="%s" stroke-width="%s" stroke-linecap="round"' % [color, width]


func _circle(cx: float, cy: float, r: float, fill: String, extra := "") -> String:
	return '<circle cx="%s" cy="%s" r="%s" fill="%s"%s/>' % [cx, cy, r, fill, extra]


func _ellipse(cx: float, cy: float, rx: float, ry: float, fill: String, extra := "") -> String:
	return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s"%s/>' % [cx, cy, rx, ry, fill, extra]


func _rect(x: float, y: float, w: float, h: float, fill: String, extra := "") -> String:
	return '<rect x="%s" y="%s" width="%s" height="%s" fill="%s"%s/>' % [x, y, w, h, fill, extra]


# --- the bust ----------------------------------------------------------------


func _bust(face: Dictionary) -> String:
	var skin: String = SKIN[face["skin"]]
	var hair: String = HAIR[face["hair"]]
	var geom := _head_geom(face)
	var width := float(geom[0])
	var xs := _eye_xs(face)
	var out := _prop(face["prop"], &"back", skin)
	if face["style"] == &"hood":
		out += _path("M20,120 Q12,64 55,50 Q98,64 90,120 Z", _accent, _line())
	out += _crowned(_hair_back(face["style"], hair), geom)
	out += _shoulders(face) + _shade_uniform(face)
	out += _neck(skin, width) + _shade_neck(width)
	out += _ears(skin, width, face.get("earring", false))
	out += _head(skin, face) + _shade_face(face)
	out += _crowned(_facial(face["facial"], hair), geom, false)
	var crown := _hair_front(face["style"], hair) + _shade_hair(face) + _headwear(face["acc"])
	out += _crowned(crown, geom)
	var band := _brows(face["brow"], xs)
	band += _eyes(face["eyes"], xs, float(face.get("eye", EYE_DEFAULT)))
	band += _eyewear(face["acc"], xs, width)
	out += _banded(band, geom)
	out += _nose(face.get("nose", NOSE_DEFAULT), width)
	out += _mouth(face["mouth"])
	out += _details(face, xs, geom)
	return out + _prop(face["prop"], &"front", skin)


## Uniform shoulders rising off the bottom edge, cut with the general's own
## collar and, for the four costliest powers, a rank pip on it.
func _shoulders(face: Dictionary) -> String:
	var collar: StringName = face.get("collar", COLLAR_DEFAULT)
	var out := _path(SHOULDER_MASS, _accent, _line())
	out += _path("M6,110 Q6,93 32,90 L78,90 Q104,93 104,110", "none", _rim())
	out += _collar(collar)
	if face.get("pip", false):
		out += _rank_pip(collar)
	return out


## The collar itself. The V is the one the handoff authored — an ink neckline
## over the faction chevron — and the two others cut the same neckline
## differently rather than adding anything beside it.
func _collar(kind: StringName) -> String:
	match kind:
		COLLAR_MANDARIN:
			var band := "M40,100 Q40,87 48,85 L62,85 Q70,87 70,100 Q55,105 40,100 Z"
			var stand := _stroke_path("M55,85 L55,103", INK_DETAIL)
			return _path(band, _accent_dark, _line(INK_FEATURE)) + stand
		COLLAR_DOUBLE:
			var facing := _path("M63,90 L73,90 L54,120 L43,120 Z", _accent_dark)
			var pen := _line(INK_DETAIL)
			var buttons := _circle(61.5, 100, 2, _gold, pen) + _circle(55, 110, 2, _gold, pen)
			return facing + _stroke_path("M40,90 L47,97 L63,90", INK_FEATURE) + buttons
	var neckline := _stroke_path("M44,90 L55,101 L66,90", INK_FEATURE)
	return neckline + _path("M40,90 L55,104 L70,90 L70,94 L55,108 L40,94 Z", _accent_dark)


## The rank pip the costliest powers wear, placed where its own collar leaves
## room for it: in the V's notch, on the mandarin band, and out on the shoulder
## where a double-breasted facing already carries buttons.
func _rank_pip(collar: StringName) -> String:
	var at := Vector2(55, 97)
	if collar == COLLAR_MANDARIN:
		at = Vector2(55, 96.5)
	elif collar == COLLAR_DOUBLE:
		at = Vector2(34, 100)
	return _circle(at.x, at.y, 2.2, _gold, _line(INK_DETAIL))


## The skull's own x, scaled about its centre: the one place a width is applied.
func _hx(x: float, width: float) -> float:
	return snappedf(HEAD_CX + (x - HEAD_CX) * width, 0.01)


func _head_geom(face: Dictionary) -> Array:
	return face.get("head", HEAD_DEFAULT)


## The two eye centres every brow, lash, lens and freckle is placed against.
func _eye_xs(face: Dictionary) -> Array[float]:
	var geom := _head_geom(face)
	var half := snappedf(10.0 * float(geom[0]) * float(geom[3]), 0.01)
	return [HEAD_CX - half, HEAD_CX + half]


## Hair, hats and the headset band are drawn against the one skull the handoff
## authored, so they ride the head's own width and crown rather than being
## redrawn per general. Facial hair takes the width without the lift: it hangs
## off the chin, which the crown never moves. An unspecified head leaves the
## fragment untouched.
func _crowned(inner: String, geom: Array, lift := true) -> String:
	var width := float(geom[0])
	var crown := float(geom[2]) if lift else 0.0
	if is_equal_approx(width, 1.0) and is_zero_approx(crown):
		return inner
	return (
		'<g transform="translate(%s %s) scale(%s 1) translate(-%s 0)">%s</g>'
		% [HEAD_CX, -crown, width, HEAD_CX, inner]
	)


## Brows, eyes and eyewear move as one band, so a pair of glasses, a patch or a
## lash still sits on the eye it was drawn for however far the crown walks them.
func _banded(inner: String, geom: Array) -> String:
	var dy := snappedf(float(geom[2]) * EYE_CROWN_RATIO, 0.01)
	if is_zero_approx(dy):
		return inner
	return '<g transform="translate(0 %s)">%s</g>' % [dy, inner]


## A neck as wide as the skull it carries — a broad head over the stock one
## reads as a bobblehead.
func _neck(skin: String, width := 1.0) -> String:
	return _path(_neck_d(width), skin, _line())


## Drawn twice — once in skin, once as the shadow the head casts down it — so
## the two can never be cut differently.
func _neck_d(width: float) -> String:
	var side := _hx(47, width)
	var far := _hx(63, width)
	return "M%s,76 L%s,90 Q%s,95 %s,90 L%s,76 Z" % [side, side, HEAD_CX, far, far]


## Ears as big as the skull they are set into, with the earring hung off the
## lobe rather than at a fixed height: a stock ear on a 1.14 head is what makes
## a wide bust read as a narrow one stretched.
func _ears(skin: String, width: float, earring: bool) -> String:
	var pen := _line(INK_FEATURE)
	var r := snappedf(5.0 * width, 0.01)
	var out := _circle(_hx(31, width), 58, r, skin, pen) + _circle(_hx(79, width), 58, r, skin, pen)
	if not earring:
		return out
	return out + _circle(_hx(31, width), snappedf(58.5 + r, 0.01), 1.9, _gold, _line(INK_DETAIL))


## The nose, one of three glyphs, drawn on the skull's own x — the tick is the
## single nose every bust used to share, so a row naming none is unchanged.
func _nose(kind: StringName, width: float) -> String:
	if kind == NOSE_HOOK:
		var hook := (
			"M%s,58 Q%s,63 %s,66.4 Q%s,67.6 %s,66"
			% [_hx(55.6, width), _hx(58.2, width), _hx(56.4, width), _hx(55, width), _hx(53, width)]
		)
		return _stroke_path(hook, INK_FEATURE)
	if kind == NOSE_BROAD:
		var broad := (
			"M%s,60.5 L%s,65 Q%s,68 %s,65"
			% [_hx(55, width), _hx(51.8, width), _hx(55, width), _hx(58.2, width)]
		)
		return _stroke_path(broad, INK_FEATURE)
	var tick := (
		"M%s,60 L%s,65 Q%s,66.5 %s,65.2"
		% [_hx(55, width), _hx(53.5, width), _hx(55, width), _hx(57, width)]
	)
	return _stroke_path(tick, INK_FEATURE)


func _head(skin: String, face: Dictionary = {}) -> String:
	var geom := _head_geom(face)
	var width := float(geom[0])
	var top := 27.0 - float(geom[2])
	var left := _hx(32, width)
	var right := _hx(78, width)
	var d := (
		"M%s,52 Q%s,%s %s,%s Q%s,%s %s,52 L%s,60 "
		% [left, left, top, HEAD_CX, top, right, top, right, right]
	)
	return _path(d + _jaw(geom[1], width, left, right), skin, _line())


## The lower half of the skull, from the cheekbone down.
func _jaw(kind: StringName, width: float, left: float, right: float) -> String:
	if kind == JAW_SQUARE:
		return (
			"L%s,80 Q%s,88 %s,89 Q%s,88 %s,80 L%s,60 Z"
			% [_hx(74, width), _hx(70, width), HEAD_CX, _hx(40, width), _hx(36, width), left]
		)
	if kind == JAW_TAPERED:
		return "Q%s,80 %s,89 Q%s,80 %s,60 Z" % [_hx(76, width), HEAD_CX, _hx(34, width), left]
	return "Q%s,84 %s,89 Q%s,84 %s,60 Z" % [right, HEAD_CX, left, left]


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


## Every fringe the table holds: one filled path, with circles for the shapes a
## curve cannot carry — `under` sits behind the path, `over` in front of it —
## and a `pen` only where the silhouette outline is not what the style wears.
const HAIR_FRONT := {
	&"long":
	{
		"d":
		(
			"M32,46 Q34,30 55,28 Q76,30 78,46 Q70,36 60,38"
			+ " Q56,30 47,36 Q40,34 40,44 Q36,40 32,46 Z"
		)
	},
	&"short": {"d": "M31,48 Q30,28 55,26 Q80,28 79,48 Q74,36 55,35 Q36,35 31,48 Z"},
	&"ponytail": {"d": "M31,48 Q30,28 55,26 Q80,28 79,48 Q72,37 55,36 Q40,36 40,45 Q35,42 31,48 Z"},
	&"bob": {"d": "M30,48 Q29,27 55,25 Q81,27 80,48 Q73,35 55,34 Q37,35 30,48 Z"},
	&"braid": {"d": "M31,48 Q30,28 55,26 Q80,28 79,48 Q72,37 55,36 Q38,36 31,48 Z"},
	&"buzz":
	{
		"d": "M33,46 Q34,31 55,30 Q76,31 77,46 Q70,40 55,40 Q40,40 33,46 Z",
		"pen": ' opacity="0.85"',
	},
	&"sidepart": {"d": "M31,47 Q30,28 55,26 Q80,28 79,45 Q75,35 52,35 Q50,33 44,38 Q38,36 31,47 Z"},
	&"spiky":
	{
		"d":
		(
			"M31,47 L34,30 L41,40 L46,27 L52,39 L58,27 L64,39 L70,29 L76,41"
			+ " L79,47 Q70,38 55,38 Q40,38 31,47 Z"
		)
	},
	&"curly":
	{
		"d": "M32,48 Q34,40 40,40 L70,40 Q76,40 78,48 Q70,42 55,42 Q40,42 32,48 Z",
		"under": [[38, 36, 8], [50, 31, 8.5], [62, 31, 8.5], [73, 37, 8]],
	},
	&"bald":
	{
		"d": "M34,44 Q36,36 44,35 Q40,40 40,46 Z M76,44 Q74,36 66,35 Q70,40 70,46 Z",
		"pen": "",
	},
	&"bun":
	{
		"d": "M31,48 Q30,30 55,28 Q80,30 79,48 Q72,38 55,38 Q38,38 31,48 Z",
		"over": [[55, 24, 9]],
	},
}


func _hair_front(style: StringName, hair: String) -> String:
	if not HAIR_FRONT.has(style):
		return ""
	var spec: Dictionary = HAIR_FRONT[style]
	var pen: String = spec.get("pen", _line())
	var out := ""
	for c: Array in spec.get("under", []):
		out += _circle(c[0], c[1], c[2], hair, pen)
	out += _path(spec["d"], hair, pen)
	for c: Array in spec.get("over", []):
		out += _circle(c[0], c[1], c[2], hair, pen)
	return out


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
			var lining := "M24,64 Q26,48 55,44 Q84,48 86,64 Q80,44 55,44 Q30,44 24,64 Z"
			return _path(d, _accent, pen) + _path(lining, _accent_dark)
	return ""


## Lenses and a patch ride the eyes they cover, so a narrow face wears its
## glasses narrow; the strap crosses the skull, so it rides its width.
func _eyewear(acc: StringName, xs: Array[float], width: float) -> String:
	var left := xs[0] - 45.0
	var right := xs[1] - 65.0
	if acc == &"eyepatch":
		var strap := _stroke_path("M%s,50 L%s,45" % [_hx(28, width), _hx(82, width)], INK_FEATURE)
		return strap + _rect(38 + left, 52, 15, 12, _ink, ' rx="3"')
	if acc == &"glasses":
		var pen := ' fill="none"' + _line(INK_FEATURE)
		var lenses := '<rect x="%s" y="52" width="15" height="11" rx="3"%s/>' % [38 + left, pen]
		lenses += '<rect x="%s" y="52" width="15" height="11" rx="3"%s/>' % [57 + right, pen]
		return lenses + _stroke_path("M%s,56 H%s" % [53 + left, 57 + right], INK_FEATURE)
	return ""


## Everything drawn over the face: a scar, freckles, a headset boom.
func _details(face: Dictionary, xs: Array[float], geom: Array) -> String:
	var out := ""
	if face["acc"] == &"scar":
		var cuts: Array[String] = ["M67,49 L71,60", "M65,52 L68,53", "M67,56 L70,57"]
		for d: String in cuts:
			out += _stroke_path(d, INK_DETAIL, "#b56b5a")
	if face.get("freckles", false):
		var dots := ""
		for x: float in xs:
			dots += _circle(x - 3, 66, 1, "#b56b5a") + _circle(x, 68, 1, "#b56b5a")
			dots += _circle(x + 3, 66, 1, "#b56b5a")
		out += '<g opacity="0.5">%s</g>' % dots
	if face["acc"] == &"headset":
		var rig := _stroke_path("M30,50 Q30,32 55,32 Q80,32 80,50", INK_FEATURE)
		rig += _rect(26, 50, 8, 12, _accent_dark, _line(INK_FEATURE) + ' rx="3"')
		rig += _stroke_path("M28,60 Q24,68 40,70", INK_DETAIL)
		rig += _circle(41, 70.5, 2.4, _accent, _line(INK_DETAIL))
		out += _crowned(rig, geom)
	return out


# --- shading -----------------------------------------------------------------


## The cast shadow: the bust's own silhouette, offset and filled flat black at
## one opacity. Clipped to the window, because the shadow falls on the wall the
## window frames; offset *outside* the pose, so a mirrored or tilted general
## casts it in the same direction as everyone else. Group opacity rather than
## per-path, so the shapes composite once instead of darkening where they meet.
func _cast(body: String, pose: String) -> String:
	return (
		'<g clip-path="url(#win)" opacity="%s"><g transform="translate(%s %s) %s">%s</g></g>'
		% [CAST_OPACITY, CAST_OFFSET.x, CAST_OFFSET.y, pose, body]
	)


## What the shadow is a shadow of: the bust's own shapes in flat black, minus
## the face, the kit and the props — none of which reaches the outline. Drawn
## from the same helpers as the bust, so a skull or a hairstyle can never grow a
## shadow of a different shape.
func _silhouette(face: Dictionary) -> String:
	var geom := _head_geom(face)
	var out := ""
	if face["style"] == &"hood":
		out += _path("M20,120 Q12,64 55,50 Q98,64 90,120 Z", SHADE, _line())
	out += _crowned(_hair_back(face["style"], SHADE), geom)
	out += _path(SHOULDER_MASS, SHADE, _line())
	out += _neck(SHADE, float(geom[0]))
	out += _head(SHADE, face)
	return out + _crowned(_hair_front(face["style"], SHADE), geom)


## A shade's x, mirrored about the skull's centre for the five flipped poses so
## that the light still comes from the same screen side, and scaled by the
## skull's own width so the shade stays over the fill it shades. `width` is left
## at 1 for the shapes drawn inside `_crowned`, which scales them itself.
func _sx(x: float, face: Dictionary, width := 1.0) -> float:
	var pose: Array = face["pose"]
	var lit := HEAD_CX * 2.0 - x if bool(pose[2]) else x
	return _hx(lit, width)


func _shade(d: String, opacity: float, color := SHADE) -> String:
	return _path(d, color, ' opacity="%s"' % opacity)


## The head's shadow side and the underside of the jaw, held inside the skull's
## own outline at its narrowest jaw.
func _shade_face(face: Dictionary) -> String:
	var width := float(_head_geom(face)[0])
	var outer := _sx(75, face, width)
	var inner := _sx(66, face, width)
	var top := _sx(64, face, width)
	var d := (
		"M%s,52 L%s,62 Q%s,80 %s,86 Q%s,78 %s,58 Q%s,54 %s,50 Z"
		% [outer, outer, outer, HEAD_CX, inner, inner, inner, top]
	)
	var deep: bool = DARK_SKINS.has(face["skin"])
	return _shade(d, SHADE_FACE_DARK if deep else SHADE_FACE)


## The neck is the one place the head casts onto the body, and it is what makes
## the chin read at chip size.
func _shade_neck(width: float) -> String:
	return _shade(_neck_d(width), SHADE_NECK)


## The shoulder away from the light, so the uniform has a lit side and a dark
## one. Kept clear of the collar, which owns its own shape.
func _shade_uniform(face: Dictionary) -> String:
	var edge := _sx(78, face)
	var lip := _sx(86, face)
	var bend := _sx(96, face)
	var side := _sx(97, face)
	var d := "M%s,93 L%s,93 Q%s,98 %s,110 L%s,120 L%s,120 Z" % [edge, lip, bend, side, side, edge]
	return _shade(d, SHADE_UNIFORM)


## One hard band on the crown, on the hair dark enough to show it.
func _shade_hair(face: Dictionary) -> String:
	if not HAIR_LIT_COLOURS.has(face["hair"]) or not HAIR_LIT_STYLES.has(face["style"]):
		return ""
	var d := (
		"M%s,34.4 Q%s,31.6 %s,31 Q%s,33.2 %s,34.8 Z"
		% [_sx(44, face), _sx(47, face), _sx(57, face), _sx(48, face), _sx(45.6, face)]
	)
	return _shade(d, HAIR_LIT_OPACITY, HAIR_LIT)


# --- face parts --------------------------------------------------------------


## The eye, at the size the `eye` column asked for. Every radius and offset is
## taken about the eye's own centre, so the scale is the one number that says
## how big a general's eyes are.
func _eyes(kind: StringName, xs: Array[float], scale := EYE_DEFAULT) -> String:
	var out := ""
	if kind == &"closed":
		for x: float in xs:
			var half := 4.5 * scale
			out += _stroke_path(
				"M%s,57 Q%s,%s %s,57" % [x - half, x, 57 + 3.5 * scale, x + half], INK_FEATURE
			)
		return out
	var rx := 4.1 * scale
	var ry := _eye_ry(kind) * scale
	var pupil := (1.7 if kind == &"wide" else 2.1) * scale
	for x: float in xs:
		out += _ellipse(x, 57, rx, ry, "#ffffff", _line(INK_FEATURE))
		out += _circle(x, 57 + 0.4 * scale, pupil, _ink)
		out += _circle(x + 1.1 * scale, 57 - 1.0 * scale, 0.9 * scale, "#ffffff")
		if scale >= EYE_SINGLE_CATCHLIGHT:
			out += _circle(x - 1.5 * scale, 57 + 1.4 * scale, 0.55 * scale, "#ffffff")
		if kind == &"lidded":
			out += _stroke_path(_lid(x, rx, ry), INK_FEATURE)
	if kind == &"f":
		for x: float in xs:
			out += _stroke_path("M%s,53.6 Q%s,51.2 %s,53.6" % [x - 5, x, x + 5], INK_FEATURE)
	return out


## A heavy upper lid over the top third of the eye — the hooded read a doctrine
## that spends its own units wants.
func _lid(x: float, rx: float, ry: float) -> String:
	var edge := 57 - ry * 0.3
	return "M%s,%s Q%s,%s %s,%s" % [x - rx, edge, x, 57 - ry * 1.2, x + rx, edge]


func _eye_ry(kind: StringName) -> float:
	if kind == &"narrow" or kind == &"lidded":
		return 2.6
	if kind == &"wide":
		return 5.4
	return 4.4


func _brows(kind: StringName, xs: Array[float]) -> String:
	var out := ""
	for i: int in xs.size():
		out += _brow(_brow_side(kind, i), xs[i], i)
	return out


## `cocked` is the one brow whose halves differ — one raised, one level — which
## is why the brows are drawn a side at a time. Every other kind hands both
## sides its own shape.
func _brow_side(kind: StringName, side: int) -> StringName:
	if kind != &"cocked":
		return kind
	return &"raised" if side == 0 else &"soft"


func _brow(kind: StringName, x: float, side: int) -> String:
	if kind == &"angled" or kind == &"heavy":
		var heavy := kind == &"heavy"
		var drop := 1.5 if heavy else 0.0
		var rise := (48.5 if side == 0 else 52.0) + drop
		var fall := (52.0 if side == 0 else 48.5) + drop
		var d := "M%s,%s L%s,%s" % [x - 5.5, rise, x + 5.5, fall]
		return _stroke_path(d, INK_SILHOUETTE if heavy else INK_FEATURE)
	if kind == &"raised":
		return _stroke_path("M%s,48 Q%s,45.5 %s,48" % [x - 5, x, x + 5], INK_FEATURE)
	return _stroke_path("M%s,49.5 Q%s,47.5 %s,49.5" % [x - 5, x, x + 5], INK_FEATURE)


func _mouth(kind: StringName) -> String:
	match kind:
		&"smile":
			return _stroke_path("M47.5,70 Q55,78 62.5,70", INK_FEATURE)
		&"smirk":
			return _stroke_path("M48.5,72 Q56,74 62.5,69", INK_FEATURE)
		&"stern":
			return _stroke_path("M49,72 Q55,70.5 61,72.5", INK_FEATURE)
		&"snarl":
			var bite := "M47,68.5 Q55,66.5 63,68.5 L61,76 Q55,79 49,76 Z"
			var jaw := _path(bite, _ink, _line(INK_FEATURE))
			return jaw + _stroke_path("M48.5,70 H61.5", INK_DETAIL, "#ffffff")
		&"grin":
			var open := _path("M47,68.5 Q55,80 63,68.5 Z", _ink, _line(INK_FEATURE))
			return open + _stroke_path("M49.5,70.5 H60.5", INK_DETAIL, "#ffffff")
		&"clench":
			var set_line := _stroke_path("M48.5,71 H61.5", INK_FEATURE)
			var left_corner := _stroke_path("M48.8,70.8 L47.6,73.4", INK_DETAIL)
			return set_line + left_corner + _stroke_path("M61.2,70.8 L62.4,73.4", INK_DETAIL)
		&"laugh":
			var wide := _path("M46,67.5 Q55,82.5 64,67.5 Z", _ink, _line(INK_FEATURE))
			var teeth := _stroke_path("M48.5,69.5 H61.5", INK_DETAIL, "#ffffff")
			return '<g transform="rotate(4 55 71)">%s</g>' % (wide + teeth)
		&"wry":
			return _stroke_path("M47,71 Q55,72 63,67.5", INK_FEATURE)
		&"open":
			var shout := _ellipse(55, 74, 4.6, 4.8, _ink, _line(INK_FEATURE))
			return shout + _stroke_path("M52.6,76.4 Q55,79 57.4,76.4", INK_DETAIL, "#ffffff")
	return _stroke_path("M49,71.5 H61", INK_FEATURE)


# --- backdrops ---------------------------------------------------------------


## One of seven dramatic treatments behind the bust, clipped to the window.
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
		&"grid":
			return _grid()
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
	var hub := _path("M21,118 A34,34 0 0 1 89,118 Z", "#ffffff", ' opacity="0.12"')
	return ('<g fill="#ffffff" opacity="0.2">%s</g>' % wedges) + hub


func _burst() -> String:
	var pts := PackedStringArray()
	for i in 20:
		var a := deg_to_rad(i * 18.0 - 9.0)
		var r := 30.0 if i % 2 == 1 else 62.0
		pts.append("%.1f,%.1f" % [55 + r * cos(a), 70 + r * sin(a)])
	var points := " ".join(pts)
	var out := '<polygon points="%s" fill="#ffffff" opacity="0.22"/>' % points
	return out + _burst_ring(points, 0.8, 9.0, 2.0) + _burst_ring(points, 0.6, -7.0, 1.6)


## A concentric copy of the star, scaled about its own centre (55,70).
func _burst_ring(points: String, scale: float, rot: float, width: float) -> String:
	var back := (1.0 - scale) / scale
	var ring := 'fill="none" stroke="%s" stroke-width="%s" opacity="0.5"' % [_accent, width]
	var move := (
		'transform="rotate(%s 55 70) scale(%s) translate(%.2f %.2f)"'
		% [rot, scale, 55 * back, 70 * back]
	)
	return '<polygon points="%s" %s %s/>' % [points, ring, move]


func _speed() -> String:
	var bands := ""
	var ys: Array[float] = [26.0, 40.0, 54.0, 68.0, 82.0, 96.0]
	for i in ys.size():
		var thin := i % 2 == 1
		var offset := 16.0 if thin else 0.0
		bands += _rect(-20.0 + offset, ys[i], 150, 3.0 if thin else 4.5, "#ffffff")
	var slab := _rect(-20.0, 33.0, 150, 9.0, "#ffffff") + _rect(-20.0, 89.0, 150, 9.0, "#ffffff")
	var tilt := 'transform="rotate(-16 55 70)"'
	return '<g %s opacity="0.2">%s</g><g %s opacity="0.3">%s</g>' % [tilt, bands, tilt, slab]


func _halftone() -> String:
	var dots := ""
	for row in 10:
		for col in 11:
			var stagger := 4.5 if row % 2 == 1 else 0.0
			dots += _circle(10.0 + col * 9 + stagger, 30.0 + row * 9, 2.6 - row * 0.16, "#ffffff")
	return '<g opacity="0.24">%s</g>' % dots


## Two flat values split by one hard diagonal, rather than a bright hairline on
## a single field a near-black uniform then disappears into. The split runs
## clear of the shoulders at every x, so the lit half sits behind the head and
## the hair while the uniform keeps the deep half to be a silhouette against —
## a lit field level with the shoulders would wash them out instead. Held at
## 0.24 white, the backdrop ceiling, so the face stays the brightest thing in
## the frame.
func _wedge() -> String:
	var deep := _path("M6,84 L104,44 L104,120 L6,120 Z", "#000000", ' opacity="0.2"')
	var lit := _path("M6,24 L104,24 L104,44 L6,84 Z", "#ffffff", ' opacity="0.24"')
	var edge := ' stroke="#000000" stroke-width="2.5" opacity="0.35"'
	return deep + lit + _path("M6,84 L104,44", "none", edge)


func _bars() -> String:
	var bars := _rect(17, 46, 13, 80, "#ffffff")
	bars += _rect(48, 30, 13, 96, "#ffffff")
	bars += _rect(79, 58, 13, 68, "#ffffff")
	var edge := _rect(48, 30, 13, 96, "none", _line(INK_DETAIL))
	return '<g opacity="0.22">%s</g><g opacity="0.4">%s</g>' % [bars, edge]


## The strategist's lattice: a 12-unit ruled grid over the whole window.
func _grid() -> String:
	var lines := ""
	for i in 10:
		lines += _rect(6.0 + i * 12.0, -20.0, 1.2, 160, "#ffffff")
		lines += _rect(-20.0, 24.0 + i * 12.0, 150, 1.2, "#ffffff")
	return '<g opacity="0.18">%s</g>' % lines


# --- signature props ---------------------------------------------------------

## The hard offset shadow every prop drops, in the design system's idiom at prop
## scale: pure black, no blur, down and to the right, the same direction the
## bust's own cast runs so one light serves the whole figure.
const PROP_CAST := Vector2(2, 2)
const PROP_CAST_ALPHA := 0.25
## Every painted fill and stroke in a prop's markup. `fill="none"` is
## deliberately unmatched: an outline-only shape casts only its outline.
const PAINTED := '(fill|stroke)="#[0-9a-fA-F]+"'

var _painted := RegEx.create_from_string(PAINTED)


## The one object each general is never without. The shouldered ones are drawn
## behind the bust; the rest are held, and sit in front of it. Either way it
## casts, so it reads as standing off what is behind it.
##
## Two placement rules the drawings are laid out against: a whole object stands
## low and near x 12-48, because the pose scales up to 1.28 about (55, 120) and
## anything higher or further out crops; a shouldered haft sits outside x 86, or
## the `long` and `hood` back hair swallows it. A prop that breaks the frame on
## the right stops short of x 98, which is the 4px of bleed the raster needs.
func _prop(id: StringName, layer: StringName, skin: String) -> String:
	var drawn := _prop_back(id) if layer == &"back" else _prop_front(id, skin)
	return "" if drawn.is_empty() else _prop_cast(drawn) + drawn


## A prop's cast shadow: the same drawing again, flattened to one tone and
## dropped, so the object sits in front of what is behind it rather than on it.
## Named apart from the bust's own `_cast`, which offsets a whole posed
## silhouette rather than re-tinting one drawing.
func _prop_cast(markup: String) -> String:
	return (
		'<g transform="translate(%s %s)" opacity="%s">%s</g>'
		% [PROP_CAST.x, PROP_CAST.y, PROP_CAST_ALPHA, _painted.sub(markup, '$1="#000000"', true)]
	)


func _prop_back(id: StringName) -> String:
	match id:
		&"sabre":
			var blade := _path("M82,96 L95,32 L101,35 L88,98 Z", "#cfd6dd", _line(INK_FEATURE))
			return blade + _stroke_path("M79,91 L93,96", INK_SILHOUETTE)
		&"wrench":
			var shaft := _path("M80,96 L89,55 L97,57 L88,98 Z", "#aab3bb", _line(INK_FEATURE))
			var jaw := "M86,57 Q82,44 93,41 Q104,39 103,50 L95,49 L94,55 Z"
			return shaft + _path(jaw, "#aab3bb", _line(INK_FEATURE))
		&"anchor":
			return _anchor()
		&"axe":
			return _axe()
		&"hammer":
			return _hammer()
	return ""


## A shouldered prop is carried, so its front layer is the strap that carries
## it; everything else is worn or held.
func _prop_front(id: StringName, skin: String) -> String:
	if not _prop_back(id).is_empty():
		return _strap(id)
	var worn := _prop_worn(id)
	return worn if not worn.is_empty() else _prop_held(id, skin)


## What carries the haft behind the bust, so the object reads as slung rather
## than as painted on the field. Five shouldered props, five different rigs —
## three of them are Meridian, and one shared diagonal band across the chest was
## the loudest repeated mark on the contact sheet.
func _strap(id: StringName) -> String:
	match id:
		&"wrench":
			var loop := _path("M72,88 L90,94 L84,108 L66,102 Z", _accent_dark, _line(INK_DETAIL))
			return loop + _rect(72, 94, 8, 7, _slate, _line(INK_DETAIL) + ' rx="1.5"')
		&"anchor":
			return _cord(82, 90, 63, 122) + _cord(88, 94, 69, 126)
		&"axe":
			var down := _path("M80,90 L89,95 L73,122 L64,117 Z", _accent_dark, _line(INK_DETAIL))
			var across := _path("M69,95 L74,88 L93,104 L88,112 Z", _accent_dark, _line(INK_DETAIL))
			return down + across + _circle(78, 101, 3.4, _gold, _line(INK_DETAIL))
		&"hammer":
			var bandolier := _path(
				"M82,93 L93,100 L64,120 L56,111 Z", _accent_dark, _line(INK_DETAIL)
			)
			var loops := (
				_stroke_path("M78,98 L72,107", INK_DETAIL)
				+ _stroke_path("M69,105 L63,114", INK_DETAIL)
			)
			return bandolier + loops
	var band := _path("M80,91 L92,97 L71,122 L59,116 Z", _accent_dark, _line(INK_DETAIL))
	return band + _circle(75.5, 106.5, 3, _gold, _line(INK_DETAIL))


## One rope of a lanyard: the ink line drawn under a lighter core, so a cord
## thin enough to read as rope still carries the sheet's outline.
func _cord(x1: float, y1: float, x2: float, y2: float) -> String:
	var d := "M%s,%s L%s,%s" % [x1, y1, x2, y2]
	return _stroke_path(d, INK_SILHOUETTE) + _stroke_path(d, 2.6, _accent_dark)


## The front props that stand on their own — smoked, worn or set down.
func _prop_worn(id: StringName) -> String:
	match id:
		&"pipe":
			return _pipe()
		&"cigar":
			return _cigar()
		&"medal":
			return _medal()
		&"drone":
			return _drone()
		&"falcon":
			return _falcon()
		&"helm":
			return _helm()
		&"scales":
			return _scales()
		&"whistle":
			return _whistle()
	return ""


## The front props a hand closes on, so each one draws that hand too.
func _prop_held(id: StringName, skin: String) -> String:
	match id:
		&"baton":
			return _baton(skin)
		&"card":
			return _card(skin)
		&"book":
			return _book(skin)
		&"dagger":
			return _dagger(skin)
		&"plane":
			return _plane(skin)
		&"radio":
			return _radio(skin)
		&"coins":
			return _coins(skin)
		&"compass":
			return _compass(skin)
		&"ledger":
			return _ledger(skin)
	return ""


func _hand(x: float, y: float, skin: String) -> String:
	return _circle(x, y, 5.5, skin, _line(INK_FEATURE))


## Rising smoke — the shared puff trail behind a pipe and a cigar. Each puff is
## (x, y, radius), growing as it climbs.
func _smoke(puffs: Array[Vector3], opacity: String) -> String:
	var drawn := ""
	for puff: Vector3 in puffs:
		drawn += _circle(puff.x, puff.y, puff.z, "#ffffff")
	return '<g opacity="%s">%s</g>' % [opacity, drawn]


func _pipe() -> String:
	var stem := _stroke_path("M61,72 Q72,75 74,83", 3.5, "#5a3c28")
	var bowl := _circle(74.5, 86, 4.2, "#5a3c28", _line(INK_FEATURE))
	var puffs: Array[Vector3] = [Vector3(82, 70, 3), Vector3(87, 59, 4), Vector3(92, 46, 5)]
	return stem + bowl + _smoke(puffs, "0.45")


func _cigar() -> String:
	var pen := _line(INK_FEATURE)
	var roll := _rect(60, 70.5, 14, 4.8, "#7a4a2b", pen + ' rx="2" transform="rotate(20 60 71)"')
	var ember := _circle(73.5, 76.8, 2, _ember)
	var puffs: Array[Vector3] = [Vector3(79, 66, 2.6), Vector3(84, 56, 3.4)]
	return roll + ember + _smoke(puffs, "0.4")


func _baton(skin: String) -> String:
	var pen := _line(INK_DETAIL)
	var stick := _path("M28,110 L84,92", "none", _tint("#5a3c28", 5))
	var caps := _circle(28, 110, 3, _gold, pen) + _circle(84, 92, 3, _gold, pen)
	return stick + caps + _hand(58, 101, skin)


func _medal() -> String:
	var pen := _line(INK_FEATURE)
	var boards := _rect(10, 92, 15, 6, _gold, pen) + _rect(85, 92, 15, 6, _gold, pen)
	var ribbon := _path("M35,96 L44,96 L42.5,105 L36.5,105 Z", _accent, pen)
	return boards + ribbon + _circle(39.5, 109, 4.5, _gold, pen)


func _card(skin: String) -> String:
	var face := _rect(75, 63, 15, 21, "#ffffff", _line(INK_FEATURE) + ' rx="2"')
	var pip := _path("M82.5,69 L86,73.5 L82.5,78 L79,73.5 Z", _accent)
	var held := '<g transform="rotate(-12 82 74)">%s%s</g>' % [face, pip]
	return held + _hand(80, 87, skin)


func _book(skin: String) -> String:
	var leaves := "M14,106 Q26,97 38,106 L38,119 Q26,110 14,119 Z"
	var pages := _path(leaves, "#ffffff", _line(INK_FEATURE))
	return pages + _stroke_path("M26,101.5 L26,113", INK_DETAIL) + _hand(37, 112, skin)


func _drone() -> String:
	var arc := _stroke_path("M74,25 Q80,21 86,25", INK_DETAIL, "#ffffff")
	var rotors := _rect(76, 27, 9, 2.5, _accent) + _rect(89, 27, 9, 2.5, _accent)
	var body := _rect(80, 29.5, 14, 8, _slate, _line(INK_FEATURE) + ' rx="2.5"')
	return '<g opacity="0.4">%s</g>' % arc + rotors + body + _circle(87, 33.5, 1.8, _led)


func _falcon() -> String:
	var breast := "M22,77 Q13,81 14,92 Q15,99 23,99 Q31,97 30,86 Z"
	var body := _path(breast, "#8c5a30", _line(INK_FEATURE))
	var wing := _stroke_path("M17,83 Q12,90 18,96", INK_DETAIL)
	var head := _circle(25, 73.5, 6, "#f2ead8", _line(INK_FEATURE))
	var beak := _path("M30.5,73 L35,75 L30.5,77.5 Z", _gold, _line(INK_DETAIL))
	return body + wing + head + beak + _circle(26, 72.5, 1.4, _ink)


func _dagger(skin: String) -> String:
	var blade := _path("M89,56 L93,80 L85,80 Z", "#cfd6dd", _line(INK_FEATURE))
	var grip := _rect(87.3, 80, 3.4, 7, _ink)
	return blade + grip + _hand(89, 86, skin) + _circle(89, 93.5, 3, "none", _line(INK_DETAIL))


func _radio(skin: String) -> String:
	var antenna := _stroke_path("M76,83 Q68,95 77,104 Q84,110 79,118", INK_DETAIL)
	var body := _rect(71, 65, 11, 18, _slate, _line(INK_FEATURE) + ' rx="3"')
	var grille := _path("M73.5,69 H79.5 M73.5,72 H79.5", "none", _tint("#ffffff", INK_DETAIL))
	return antenna + body + '<g opacity="0.7">%s</g>' % grille + _hand(77, 85, skin)


func _anchor() -> String:
	var steel := "#aab3bb"
	var shaft := _path("M84,98 L85,38 L91,38 L90,98 Z", steel, _line(INK_FEATURE))
	var stock := _rect(76, 48, 20, 5, steel, _line(INK_FEATURE) + ' rx="2"')
	var ring := _circle(87, 31, 6.5, "none", _line(INK_SILHOUETTE))
	var flukes := "M77,77 Q78,97 87,101 Q96,97 97,77 L92,79 Q91,92 87,94 Q83,92 82,79 Z"
	return shaft + stock + ring + _path(flukes, steel, _line(INK_FEATURE))


func _axe() -> String:
	var haft := _path("M86,100 L89,28 L95,29 L92,101 Z", "#8c5a30", _line(INK_FEATURE))
	var bit := "M83,30 Q94,25 96,42 Q94,58 83,54 L88,48 Q89,42 88,36 Z"
	return haft + _path(bit, "#cfd6dd", _line(INK_FEATURE))


func _hammer() -> String:
	var haft := _path("M81,32 L89,32 L87,102 L79,102 Z", "#8c5a30", _line(INK_FEATURE))
	var head := _rect(74, 22, 22, 16, "#8f9aa3", _line(INK_FEATURE))
	var cheek := _rect(90, 22, 6, 16, "#6d7880")
	return '<g transform="rotate(-10 85 30)">%s</g>' % (haft + head + cheek)


func _helm() -> String:
	var dome := _path("M20,120 Q18,98 34,96 Q50,98 48,120 Z", "#8f9aa3", _line(INK_FEATURE))
	var crest := _stroke_path("M20,100 Q34,92 48,100", 4.5, _accent)
	return dome + crest + _stroke_path("M34,97 L34,120", INK_DETAIL)


func _coins(skin: String) -> String:
	var pen := _line(INK_FEATURE)
	var tossed := _circle(89, 83, 5, _gold, pen) + _circle(98, 89, 5, _gold, pen)
	var held := _circle(91, 95, 5, _gold, pen)
	return _hand(82, 97, skin) + held + '<g opacity="0.85">%s</g>' % tossed


func _scales() -> String:
	var steel := "#aab3bb"
	var post := _rect(26, 94, 4, 26, steel, _line(INK_FEATURE))
	var beam := _rect(15, 92, 30, 3.5, steel, _line(INK_FEATURE))
	var cords := _stroke_path("M17,95 L17,104 M43,95 L43,104", INK_DETAIL)
	var pans := _path("M11,104 Q17,112 23,104 Z", _gold, _line(INK_DETAIL))
	pans += _path("M37,104 Q43,112 49,104 Z", _gold, _line(INK_DETAIL))
	return post + beam + cords + pans + _circle(28, 91, 2.6, _gold, _line(INK_DETAIL))


func _whistle() -> String:
	var mouthpiece := _path("M60,71 L70,69.5 L70,77 L60,75.5 Z", _gold, _line(INK_FEATURE))
	var body := _rect(69, 66.5, 13, 11, _gold, _line(INK_FEATURE) + ' rx="3.5"')
	var puffs: Array[Vector3] = [Vector3(88, 62, 3), Vector3(94, 52, 3.8)]
	return mouthpiece + body + _circle(76, 70, 1.8, _ink) + _smoke(puffs, "0.42")


## A model aircraft banked on an upheld palm: the same silhouette the sky held,
## brought down onto a hand so it has a contact point.
func _plane(skin: String) -> String:
	var fuselage := _path("M74,80 Q84,75 94,81 Q84,87 74,85 Z", "#e4e9ee", _line(INK_FEATURE))
	var wings := _path("M81,80 L87,70 L91,71 L89,82 Z", _accent, _line(INK_DETAIL))
	wings += _path("M81,83 L87,93 L91,92 L89,81 Z", _accent, _line(INK_DETAIL))
	var tail := _path("M75,79 L70,74 L72,84 Z", _accent, _line(INK_DETAIL))
	var flown := fuselage + wings + tail + _circle(89, 81, 2, _slate)
	return '<g transform="rotate(-16 84 81)">%s</g>' % flown + _hand(84, 94, skin)


func _compass(skin: String) -> String:
	var dial := _circle(28, 90, 12, "#e4e9ee", _line(INK_FEATURE))
	var rim := _circle(28, 90, 8, "none", _line(INK_DETAIL))
	var north := _path("M28,81 L31.5,90 L28,93 L24.5,90 Z", _accent, _line(INK_DETAIL))
	var south := _path("M28,99 L31.5,90 L24.5,90 Z", "#aab3bb", _line(INK_DETAIL))
	return dial + rim + north + south + _circle(28, 90, 1.6, _ink) + _hand(39, 99, skin)


func _ledger(skin: String) -> String:
	var block := _rect(13, 93, 26, 20, "#f2ead8", _line(INK_FEATURE) + ' rx="1.5"')
	var clasp := _rect(34, 98, 6, 7, "#aab3bb", _line(INK_DETAIL) + ' rx="1"')
	var rules := _path("M19,99 H31 M19,103 H31 M19,107 H27", "none", _tint(_ink, INK_DETAIL))
	return block + '<g opacity="0.55">%s</g>' % rules + clasp + _hand(38, 111, skin)
