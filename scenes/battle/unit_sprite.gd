class_name UnitSprite
extends Sprite2D
## Visual for one Unit. Position and tint always derive from the sim state
## via refresh(); the battle scene tweens `position` only for move previews.

const TILE := 16
## The units atlas is drawn at 4x the world grid so the generated art keeps
## its detail; the sprite is scaled back down to cover exactly one cell. Grid
## maths everywhere else still speaks in TILE. Must match sprite_generator's
## cell size (its atlas contract).
const SPRITE_W := 64
const SPRITE_H := 64
## The sprite is scaled by its *width*, so a cell taller than it is wide overflows
## upward at the same texel rate rather than shrinking the unit inside its tile.
const SPRITE_SCALE := float(TILE) / float(SPRITE_W)
## What a taller cell has over its footprint, in atlas pixels.
const SPRITE_OVERFLOW := SPRITE_H - SPRITE_W
## The art is anchored by its *footprint*, not by the cell's middle: with `centered`
## at its default, the bottom SPRITE_W square of the region lands exactly on the tile
## and the surplus rides up over the row above. This is a texture-space offset, so
## `position` stays the cell centre the sim derives — which is what leaves the HP,
## fuel and acted badges (children of this node) and every mark posed off
## `BattleView.cell_center` on the tile rather than floating up with a tall turret.
##
## Whole texels only, the rule the zoom ladder's A2/A4 keep everywhere else, so
## SPRITE_OVERFLOW must be even; test_texel_stability.gd pins it.
##
## Fog is deliberately left drawing above Units: overflow reaching into a fogged
## row is over ground the viewer cannot see, so having it clipped is correct.
const ART_OFFSET := Vector2(0, -float(SPRITE_OVERFLOW) / 2.0)
const UNITS_ATLAS_PATH := "res://assets/tiles/units_atlas.png"
## Ambient animation frame B: the same army one beat later — rotors swept,
## air and sea units riding a pixel higher while their shadows stay put.
## Land cells are byte-identical between the sheets, so only what should
## move ever moves.
const UNITS_ATLAS_B_PATH := "res://assets/tiles/units_atlas_b.png"
## The same army with the tile's cast shadow subtracted, for a surface that
## draws the art at 1:1 over ground and a shadow of its own — see
## `figure_texture_for`.
const UNITS_ATLAS_FIGURES_PATH := "res://assets/tiles/units_atlas_figures.png"
## Milliseconds per ambient beat, and one cadence for both motions because the
## sheets encode one: frame B is the whole army a beat later, so a rotor and a
## swell cannot be given different rates without a third sheet. Half a second is
## the slowest rate a swept rotor still reads as turning, which is the faster of
## the two motions and so the one that sets the beat.
const AMBIENT_MS := 500
## Captures pin the ambient clock at frame A the way they pin game speed
## and the hint strip: a frame must not depend on when the shutter fired.
## Belt as well as braces — a capture also pins Instant, which `ambient_frame`
## already answers with frame A — because an explicit `--speed=` still wins over
## the pinned tier and a capture of a tier must not become a capture of a beat.
static var ambient_frozen := false
## The acted grey-out is a screen-space dither scrim, not desaturate-and-dim:
## with the generated liveries a desaturated unit collapsed into the iron and
## neutral rows — three meanings, one appearance (sprite review round 3). The
## checkerboard darkens alternate screen pixels, so the faction hue survives
## on the pixels between; one shared material serves every sprite because the
## scrim has no per-unit state.
const _ACTED_SCRIM := """
shader_type canvas_item;
void fragment() {
	if (mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 2.0) < 0.5) {
		COLOR.rgb *= 0.62;
	}
}"""
static var _acted_material: ShaderMaterial
## A submerged boat is drawn faint for its own side. The enemy does not see it
## at all — that is Vision's answer, arriving here as `fogged`.
const DIVED_ALPHA := 0.5
## HpLabel's offset in unit_sprite.tscn, in world-grid units.
const HP_LABEL_OFFSET := Vector2(1, 0)
## FuelLabel sits opposite it, on the other side of the sprite.
const FUEL_LABEL_OFFSET := Vector2(-8, 0)
## The acted corner mark sits above the fuel badge, clear of both.
const ACTED_LABEL_OFFSET := Vector2(-8, -8)

