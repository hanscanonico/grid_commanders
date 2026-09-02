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
const SPRITE_H := 96
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
## Where the ground line sits inside the cell, measured up from its bottom edge:
## the row the generator centres the tile's cast shadow on, and so the row a
## figure's tracks or feet rest on. The rows below it are that shadow's own
## spread, which is why a surface drawing the shadowless figure sheet over a
## contact ellipse of its own must put the ellipse here rather than on the box's
## bottom edge — the two cut-ins do, and an armour cell, whose shadow is the
## widest, floated furthest above it. test_figure_sheet.gd measures it off the
## shipped sheets, the subtraction between them being the shadow itself.
## The generator lights the board with one sun, which drops the shadow
## SHADOW_OFFSET (2px) below the feet row rather than centring it on them.
const CELL_GROUND_PX := 7
const UNITS_ATLAS_PATH := "res://assets/tiles/units_atlas.png"
## Ambient animation frame B: the same army one beat later — rotors swept,
## air and sea units riding a pixel higher while their shadows stay put, land
## cells on an idle key pose. Every column differs, so every sprite processes;
## tests/unit/test_ambient_frames.gd pins that against the shipped art.
const UNITS_ATLAS_B_PATH := "res://assets/tiles/units_atlas_b.png"
## The walk cycle: the same grid again, one gait pose per frame, played only
## while BattleAnimator is tweening a unit along its path. A unit the generator
## has authored no gait for carries its ambient cell in both move sheets, so
## nothing here ever asks which units are authored — the clip is valid for the
## whole roster from the day it ships. The art faces screen-left and a rightward
## step mirrors it: the generator draws this pair's land and air cells over a
## cell-centred cast shadow, so the mirror leaves the shadow where it was. The
## *ambient* pair's is not centred (34-36 px of 64, measured off the shipped
## sheets), so the mirror is the clip's and ends with it — see `moving`.
## tests/unit/test_move_frames.gd pins the grid, the pairing, the cadence, the two
## stills and the flip policy.
const UNITS_ATLAS_MOVE_PATH := "res://assets/tiles/units_atlas_move.png"
const UNITS_ATLAS_MOVE_B_PATH := "res://assets/tiles/units_atlas_move_b.png"
## The same army with the tile's cast shadow subtracted, for a surface that
## draws the art at 1:1 over ground and a shadow of its own — see
## `figure_texture_for`.
const UNITS_ATLAS_FIGURES_PATH := "res://assets/tiles/units_atlas_figures.png"
## The figures a beat later: the ambient pair's frame B with the same shadow
## subtracted, so the cut-ins idle on the beat the board does.
const UNITS_ATLAS_FIGURES_B_PATH := "res://assets/tiles/units_atlas_figures_b.png"
## One AUTHORED casualty frame per unit, shadowless like the figure pair — the
## board never draws it, so there is no board-sheet sibling, and it is a
## still: the dead don't loop. Air carries no frame here in v1; the generator
## fills its column with the unit's own rest key so the sheet stays a valid
## grid, and `CutsceneSide` never asks for it there (its own domain check is
## the fallback the manifest's `ko` clip names).
const UNITS_ATLAS_FIGURES_KO_PATH := "res://assets/tiles/units_atlas_figures_ko.png"
## The fire clip's pair: an authored muzzle-lit frame per ARMED unit,
## shadowless like the figure pair — the board never draws it, so there is
## no board-sheet sibling — for the combat cut-in's fire window
## (`CutsceneSide._figure_now`). A unit outside the generator's `FIRES` draws
## its own rest key in both slots (`units.pose._FALLBACK`, the fire clip's
## own fallback contract), and the second sheet is a real second key only
## for the sustained weapon families (`units.pose.FIRE_PAIRS`) — everything
## else armed carries the same cell in both, byte for byte.
const UNITS_ATLAS_FIGURES_FIRE_PATH := "res://assets/tiles/units_atlas_figures_fire.png"
const UNITS_ATLAS_FIGURES_FIRE_B_PATH := "res://assets/tiles/units_atlas_figures_fire_b.png"
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
## One step under HpLabel's 8: enough to read as a mark rather than a number,
## not so small the glyph loses its shape at the far zoom rungs.
const ACTED_LABEL_SIZE := 7

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
		texture = _region_of(load(_sheet_path(_frame)), unit.type, value)

