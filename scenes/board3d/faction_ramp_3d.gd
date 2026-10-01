class_name FactionRamp3D
extends RefCounted
## An army's three tones on a 3D unit, derived from its `CommanderVisuals`
## theme, and the one rule that places them: a face a builder paints `base`
## wears `light` where it looks up, `dark` where it looks down and `base` on
## the flanks. The board camera looks down at 52°, so the up-facing panels are
## most of what it sees, and a light top is what lifts the Iron Dominion's
## near-black hull off its own running gear.
##
## A builder paints `light` itself only for trim and `dark` only for a recess;
## neither is ever a weapon's colour (that is `UnitPalette3D.STEEL`).

## How far toward straight up (or down) a face must look to take the light (or
## dark) tone: a sloped glacis still reads as a flank, a deck as a top.
const FACING := 0.6
## How much lighter the lit tone is than the army's base, in OKHSL lightness,
## its hue and saturation the base's own. The theme's light shade is a paler
## tint, and the board's sun lifts a top face further still, so a top painted
## in it read salmon and periwinkle where the sprites are red and blue.
const LIGHT_STEP := 0.08
## The brightest an army's lit tone may be, in relative luminance, under the
## board's sun. A lit tone past it washes toward white on a top face, so the
## whole ramp is lowered by one factor until its light tone sits on the
## ceiling. Only the Gilded Concord's yellow reaches it (0.87 against the other
## armies' 0.39–0.51), which deepens it from lemon toward the sprites' ochre.
const LIT_CEILING := 0.62

static var _ramps: Dictionary[StringName, FactionRamp3D] = {}

var base: Color
var light: Color
var dark: Color


func _init(theme: CommanderVisuals.FactionTheme) -> void:
	var hue := theme.color
	var lit := Color.from_ok_hsl(hue.ok_hsl_h, hue.ok_hsl_s, hue.ok_hsl_l + LIGHT_STEP)
	var lower := minf(1.0, LIT_CEILING / maxf(lit.get_luminance(), 0.001))
	base = _scaled(theme.color, lower)
	light = _scaled(lit, lower)
	dark = _scaled(theme.color_dark, lower)


static func of(theme: CommanderVisuals.FactionTheme) -> FactionRamp3D:
	if not _ramps.has(theme.key):
		_ramps[theme.key] = FactionRamp3D.new(theme)
	return _ramps[theme.key]


## The tone a `base` face takes, by which way it looks.
func tone_for(normal: Vector3) -> Color:
	if normal.y >= FACING:
		return light
	if normal.y <= -FACING:
		return dark
	return base


## Commits everything `st` holds to a mesh, every `base` face re-toned by
## `tone_for` and every other colour left as it was painted.
func commit(st: SurfaceTool) -> ArrayMesh:
	var arrays := st.commit_to_arrays()
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in colours.size():
		if colours[i] == base:
			colours[i] = tone_for(normals[i])
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _scaled(colour: Color, by: float) -> Color:
	return Color(colour.r * by, colour.g * by, colour.b * by, colour.a)