var unit: Unit
## Team whose turn it is. Only that team's units grey out when exhausted;
## `acted` on the waiting team is stale until its own turn readies it.
var active_team: int = 0
## True when the viewing team may not see this unit. BattleView owns the answer
## — `Vision` decides it — and the sprite only remembers it. Held rather than
## re-derived so that every redraw honours it: a sprite that worked visibility
## out for itself would un-hide a fogged enemy on the next refresh.
var fogged: bool = false
## The side's resolved faction row this sprite draws in, not `unit.team`: the sim
## keeps team ints, but which paint a team wears is the SideIdentity resolver's
## call. The sprite still reads unit.team for everything else — acted grey-out,
## fog. Held and written by BattleView the same way `fogged` is, and setting it is
## what repaints the art: a unit can change army mid-match (a scripted defection),
## and a texture resolved once at setup would leave it in its old colours.
var atlas_row: int = -1:
	set(value):
		if atlas_row == value:
			return
		atlas_row = value
		texture = texture_for(unit.type, value, _frame)

## Which ambient frame this sprite currently shows. Instance state so a
## repaint (atlas_row, refresh) rebuilds the texture on the right sheet.
var _frame: int = 0

@onready var hp_label: Label = $HpLabel
@onready var fuel_label: Label = $FuelLabel
## The scrim's redundant corner mark: at zoom-out a one-pixel checker can
## read weakly, so an acted unit also wears a small "Z". Built in code as
## HpLabel's twin rather than authored in the scene, so the two can never
## drift in font or size.
var acted_label: Label


func setup(p_unit: Unit, p_active_team: int, p_atlas_row: int) -> void:
	unit = p_unit
	active_team = p_active_team
	# On the beat the rest of the board is on, before the first paint: a copter
	# built mid-beat would otherwise open on frame A and snap a frame later.
	set_process(animates(p_unit.type))
	_frame = ambient_frame() if is_processing() else 0
	atlas_row = p_atlas_row
	scale = Vector2.ONE * SPRITE_SCALE
	offset = ART_OFFSET
	# The badges are authored against the world grid, so undo the sprite's scale
	# rather than letting them shrink with the art. Their offsets are authored in
	# the same units and need the same treatment, or a badge creeps toward centre.
	hp_label.scale = Vector2.ONE / SPRITE_SCALE
	hp_label.position = HP_LABEL_OFFSET / SPRITE_SCALE
	fuel_label.scale = Vector2.ONE / SPRITE_SCALE
	fuel_label.position = FUEL_LABEL_OFFSET / SPRITE_SCALE
	# The one attention-amber: the low-fuel badge speaks UiTheme.AMMO rather than
	# a colour authored a shade off it in unit_sprite.tscn.
	fuel_label.add_theme_color_override("font_color", UiTheme.AMMO)
	acted_label = hp_label.duplicate()
	acted_label.text = "Z"
	acted_label.position = ACTED_LABEL_OFFSET / SPRITE_SCALE
	add_child(acted_label)
	refresh()


## Atlas region for one unit kind in a resolved faction's colours, at the atlas's
## own SPRITE_W x SPRITE_H resolution. `row` is a SideIdentity atlas row, not a
## team int — the two coincided before factions, when team N drew in row N, and
## this is the one line where that stopped being true. Static so menus can show
## the same artwork the board does without instancing a sprite; callers that draw it
## outside the world grid size it themselves.
static func texture_for(type: UnitType, row: int, frame: int = 0) -> AtlasTexture:
	return _region_of(load(UNITS_ATLAS_B_PATH if frame == 1 else UNITS_ATLAS_PATH), type, row)


## The same cell without the contact shadow the tile needs. The shadow is an
## opaque checkerboard, which reads as half-tone at the board's 4:1 decimation
## and as loose dots wherever the art is drawn at 1:1 — so the cut-ins, which
## blow a figure up over a ground plane and a contact shadow they draw
## themselves, ask for this one instead. The sheet is the board's own cell with
## those pixels subtracted (the generator's `compose_cell`), never a redraw,
## which is what keeps "board art, blown up" true of it.
static func figure_texture_for(type: UnitType, row: int) -> AtlasTexture:
	return _region_of(load(UNITS_ATLAS_FIGURES_PATH), type, row)