## True while this sprite is walking a path. Set by BattleAnimator on both sides
## of its tween and by nothing else: it selects the clip the sprite draws, so a
## sprite left moving would stride on the spot for the rest of the match.
##
## Leaving the clip also faces the sprite forward again, here rather than at the
## animator's clear site so the clip and its mirror can never be let go of
## separately. The board's sun is the generator's: a unit parked mirrored over
## the ambient pair, whose shadow is not cell-centred, drops that shadow on the
## other side from an unmirrored neighbour of the same type, which reads as two
## suns on one board.
var moving: bool = false:
	set(value):
		if moving == value:
			return
		moving = value
		if not moving:
			flip_h = false
		_frame = BoardBeat.frame(_period_ms())
		_repoint_sheet()

## Which frame of the current clip this sprite shows. Instance state so a
## repaint (atlas_row, refresh) rebuilds the texture on the right sheet.
var _frame: int = 0

@onready var hp_label: Label = $HpLabel
@onready var fuel_label: Label = $FuelLabel
## The scrim's redundant corner mark: at zoom-out a one-pixel checker can
## read weakly, so an acted unit also wears a small "Z". Duplicated from HpLabel
## rather than authored in the scene — the font and the outline that make it
## legible zoomed out can then never drift — and restyled in `setup` where it
## must read as a status mark rather than a second number.
var acted_label: Label


func setup(p_unit: Unit, p_active_team: int, p_atlas_row: int) -> void:
	unit = p_unit
	active_team = p_active_team
	# On the beat the rest of the board is on, before the first paint: a copter
	# built mid-beat would otherwise open on frame A and snap a frame later.
	set_process(true)
	_frame = BoardBeat.frame(BoardBeat.AMBIENT_MS)
	flip_h = false
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
	# Muted grey, so a status mark and a stat are different categories at a glance,
	# and never amber — that is FuelLabel's attention colour. The outline the
	# duplicate carries stays: reading at the far zoom rungs is the badge's job.
	acted_label.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	acted_label.add_theme_font_size_override("font_size", ACTED_LABEL_SIZE)
	add_child(acted_label)
	refresh()


## Atlas region for one unit kind in a resolved faction's colours, at the atlas's
## own SPRITE_W x SPRITE_H resolution. `row` is a SideIdentity atlas row, not a
## team int — the two coincided before factions, when team N drew in row N, and
## this is the one line where that stopped being true. Static so menus can show
## the same artwork the board does without instancing a sprite; callers that draw it
## outside the world grid size it themselves. Always the resting frame: a slot
## outside the board shows the army parked, and `_sheet_path` stays the one place
## a clip and a frame pick a sheet.
static func texture_for(type: UnitType, row: int) -> AtlasTexture:
	return _region_of(load(UNITS_ATLAS_PATH), type, row)


## The same art cut down to its footprint square — the tile the unit stands on,
## without the headroom a raised silhouette overflows into. For a square slot that
## *is* a tile: the HUD's unit icon and an illustrated menu row. Fitting the whole
## cell into one of those instead shrinks every unit to two thirds of the slot to
## make room for sky, which costs a 20 px icon far more than a raised turret's top
## few pixels are worth.
static func tile_texture_for(type: UnitType, row: int) -> AtlasTexture:
	var art := texture_for(type, row)
	art.region = Rect2(
		art.region.position + Vector2(0, SPRITE_OVERFLOW), Vector2(SPRITE_W, SPRITE_W)
	)
	return art


## The same cell without the contact shadow the tile needs. The shadow is an
## opaque checkerboard, which reads as half-tone at the board's 4:1 decimation
## and as loose dots wherever the art is drawn at 1:1 — so the cut-ins, which
## blow a figure up over a ground plane and a contact shadow they draw
## themselves, ask for this one instead. The sheet is the board's own cell with
## those pixels subtracted (the generator's `compose_cell`), never a redraw,
## which is what keeps "board art, blown up" true of it.
##
## `frame` is the idle clip's, the ambient beat's two poses with the shadow gone
## from both. It defaults to the resting frame, so a caller that wants a still
## asks for nothing; a cut-in passes the frame its own director's clock is on.
static func figure_texture_for(type: UnitType, row: int, frame: int = 0) -> AtlasTexture:
	var path := UNITS_ATLAS_FIGURES_B_PATH if frame == 1 else UNITS_ATLAS_FIGURES_PATH
	return _region_of(load(path), type, row)


## A unit's authored KO frame — the same shape as `figure_texture_for`, one
## sheet and no frame argument, since the clip holds a single pose. Every
## column of the sheet resolves (the generator's own fallback keeps an
## unauthored unit's rest key there), so this never fails to return a
## texture; whether a caller may SHOW it is the caller's own question — see
## `CutsceneSide.bind`, which asks it only for a unit that is not flying.
static func ko_figure_texture_for(type: UnitType, row: int) -> AtlasTexture:
	return _region_of(load(UNITS_ATLAS_FIGURES_KO_PATH), type, row)


## A unit's authored fire frame — the same shape as `figure_texture_for`, one
## sheet per pair key. `frame` defaults to the pair's first sheet, the way
## `figure_texture_for`'s does; a caller reading the second sustained key
## passes 1. Every column resolves (the generator's own fallback keeps an
## unarmed unit's rest key there), so this never fails to return a texture —
## whether the cut-in's fire window is open is `CutsceneSide`'s own question.
static func fire_figure_texture_for(type: UnitType, row: int, frame: int = 0) -> AtlasTexture:
	var path := UNITS_ATLAS_FIGURES_FIRE_B_PATH if frame == 1 else UNITS_ATLAS_FIGURES_FIRE_PATH
	return _region_of(load(path), type, row)


static func _region_of(sheet: Texture2D, type: UnitType, row: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(type.atlas_col * SPRITE_W, row * SPRITE_H, SPRITE_W, SPRITE_H)
	return atlas


func _process(_delta: float) -> void:
	var frame := BoardBeat.frame(_period_ms())
	if frame == _frame:
		return
	_frame = frame
	_repoint_sheet()


## Which screen direction a sprite faces after a leg of `delta`, given the facing
## it already had. The sheets are drawn facing screen-left, so a step with a
## positive x mirrors and a negative one does not; a purely vertical leg holds
## what the last horizontal one left. Static and pure so the policy is checkable
## without a sprite, the way PathArrow.segments() is.
static func facing_for(delta: Vector2i, was: bool) -> bool:
	if delta.x == 0:
		return was
	return delta.x > 0


## Turns this sprite for one leg of a walk. Called at the corner rather than once
## for the whole path, and never from refresh(): a repaint mid-walk — a fog flip,
## a defection's atlas_row — must not turn a striding unit around. The facing
## lasts exactly as long as the clip does; `moving` lets go of both together.
func face_step(delta: Vector2i) -> void:
	flip_h = facing_for(delta, flip_h)


## The one answer to which sheet this sprite draws from, so that a repaint
## mid-walk — a defection's atlas_row, a fog flip — cannot snap a striding unit
## back to its parked pose.
func _sheet_path(frame: int) -> String:
	if moving:
		return UNITS_ATLAS_MOVE_B_PATH if frame == 1 else UNITS_ATLAS_MOVE_PATH
	return UNITS_ATLAS_B_PATH if frame == 1 else UNITS_ATLAS_PATH


func _period_ms() -> int:
	return BoardBeat.move_ms() if moving else BoardBeat.AMBIENT_MS


func _repoint_sheet() -> void:
	var atlas := texture as AtlasTexture
	if atlas != null:
		atlas.atlas = load(_sheet_path(_frame))


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