static func _region_of(sheet: Texture2D, type: UnitType, row: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(type.atlas_col * SPRITE_W, row * SPRITE_H, SPRITE_W, SPRITE_H)
	return atlas


## Which figures the two sheets differ in at all: air and sea, whose rotors are
## swept and whose hulls ride a pixel higher in frame B. Every land column is
## byte-identical between the sheets — measured, and pinned against the shipped
## art by tests/unit/test_ambient_frames.gd — so a land sprite is left out of the
## beat entirely rather than repainted with the picture it already shows.
static func animates(type: UnitType) -> bool:
	return type.domain != UnitType.LAND


## The shared ambient beat. Wall-clock, not accumulated time: every sprite
## on the board (and any future surface that animates) agrees on the frame
## without a conductor, and pacing stays presentation-only by construction.
##
## Instant is a still board by the same rule the tier states everywhere else —
## it shows a result rather than playing one out — so it answers frame A, the
## sheet every other surface draws from.
##
## The clock is a defaulted argument so that both stills — Instant and a pinned
## capture — are checkable rather than being read off whichever beat the suite
## happened to run in.
static func ambient_frame(now_ms: int = Time.get_ticks_msec()) -> int:
	if ambient_frozen or Settings.speed.instant:
		return 0
	return int(now_ms / AMBIENT_MS) % 2


func _process(_delta: float) -> void:
	var frame := ambient_frame()
	if frame == _frame:
		return
	_frame = frame
	var atlas := texture as AtlasTexture
	if atlas != null:
		atlas.atlas = load(UNITS_ATLAS_B_PATH if frame == 1 else UNITS_ATLAS_PATH)


func set_active_team(team: int) -> void:
	active_team = team
	refresh()


## Re-syncs position, visibility, the acted scrim, and HP badge from the sim
## state. Carried units are hidden until dropped, and so is anything the
## viewing team may not see — see `fogged`.
func refresh() -> void:
	position = Vector2(unit.cell * TILE) + Vector2(TILE, TILE) / 2.0
	visible = unit.carrier == null and not fogged
	var acted := unit.acted and unit.team == active_team
	material = acted_scrim() if acted else null
	acted_label.visible = acted
	var tint := Color.WHITE
	tint.a *= DIVED_ALPHA if unit.dived else 1.0
	modulate = tint
	hp_label.visible = unit.displayed_hp() < 10
	hp_label.text = str(unit.displayed_hp())
	fuel_label.visible = unit.running_dry()


## Shared by HudBottomBar's unit icon, so a unit that has acted looks the
## same in the bar as it does on the tile.
static func acted_scrim() -> ShaderMaterial:
	if _acted_material == null:
		var shader := Shader.new()
		shader.code = _ACTED_SCRIM
		_acted_material = ShaderMaterial.new()
		_acted_material.shader = shader
	return _acted_material


## Quick white flash when taking a hit. Awaitable.
##
## The durations arrive from BattleAnimator rather than being owned here: pacing
## is the animator's job and the player's setting, and this sprite derives
## nothing but sim state. A zero-length flash is skipped outright — that is the
## Instant tier asking for the result rather than the theatre.
func flash_hit(in_seconds: float, out_seconds: float) -> void:
	if in_seconds <= 0.0 or out_seconds <= 0.0:
		return
	var tween := create_tween()
	tween.tween_property(self, "self_modulate", Color(4.0, 4.0, 4.0), in_seconds)
	tween.tween_property(self, "self_modulate", Color.WHITE, out_seconds)
	await tween.finished


## Fade out and free. Awaitable; the caller must drop its reference first.
## `fade_seconds` is handed in for the same reason as `flash_hit`'s, and a zero
## fade frees on the spot.
func die(fade_seconds: float) -> void:
	if fade_seconds <= 0.0:
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_seconds)
	await tween.finished
	queue_free()
