class_name CutsceneSide
extends Control
## One half of the battle cut-in: a unit posed over a strip of its own terrain,
## with a name/HP plate above it and a terrain/defence plate below.
##
## Draws, and does nothing else. Every value it renders is written onto it by
## CombatCutscene, which owns the clock: the side never reads the simulation,
## never advances time, and never decides an outcome. `mirror` is the only
## difference between the attacker's half and the defender's.
##
## The ground is the board's own terrain art, tiled in receding bands, and the
## figure is the board's own unit art — blown up, never redrawn (plan D2), minus
## the contact shadow the tile needed and this half draws for itself
## (UnitSprite.figure_texture_for). The scenery a standing terrain puts on that
## ground is the one exception, and says so where it is declared
## (TerrainType.cutin_scenery). The other thing derived rather than drawn is the
## horizon ridge's colour, which is averaged off the terrain tile so a new
## terrain needs no entry anywhere.

## Share of the arena the ground plane fills, measured up from the bottom.
const GROUND_RATIO := 0.45
## How many steps the sky is graded in over what is left above it.
const SKY_BANDS := 32
## The same plane as a top edge and a depth, both measured *down* the arena —
## the frame the scenery's depth shading is written in.
const _GROUND_TOP := 1.0 - GROUND_RATIO
const _GROUND_DEPTH := GROUND_RATIO
## Where a standing terrain's art is stood on that plane: how far in from the
## outer edge, how far down the arena its base rests, and its size *relative to
## its own kind* — a ridge and a pine are not the same object at two scales, so
## the absolute height is the shape's (below) and only the variation is here.
## Four of them at different depths, so a city reads as a place with buildings in
## it rather than as a row of identical cut-outs. Every base sits above the
## squad's own line (FEET_RATIO), which is what keeps a city's towers behind the
## tanks fighting over it instead of in front of them.
const SCENERY_SLOTS: Array[Vector3] = [
	Vector3(0.05, 0.72, 0.86),
	Vector3(0.27, 0.63, 0.70),
	Vector3(0.63, 0.66, 0.92),
	Vector3(0.85, 0.74, 1.0),
]
## How far in from the outer edge the squad's *middle* sits. Squads are centred
## on this whatever their size, so a lone 1 HP straggler holds the same ground a
## full five did rather than standing off at the edge of the frame where the
## outermost of five would have been.
const SQUAD_CENTER := 132.0
## Where the figures' feet sit, as a share of the arena height.
const FEET_RATIO := 0.86
## Advance Wars' rule: one figure per two displayed HP, so a full squad is five
## and a battered 1 HP straggler fights alone (plan D3). Figures carry the feel;
## the pip bar above them carries the exact number.
const MAX_FIGURES := 5
## Where each figure stands, offset from the outermost one. Staggered rather than
## in a line so five 64 px sprites read as a cluster instead of a row, and drawn
## back to front so the outermost is the one in front.
const SLOTS: Array[Vector2] = [
	Vector2(0.0, 6.0),
	Vector2(44.0, -12.0),
	Vector2(86.0, 9.0),
	Vector2(128.0, -8.0),
	Vector2(168.0, 13.0),
]
## How far apart, in fall progress, consecutive figures start toppling.
const TOPPLE_STAGGER := 0.13
## Where in a figure's OWN fall — not the beat, not the clock, the `fall`
## progress `_draw_squad` already threads through `_draw_figure` — the
## standing idle art gives way to the authored KO frame. Chosen off the same
## curve the fall already answers to: by 0.5 the knock-back is spent and
## `lift`'s own ramp has carried the figure back down through roughly zero
## (peaking at -13px at 0.3, landing at +46px by 1.0), so the figure is
## about back at the ground it is about to lie on — the moment a standing
## sprite tipping over stops being the honest reading and a body already
## down is. `spin` and `lift` keep running past it unmoved: only which
## texture is drawn changes here, never a beat's own timing.
const TOPPLE_KO_AT := 0.5
## The knock-back a figure takes before it tips: how far outward it is thrown and
## how long that jerk lasts. The length is in **seconds of the casualty beat**,
## asked of the window CombatBeats sized rather than counted in frames, so a
## two-figure loss — whose window is longer — gives each figure the same jerk
## rather than a proportionally slower one.
const KNOCK_PX := 4.0
const KNOCK_SECONDS := 0.08
## The shove a standing figure takes as its half is hit, decaying with the flash.
const BRACE_PX := 2.0
## Where a figure's barrel mouth sits above and inward of its feet. `MUZZLE_UP`
## is also the height the wind-up's shear is evaluated at, so the flash tracks
## the row `_draw_tipped` really displaced rather than a second guess at it.
const MUZZLE_IN := 22.0
const MUZZLE_UP := 34.0
## The roll-in: how far outward of its firing slot a squad starts, how far past
## the slot it dips as it halts, and the share of the run that settle happens
## over. The dip is what makes the halt read as weight rather than as a stop.
const ARRIVE_PX := 26.0
const SETTLE_PX := 2.0
const SETTLE_BAND := 0.15
## A marching rank sets off in order rather than as a block — five men translated
## together read as one cut-out on a conveyor — and each figure bobs as it comes.
const MARCH_STAGGER := 0.10
const TRUDGE_PX := 1.5
const TRUDGE_STEPS := 2.0
## Below this much scuff a land half is on foot: it staggers and trudges in where
## a hull rolls in as one piece. Read off the scuff a style kicks rather than off
## a style id, which would be the same "checked in three places" smell the
## movement domains are data to avoid.
const FOOT_DUST := 0.2
## How far an aircraft drops into its slot over the arrive, and how far a hull
## rides the swell there. The aircraft's bank is a vertical offset and nothing
## else: these are the board's three-quarter-view cells, and rolling one reads as
## a rendering glitch — the same reason the topple's tip is capped (plan R3).
const BANK_PX := 6.0
const SWELL_PX := 3.0
## The wind-up: the share of it the lift and the tip ease over before holding,
## how far the figure drifts away from the seam as a share of that lift, and the
## tip a style is allowed. A pitch past this is a data error rather than a pose —
## a board sprite rotated further stops reading as a weapon being aimed.
const AIM_EASE := 0.6
const AIM_DRIFT := 0.4
const AIM_PITCH_MAX := 0.10
## The scuff kicked at the ground line: how many puffs, how wide the first is,
## how far apart they step outward, and how flat they lie on the plane. The floor
## is CutsceneFx.MIN_FLARE_REACH's discipline — a polygon ramped from zero lands
## its points on one float and the triangulator refuses it.
const SCUFF_PUFFS := 3
const SCUFF_REACH := 8.0
const SCUFF_STEP := 12.0
const SCUFF_FLAT := 0.34
const SCUFF_MIN_REACH := 0.5
## How high aircraft ride above their own ground, and the bob they hold there.
## The phase step keeps a flight of four from pulsing in unison.
const HOVER_HEIGHT := 34.0
const HOVER_SWING := 4.0
const HOVER_RATE := 4.4
const HOVER_PHASE := 1.1

# --- this half's own colours (the shared ones are CutscenePalette's) ----------
## The unlit pip. The banded fill beside it is UiTheme.hp_color's, never a copy —
## see _draw_pips.
const HP_EMPTY := Color(1.0, 1.0, 1.0, 0.12)
## What a knocked-out figure burns down to on its way off the field: a multiply
## over its own art, so a wreck is dead by value and never by hue — a darkened
## faction tone reads as a healthy rear rank in shadow. Its luma is that
## burn-down's floor, and the floor is measured: two ramp steps (0.1543 each,
## docs/sprite_legibility.md) above the figure sheet's own S0 ink at 0.086. Under
## it the interior stops reading as a shape inside the outline and the figure
## reads as a hole, which 0.205 — what this was, 0.77 of a step — did.
##
## Every toppling figure falls on this, `[0, 0.35, 1.0]` onto `[0, 0.85, 1.0]`;
## it is retired past `TOPPLE_KO_AT` for the one that has an authored frame to
## swap to, where `KO_SETTLE_TINT` picks the burn up.
const WRECK_TINT := Color(0.4, 0.4, 0.4)
## What the authored KO frame wears at the swap, easing to 1.0 over the whole
## rest of the fall — `[TOPPLE_KO_AT, 1.0]`, and the width is the point. A
## figure's fall runs about 0.30 s at the default tier (a one-figure loss sizes
## the casualty window at 0.38 s, of which `_knock_share` spends 0.08 before the
## fall starts), so half of it is ~150 ms and ~9 frames at 60 Hz. Easing over
## the 0.05 up to the alpha fade's own start instead would be 15 ms — under one
## frame — which does not smooth a value step, it just moves it a frame later.
## The fade opens at 0.55 and takes the tail of this.
##
## Measured on the shipped sheets, so the value is continuous where the texture
## changes: the burn above leaves the idle art at 0.469 of its own value by
## `TOPPLE_KO_AT`, and a KO cell's own band is 1.250x that same live cell's —
## 115.4L dead against 93.3L alive, the 1.250 being the mean of the 84 per-cell
## ratios (14 units x 6 factions). It lands ABOVE the body it was because
## `wreck_tone` floors a wreck two ramp steps over the sheet's S0 ink and drops
## its rim, so a wreck reads flatter and rim-less rather than dimmer. 0.469 /
## 1.250 is what the replacement has to wear to arrive on the value the idle art
## left. Re-take both readings off the installed PNGs if the burn is ever
## re-authored — this pair moved when it last was. Nothing here may exceed 1.0:
## the 2D framebuffer is RGBA8 under `gl_compatibility`, where a modulate over 1
## clips the lit planes flat rather than brightening them.
const KO_SETTLE_TINT := Color(0.375, 0.375, 0.375)
## The wash the vignette darkens the arena's edges with, a step per band.
const VIGNETTE := Color(0.05, 0.06, 0.10)

const PIP_COUNT := 10
const PIP_SIZE := Vector2(6, 8)
const PIP_GAP := 1.0
## The weapon chip beside the unit's name: its type size, the padding inside its
## border, and how far it sits off the name. Small and bordered rather than loud —
## it answers "which of its two guns is this" without competing with the name.
const CHIP_FONT_PX := 7
const CHIP_PAD := Vector2(4.0, 3.0)
const CHIP_GAP := 8.0
const CHIP_BORDER := Color(1.0, 1.0, 1.0, 0.25)
const CHIP_TEXT := Color(1.0, 1.0, 1.0, 0.68)
## How far plate content is held off the frame's outer edge. Generous on purpose:
## the band pushes in slightly over the exchange, so a few pixels either side are
## outside the viewport at the moment the volley lands.
const PLATE_MARGIN := 26.0
## The space left between the terrain's name and its first defence star.
const TERRAIN_STAR_GAP := 12.0
## The matching hold-off from the seam, for the content that sits against it.
const SEAM_MARGIN := 18.0

var unit: Unit
var terrain: TerrainType
## The terrain whose art paves the floor. The cell's own for an open surface, and
## the surface named by `TerrainType.cutin_ground` for a terrain that stands on
## one instead — resolved by the director, because the side is handed what it
## draws and looks nothing up.
var ground: TerrainType
## The atlas row the cell's owner draws its property art in — already resolved
## through SideIdentity by the director, never a team int. Neutral (and unowned)
## is row 0, which is what an untinted tile wants anyway.
var owner_row := 0
## This side's faction accent, the tint on its name-plate bar. Resolved by the
## director off SideIdentity and written here — the side never re-derives a team
## colour, in keeping with "draws, and does nothing else" above.
var accent := Color.WHITE
## True for the defender's half: art, plates and squad all face the other way.
var mirror := false
## What this side is shooting with, for the chip beside its name — the label off the
## BattleStyle the rules already selected, written here by the director. Empty draws
## no chip, which is what an unarmed unit and a defender that never answers both
## want: a chip on a silent side would announce a weapon the frame never shows.
var weapon_label := ""

# --- pose, written every frame by CombatCutscene ------------------------------

## Displayed HP the pips currently show. Ticks from the result's snapshot to the
## unit's real HP across the impact beat.
var hp_shown := 10
## How many figures this side ends the exchange with, and how many it started
## with. Both are whole counts written by the director rather than derived from
## the ticking `hp_shown`, so surplus figures topple once, together, from the
## start of their fall — deriving them mid-tick pops a figure into a topple that
## is already half over.
var squad_now := MAX_FIGURES
var squad_was := MAX_FIGURES
## 0 -> 1 as the squad rolls the last stretch into its firing slot. 1.0 is
## posted, and a posted half must draw exactly the frame it drew before there was
## an arrive beat at all.
var arrive_p := 1.0
## 0 -> 1 over the wind-up before this side fires. Its *length* is the weapon's,
## which is most of what tells a howitzer from a rifle before a single pixel of
## projectile exists (CombatBeats).
var aim_p := 0.0
## 0 -> 1 over the fire window CombatBeats.fire_window composes (the recoil
## ramp through the volley's own travel) — open exactly while this half's
## muzzle should read as lit, zero for a side that never fires. Only
## `_figure_now` reads it; the procedural aim lift/pitch above still carries
## the wind-up regardless.
var fire_p := 0.0
## 0 -> 1 over the casualty beat, which the sheet sizes off how many figures this
## side lost: the surplus figures are knocked back, then rise, spin and fall away.
var casualty_p := 0.0
## How many figures `casualty_p`'s own window was sized for — CombatBeats' own
## count, written here rather than re-derived from `squad_was`/`squad_now`,
## which carry the "kept whole for the blast" rule for a dying side and would
## silently drift from the window's real tail the moment the two rules parted
## ways (see CombatBeats.def_lost).
var casualty_lost := 0
## The style's own look numbers, copied on by the director rather than looked up:
## how much scuff this half kicks, how far its weapon lifts (+) or settles (-)
## and tips (nose-toward-the-seam positive) over the wind-up, and how far out it
## starts its roll-in.
var dust := 0.0
var aim_lift := 0.0
var aim_pitch := 0.0
var arrive_scale := 1.0
## Recoil offset along the firing axis: negative pulls back, positive thrusts.
var lunge := 0.0
## 0 -> 1 white over-brighten on taking a hit.
var flash := 0.0
## Fades whatever is left standing — what the death explosion takes with it.
var squad_alpha := 1.0
## 0 -> 1 as the plates slide in and their text appears.
var plate_p := 0.0
## The cut-in's clock, in seconds, for the two things here that run on time
## rather than on a beat of the director's: an aircraft's hover bob, and the
## squad's idle pose. Written by the director like everything else, so a posed
## still is still a pure function of `_t`.
var clock := 0.0

## The idle clip's frame A then frame B, both cut at bind, and the KO frame
## third — null for a flying unit, which carries none in v1. Which idle frame
## is drawn is the *director's* clock's answer (`_figure_now`), never the
## board's wall beat: the board's would make a posed still depend on when the
## shutter fired. The KO slot is asked directly, off `fall` alone
## (`_draw_figure`), since a wreck holds no pose of its own to pick between.
var _figures: Array[AtlasTexture] = []
## The fire clip's own pair, cut at bind like `_figures`. Bound for every
## unit, armed or not: the generator's own fallback (`units.pose._FALLBACK`)
## already fills an unarmed column with its idle key, so this needs no
## domain gate the way the KO slot's flying carve-out does — an unarmed
## side's `fire_p` window simply never opens (CombatBeats never sizes a
## recoil ramp for a style that does not fire).
var _fire_figures: Array[AtlasTexture] = []
var _ridge_tint := Color.SLATE_GRAY
## Cached off the unit's domain at bind time — asked once per cut-in rather than
## once per figure per frame.
var _flying := false
var _floating := false


func _ready() -> void:
	clip_contents = true  # the ground tiles and a toppling figure both overrun
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Poses this half for one exchange. Called once per cut-in, before the clock
## starts; everything after that is the pose fields above.
##
## Both rows arrive resolved: `p_unit_row` is the faction row this side's army
## draws in and `p_owner_row` the one the ground's owner does, both the director's
## SideIdentity answers. A team int here would be a second opinion on who wears
## what, and for the two sides whose row differs from their slot number it was a
## wrong one — the whole of COM-10.
func bind(
	p_unit: Unit,
	p_unit_row: int,
	p_terrain: TerrainType,
	p_ground: TerrainType,
	p_owner_row: int,
	p_mirror: bool,
	p_accent: Color
) -> void:
	unit = p_unit
	terrain = p_terrain
	ground = p_ground
	owner_row = p_owner_row
	accent = p_accent
	mirror = p_mirror
	_flying = p_unit.type.domain == UnitType.AIR
	_floating = p_unit.type.domain == UnitType.SEA
	_figures = [
		UnitSprite.figure_texture_for(p_unit.type, p_unit_row, 0),
		UnitSprite.figure_texture_for(p_unit.type, p_unit_row, 1),
	]
	_fire_figures = [
		UnitSprite.fire_figure_texture_for(p_unit.type, p_unit_row, 0),
		UnitSprite.fire_figure_texture_for(p_unit.type, p_unit_row, 1),
	]
	# Air ships no authored frame in v1 (plan's own fallback contract): this
	# slot stays null for it, which is what keeps `_draw_figure` on the
	# transform-topple there instead of asking `_flying` a second time.
	var ko_art: AtlasTexture = null
	if not _flying:
		ko_art = UnitSprite.ko_figure_texture_for(p_unit.type, p_unit_row)
	_figures.append(ko_art)
	_ridge_tint = CutsceneScenery.ground_tint(ground.atlas_col, _ground_row())


## The atlas row this side's figures are really drawn from, read back off the
## region `bind` baked, and the row its ground strip is drawn from. Both are
## reads for the scenario driver's row check, which asks what is on screen rather
## than what was remembered — the side stays draw-only.
func drawn_unit_row() -> int:
	if _figures.is_empty():
		return -1
	return int(_figures[0].region.position.y) / UnitSprite.SPRITE_H


## The row the *cell's own* art is drawn in — the paved floor for a surface, the
## standing scenery for a property. Both come off `_atlas_row`, so the driver's
## faction check reads the same answer whichever of the two the terrain is.
func drawn_ground_row() -> int:
	if terrain == null:
		return -1
	return _atlas_row()


## Advance Wars' squad rule: one figure per two displayed HP, capped at five.
## Zero only ever means dead.
static func figures_for(displayed_hp: int) -> int:
	return clampi(ceili(displayed_hp / 2.0), 0, MAX_FIGURES)


## Every standing figure's barrel, in this control's coordinates, innermost last
## — the muzzle flashes go on all of them and the volley leaves from the last,
## which is the figure nearest the enemy. Derived from the same layout numbers
## the squad is drawn with rather than hand-tuned twice: `_pose_offset` is the
## whole of a standing figure's pose (roll-in, wind-up, recoil, brace), and the
## wind-up's shear is composed at the mouth's own height exactly as
## `_draw_tipped` displaces that row, so the flash rides the barrel where it is
## drawn — which reads oddest without it on a weapon whose barrel visibly
## elevates, like the howitzer's.
func muzzle_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	var arena := _arena()
	var on_foot := _on_foot()
	var lean := sin(aim_tilt(aim_p, aim_pitch))
	for slot in squad_now:
		var reach := _inward(MUZZLE_IN + lean * MUZZLE_UP)
		var barrel := _figure_point(arena, slot) + Vector2(reach, -MUZZLE_UP)
		var roll := arrive_offset(arrive_p, arrive_scale, unit.type.domain, slot, clock, on_foot)
		points.append(barrel + _pose_offset(roll, slot, 0.0, true))
	return points


## Where one figure of the squad stands, in this control's coordinates.
##
## The formation is laid out from its own middle rather than from its outermost
## figure: the posted squad's span is measured off `squad_was` and halved, so
## every size stays centred on SQUAD_CENTER.
func _figure_point(arena: Rect2, slot: int) -> Vector2:
	var offset: Vector2 = SLOTS[clampi(slot, 0, SLOTS.size() - 1)]
	var span: float = SLOTS[clampi(squad_was - 1, 0, SLOTS.size() - 1)].x
	return Vector2(
		_outward_px(SQUAD_CENTER - span * 0.5 + offset.x),
		arena.position.y + arena.size.y * FEET_RATIO + offset.y
	)


## Where this side's callout sits, where an incoming round is aimed, and where
## the kill blast goes off: the middle of the squad, at body height rather than
## down at its feet. Fixed for the whole cut-in, so nothing anchored here drifts
## sideways as figures fall out from under it.
## Deliberately without the hover bob: a shot aimed at a bobbing point, or a
## damage number pinned to one, would judder for the whole beat.
func center_point() -> Vector2:
	var arena := _arena()
	var cruise := HOVER_HEIGHT if _flying else 0.0
	return Vector2(
		_outward_px(SQUAD_CENTER), arena.position.y + arena.size.y * FEET_RATIO - 28.0 - cruise
	)


func _arena() -> Rect2:
	return CutscenePlates.arena(size)


func _draw() -> void:
	if unit == null:
		return
	var arena := _arena()
	_draw_sky(arena)
	_draw_ground(arena)
	_draw_scenery(arena)
	_draw_squad(arena)
	_draw_vignette(arena)
	_draw_plates()


# --- backdrop ----------------------------------------------------------------


## Graded sky, two blocky clouds, and a ridge of the same ground sitting on the
## horizon. All of it above the ground line.
func _draw_sky(arena: Rect2) -> void:
	var horizon := _horizon(arena)
	CutsceneScenery.draw_sky_gradient(self, arena, size.x, horizon, SKY_BANDS)
	CutsceneScenery.draw_cloud(
		self, Vector2(_outward(0.30), arena.position.y + arena.size.y * 0.17), 1.0
	)
	CutsceneScenery.draw_cloud(
		self, Vector2(_outward(0.74), arena.position.y + arena.size.y * 0.07), 0.62
	)
	# Distant country, not scenery: the ridge is the ground's own colour washed
	# most of the way toward the sky, so it sits behind the horizon instead of
	# competing with the field the fight is on.
	var far := _ridge_tint.darkened(0.25).lerp(CutscenePalette.SKY_HORIZON, 0.55)
	_draw_hill(horizon, _outward(0.34), 260.0, 26.0, Color(far, 0.85))
	_draw_hill(horizon, _outward(0.90), 190.0, 19.0, Color(far, 0.85))
	var near := _ridge_tint.darkened(0.3).lerp(CutscenePalette.SKY_HORIZON, 0.3)
	_draw_hill(horizon, _outward(0.04), 150.0, 13.0, Color(near, 0.9))
	_draw_hill(horizon, _outward(0.66), 200.0, 16.0, Color(near, 0.9))


## The ground plane: the cell's own atlas tile, in rows that keep their width and
## grow taller as they come forward. That vertical squash is the whole trick —
## the same square tile foreshortened near the horizon and full height at the
## camera reads as a plane receding away, and the art is exactly what the board
## draws on that square (plan D2).
func _draw_ground(arena: Rect2) -> void:
	var horizon := _horizon(arena)
	var floor_y := arena.position.y + arena.size.y
	var depth := floor_y - horizon
	var atlas := CutscenePlates.terrain_atlas()
	var source := BattleView.terrain_cell_region(ground.atlas_col, _ground_row())
	var y := horizon
	var row_h := depth * 0.05
	while y < floor_y:
		# Rows also lighten as they approach: distance drains contrast, which is
		# what keeps the far ground from reading as a wall behind the near one.
		var lit := lerpf(0.76, 1.0, clampf((y - horizon) / depth, 0.0, 1.0))
		_tile_row(atlas, source, y, row_h, Color(lit, lit, lit))
		y += row_h
		row_h *= 1.6
	# A lit lip over a dark band is what makes the horizon read as an edge
	# rather than as the seam between two textures.
	draw_rect(Rect2(0.0, horizon, size.x, 2.0), Color(_ridge_tint.darkened(0.55), 0.9))
	draw_rect(Rect2(0.0, horizon - 1.0, size.x, 1.0), Color(1.0, 1.0, 1.0, 0.35))
	draw_rect(Rect2(0.0, floor_y - 18.0, size.x, 18.0), Color(0.0, 0.0, 0.0, 0.16))


## One row of terrain tiles across the full width: full tile width, squashed to
## `row_h` tall.
func _tile_row(atlas: Texture2D, source: Rect2, top: float, row_h: float, shade: Color) -> void:
	var tile := float(BattleView.TERRAIN_PX)
	var x := -tile * 0.5
	while x < size.x:
		draw_texture_rect_region(atlas, Rect2(x, top, tile, row_h + 1.0), source, shade)
		x += tile


func _horizon(arena: Rect2) -> float:
	return CutsceneScenery.horizon_of(arena, GROUND_RATIO)


func _draw_hill(base_y: float, center_x: float, width: float, height: float, tint: Color) -> void:
	var points := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var t := float(i) / steps
		points.append(Vector2(center_x - width * 0.5 + width * t, base_y - sin(t * PI) * height))
	# The arc already ends on both base corners and the polygon closes itself, so
	# appending them again would duplicate vertices and fail triangulation.
	draw_colored_polygon(points, tint)


## A terrain whose art is an object rather than a texture, stood on the paved
## floor: four silhouettes at four depths along the strip, drawn rather than
## blitted and coloured from the board's own cell. The shapes and that colour are
## CutsceneScenery's, shared with the capture cut-in, and it carries why they are
## drawn at all. Nothing is drawn for a terrain that paves: there the floor
## already *is* that terrain, which is the whole of the distinction.
func _draw_scenery(arena: Rect2) -> void:
	if terrain == null or terrain.cutin_scenery == TerrainType.NO_SCENERY:
		return
	# The colour is the cell's own, averaged off the atlas at the row its owner
	# paints it in — so a base standing here is the same slate or green the board
	# shows, and a neutral one the same grey, without a table of scenery colours
	# anywhere. Each shape darkens it to taste; the average of a whole cell is
	# already muted, and darkening it again here turned a pine into a black blob.
	var tint := CutsceneScenery.object_tint(terrain.atlas_col, _atlas_row())
	var kind := terrain.cutin_scenery
	var full := CutsceneScenery.height_of(kind)
	for slot in SCENERY_SLOTS:
		var base := Vector2(_outward(slot.x), arena.position.y + arena.size.y * slot.y)
		var height := full * slot.z
		# Distance drains contrast here exactly as it does on the ground rows, so
		# the one furthest back sits behind the field rather than on top of it.
		var lit := lerpf(0.86, 1.0, clampf((slot.y - _GROUND_TOP) / _GROUND_DEPTH, 0.0, 1.0))
		var shade := Color(tint.r * lit, tint.g * lit, tint.b * lit, 1.0)
		CutsceneScenery.draw_contact_shadow(self, base, height * 0.3, 0.22)
		CutsceneScenery.draw_shape(self, kind, base, height, shade, lit)


## Cinematic framing: the arena darkens toward its edges so the eye lands on the
## squad rather than on the seam between the halves.
func _draw_vignette(arena: Rect2) -> void:
	var steps := 10
	for i in steps:
		var wash := Color(VIGNETTE, 0.030 * (steps - i) / float(steps))
		var band := 4.0
		var offset := i * band
		draw_rect(Rect2(offset, arena.position.y, band, arena.size.y), wash)
		draw_rect(Rect2(size.x - offset - band, arena.position.y, band, arena.size.y), wash)
		draw_rect(Rect2(0.0, arena.position.y + arena.size.y - offset - band, size.x, band), wash)


# --- the squad ---------------------------------------------------------------


## The squad: one figure per two HP the side went in with, the surplus toppling
## away as the volley lands. Drawn back to front so the outermost figure — the
## one nearest the camera's edge of the frame — is the one in front.
func _draw_squad(arena: Rect2) -> void:
	if squad_alpha <= 0.0:
		return
	_draw_scuff(arena)
	var posted := maxi(squad_now, squad_was)
	# Each falls a beat after the one before it, so a squad losing three figures
	# reads as three going down rather than a row vanishing. `reach` is what pays
	# for that: the last one to start still has a full fall left when the window
	# closes, so the run has to be long enough for all of them to finish it.
	var reach := 1.0 + TOPPLE_STAGGER * maxf(posted - squad_now - 1, 0.0)
	var knock := _knock_share()
	for slot in range(posted - 1, -1, -1):
		var ground := _figure_point(arena, slot)
		var toppling := slot >= squad_now
		var run := 0.0
		if toppling:
			run = clampf(casualty_p * reach - (slot - squad_now) * TOPPLE_STAGGER, 0.0, 1.0)
		var fall := topple_fall(run, knock)
		if fall >= 1.0:
			continue
		var standing := not toppling
		var roll := arrive_offset(arrive_p, arrive_scale, unit.type.domain, slot, clock, _on_foot())
		# The shadow travels with the squad as it rolls in — that is the whole
		# vehicle crossing the plane — and stays put for everything after, which
		# is what makes an aircraft read as flying rather than as a tank drawn
		# too high, and a casualty as thrown rather than as sliding.
		_draw_shadow(ground + Vector2(_inward(roll.x), 0.0), 1.0 - fall)
		_draw_figure(
			ground + _pose_offset(roll, slot, fall, standing),
			fall,
			standing,
			topple_jerk(run, knock)
		)


## Everything that moves a figure off its own patch of ground: the roll-in it
## arrives on, the wind-up it holds, the recoil along the firing axis, the shove
## of taking a hit, and an aircraft's cruising height. Composed in the inward
## frame — positive points at the seam — and mirrored once, at the end.
##
## Only a figure still on its feet braces: one already being knocked back is
## being thrown outward, and shoving it inward at the same time cancels half of
## the hit it is reading.
func _pose_offset(roll: Vector2, slot: int, fall: float, standing: bool) -> Vector2:
	var offset := roll + aim_offset(aim_p, aim_lift)
	offset.x += lunge + (BRACE_PX * flash if standing else 0.0)
	return Vector2(_inward(offset.x), offset.y + _altitude(slot, fall))


## Whether this half marches in rather than rolling in, off the scuff its style
## kicks — a style id read here would be a second opinion on what a weapon is.
func _on_foot() -> bool:
	return dust <= FOOT_DUST and not _flying and not _floating


## What share of a casualty's own run is the knock-back. KNOCK_SECONDS is stated
## against the window CombatBeats really sized — asked of it via `casualty_lost`
## rather than re-derived from squad counts — so the jerk keeps its length
## whatever the clock is running at.
func _knock_share() -> float:
	var window := CombatBeats.casualty_window(Vector2(0.0, CombatBeats.IMPACT), casualty_lost)
	var span := window.y - window.x
	if span <= 0.0:
		return 0.0
	return clampf(KNOCK_SECONDS / span, 0.0, 1.0)


## The scuff a squad kicks off the ground line as it rolls into its slot, and
## again as its own recoil thrusts: three flat puffs outward of the outermost
## figure, sized by how much dirt this style throws. Nothing at all for a hull
## over water or a wing over nothing.
func _draw_scuff(arena: Rect2) -> void:
	if dust <= 0.0 or _flying or _floating:
		return
	var kick := maxf(
		CutsceneFx.ramp(arrive_p, [0.0, 0.7, 1.0], [0.3, 1.0, 0.0]), clampf(lunge / 13.0, 0.0, 1.0)
	)
	if kick <= 0.0:
		return
	# The dirt is the ground's own colour lifted, so a beach kicks sand and a
	# forest floor kicks loam without a table of dust colours anywhere.
	var dirt := _ridge_tint.lightened(0.45)
	var at := _figure_point(arena, 0)
	var outward := -_inward(1.0)
	for i in SCUFF_PUFFS:
		var tint := Color(dirt, 0.22 * dust * kick * (1.0 - i * 0.25))
		draw_colored_polygon(scuff_polygon(at, outward, kick, i), tint)


## How far above its own patch of ground a figure sits. Aircraft ride high and
## bob, each on its own phase so a flight of four does not pulse in unison;
## everything else stands on the deck. A falling figure loses its lift as it
## goes: a shot-down plane comes down.
func _altitude(slot: int, fall: float) -> float:
	if not _flying:
		return 0.0
	var bob := sin(clock * HOVER_RATE + slot * HOVER_PHASE) * HOVER_SWING
	return (-HOVER_HEIGHT + bob) * (1.0 - fall)


## Ground units get a flattened contact shadow — the light is high and the
## ground is a plane, so it lies down on it. A hull gets a pale wake instead: a
## dark disc under a ship reads as a hole in the water.
##
## Centred on the cell's own ground line rather than on the box's bottom edge,
## which is UnitSprite.CELL_GROUND_PX above it: the bottom of the cell is where
## the board's cast shadow spread to, and the figure sheet has that shadow
## subtracted, so an ellipse on the box's edge sits below the tracks it is
## supposed to be under.
func _draw_shadow(ground: Vector2, strength: float) -> void:
	var tint := Color(CutscenePalette.GROUND_SHADOW, 0.3 * strength * squad_alpha)
	var reach := 22.0
	if _floating:
		tint = Color(1.0, 1.0, 1.0, 0.28 * strength * squad_alpha)
		reach = 26.0
	elif _flying:
		# Cast from height: wider, fainter, and further from the thing casting it.
		tint.a *= 0.55
		reach = 26.0
	draw_set_transform(ground + Vector2(0.0, -UnitSprite.CELL_GROUND_PX), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, reach, tint)
	draw_set_transform(Vector2.ZERO)


## One figure, standing on `feet` and facing the seam. Drawn twice: a hard offset
## shadow first, then the art, over-brightened while flashing — the same
## white-hit language UnitSprite already uses on the board.
##
## `fall` above zero knocks it out: kicked up and back, tipping over, burning
## down as it goes. The tip is deliberately shallow — these are the board's own
## three-quarter-view sprites, and spinning one right over reads as a rendering
## glitch rather than a casualty (plan R3).
##
## Where the burn ends is the domain's. A figure with no authored KO frame —
## air, in v1 — burns the whole fall down to a dark silhouette, as every figure
## did before S4. One that HAS a frame swaps to it past `TOPPLE_KO_AT`, and the
## burn turns around there: `KO_SETTLE_TINT` opens on the value the burn had
## reached and eases back to 1.0 by the landing, so the wreck settles onto its
## own baked tone — which `wreck_tone` floors and rim-strips, leaving it flatter
## and, by the end, brighter than the figure stood. The alpha fade is over it
## from 0.55. `spin`, `lift` and that fade all keep running unmoved across the
## swap, so only the texture changes, never a beat.
##
## `jerk` above zero is the knock-back that precedes the fall: the round has
## landed on this figure and it is thrown outward and lit before it goes over.
##
## A figure already on its way down does not flash: it has taken its hit.
func _draw_figure(feet: Vector2, fall: float, hittable: bool, jerk: float) -> void:
	var flip := Vector2(-1.0 if mirror else 1.0, 1.0)
	var box := Rect2(
		-CutscenePlates.FIGURE_PX * 0.5,
		-CutscenePlates.FIGURE_H,
		CutscenePlates.FIGURE_PX,
		CutscenePlates.FIGURE_H
	)
	var lift := 0.0
	var spin := 0.0
	var tip := aim_tilt(aim_p, aim_pitch)
	var alpha := squad_alpha
	var tint := Color(1.0, 1.0, 1.0)
	# One burn-down, handed over at the swap: every figure falls on WRECK_TINT,
	# and the authored KO frame picks it up at the value that ramp had reached
	# and eases off it over the rest of the fall.
	var ko_art: AtlasTexture = _figures[2]
	var ko := ko_art != null and fall >= TOPPLE_KO_AT
	if fall > 0.0:
		tip = 0.0
		lift = CutsceneFx.ramp(fall, [0.0, 0.3, 1.0], [0.0, -13.0, 46.0])
		spin = CutsceneFx.ramp(fall, [0.0, 1.0], [0.0, _inward(-0.55)])
		alpha *= CutsceneFx.ramp(fall, [0.0, 0.55, 1.0], [1.0, 1.0, 0.0])
		if ko:
			tint = tint.lerp(KO_SETTLE_TINT, CutsceneFx.ramp(fall, [TOPPLE_KO_AT, 1.0], [1.0, 0.0]))
		else:
			tint = tint.lerp(WRECK_TINT, CutsceneFx.ramp(fall, [0.0, 0.35, 1.0], [0.0, 0.85, 1.0]))
	elif hittable:
		tint = tint.lerp(Color(3.4, 3.4, 3.4), flash)
	else:
		tint = tint.lerp(Color(3.4, 3.4, 3.4), jerk)
	var at := feet + Vector2(_inward(-fall * 10.0 - KNOCK_PX * jerk), lift)
	draw_set_transform_matrix(Transform2D(spin, flip, 0.0, at))
	var shadow := Color(CutscenePalette.FIGURE_SHADOW, 0.4 * alpha)
	var art := ko_art if ko else _figure_now()
	_draw_tipped(art, Rect2(box.position + Vector2(2.0, 3.0), box.size), tip, shadow)
	tint.a = alpha
	_draw_tipped(art, box, tip, tint)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## The art in its box, tipped by `tilt` radians about its own feet — as a
## **whole-pixel shear**, in bands that each step one pixel, rather than as a
## rotation.
##
## A rotation resamples the cell's own texels, and the wind-up's tip is *held*:
## it is the pose the frame is stared at through the whole volley and impact, so
## a silhouette that jags along its edges is a permanent artefact rather than a
## passing one. A band keeps its texel grid intact and steps a whole pixel, which
## is the discipline the zoom ladder keeps for the same reason. The topple's tip
## is still a real rotation — it is over in a third of a second, and it goes far
## enough that a shear would shred it.
##
## Inside this transform +x already points at the seam on both halves, so the
## lean needs no mirroring of its own.
func _draw_tipped(art: AtlasTexture, box: Rect2, tilt: float, tint: Color) -> void:
	var lean := sin(tilt)
	var bands := ceili(absf(lean) * box.size.y)
	if bands <= 1:
		draw_texture_rect(art, box, false, tint)
		return
	var step := box.size.y / bands
	var source := art.region
	var cut := source.size.y / bands
	for i in bands:
		var top := box.position.y + step * i
		var height := box.position.y + box.size.y - (top + step * 0.5)
		draw_texture_rect_region(
			art.atlas,
			Rect2(box.position.x + roundf(lean * height), top, box.size.x, step),
			Rect2(source.position + Vector2(0.0, cut * i), Vector2(source.size.x, cut)),
			tint
		)


## Which pose the squad is standing in, off this cut-in's own clock at the
## board's ambient cadence: the fire cut while `fire_p`'s window is open —
## strictly inside it, so a posed still at either endpoint reads as idle
## rather than betting on a boundary — idle otherwise. Beats do not move for
## this: only which texture is drawn does, so every locked pose constant
## (the recoil ramp, the volley window) survives untouched. The sustained
## pair's alternation reads on this same director's clock, never the wall
## one — `CutscenePlates.figure_now` is the one seam either pair uses.
func _figure_now() -> AtlasTexture:
	if fire_p > 0.0 and fire_p < 1.0:
		return CutscenePlates.figure_now(_fire_figures, clock)
	return CutscenePlates.figure_now(_figures, clock)


# --- the motion, as pure functions of the pose --------------------------------
#
# Every one of these is arithmetic on a scalar CombatCutscene wrote and a figure
# index. No tween, no accumulator, no RNG — which is what makes a skip and a
# posed still land on the same frame as playing the beat through would.


## Where a figure sits relative to its firing slot while the squad is still
## rolling in: outward and easing to nothing, past the slot by SETTLE_PX and back
## as it halts. Positive x points at the seam, as everywhere else here.
##
## The roll-in is a *translation of the idle pose*, deliberately: the cut-in cuts
## its figures from the shadow-subtracted sheet, only the ambient pair has one,
## and drawing the walk clip here would bring the tile's baked contact shadow
## back to double against the ellipse this half draws for itself.
##
## A posted squad returns exactly zero, so every frame after the beat closes is
## the frame it was before there was an arrive beat at all.
static func arrive_offset(
	arrive_p: float, arrive_scale: float, domain: StringName, slot: int, clock: float, on_foot: bool
) -> Vector2:
	if arrive_p >= 1.0:
		return Vector2.ZERO
	var p := march_progress(arrive_p, slot if on_foot else 0)
	var run := pow(1.0 - p, 3.0)
	var settle := (
		SETTLE_PX
		* CutsceneFx.ramp(p, [1.0 - SETTLE_BAND, 1.0 - SETTLE_BAND * 0.5, 1.0], [0.0, 1.0, 0.0])
	)
	var rise := 0.0
	if domain == UnitType.AIR:
		rise = -BANK_PX * run
	elif domain == UnitType.SEA:
		rise = sin(clock * HOVER_RATE) * SWELL_PX * (1.0 - p)
	elif on_foot:
		rise = sin(p * TAU * TRUDGE_STEPS) * TRUDGE_PX
	return Vector2(settle - ARRIVE_PX * arrive_scale * run, rise)


## Where one figure of a marching rank is in its own arrival. The rank sets off
## in order, and each figure's run is compressed rather than merely delayed, so
## the last man still lands exactly as the beat closes.
static func march_progress(arrive_p: float, slot: int) -> float:
	var lag := MARCH_STAGGER * clampi(slot, 0, MAX_FIGURES - 1)
	return clampf((arrive_p - lag) / (1.0 - lag), 0.0, 1.0)


## The wind-up's pose: the weapon lifts `lift` px and the figure drifts back off
## the seam with it, both easing out over the front of the beat and then held —
## the hold is what a player stares at for the whole volley and impact.
static func aim_offset(aim_p: float, lift: float) -> Vector2:
	var ease := _aim_ease(aim_p)
	return Vector2(-lift * AIM_DRIFT * ease, -lift * ease)


## And how far it tips over that same beat, about its own feet. Clamped rather
## than honoured past AIM_PITCH_MAX: a board sprite tipped further reads as a
## rendering fault, not as a barrel coming up.
static func aim_tilt(aim_p: float, pitch: float) -> float:
	return clampf(pitch, -AIM_PITCH_MAX, AIM_PITCH_MAX) * _aim_ease(aim_p)


static func _aim_ease(aim_p: float) -> float:
	return 1.0 - pow(1.0 - clampf(aim_p / AIM_EASE, 0.0, 1.0), 3.0)


## One scuff puff, lying flat on the ground plane: a lens of dust centred
## `outward` of `at`, each one further out and wider than the last as the kick
## spreads. Floored at SCUFF_MIN_REACH so a puff ramped from nothing never lands
## its points on one float for the triangulator to refuse.
static func scuff_polygon(
	at: Vector2, outward: float, spread: float, index: int
) -> PackedVector2Array:
	var reach := maxf(SCUFF_MIN_REACH, SCUFF_REACH * (0.4 + spread) * (1.0 + index * 0.3))
	var center := at + Vector2(outward * SCUFF_STEP * (index + spread), -reach * SCUFF_FLAT)
	var points := PackedVector2Array()
	for i in 8:
		var angle := float(i) * TAU / 8.0
		points.append(center + Vector2(cos(angle) * reach, sin(angle) * reach * SCUFF_FLAT))
	return points


## A casualty's own run, split in two: it is knocked back first and tips after,
## so a hit reads as men being struck rather than as men deciding to fall over.
static func topple_fall(run: float, knock: float) -> float:
	if run <= knock or knock >= 1.0:
		return 0.0
	return (run - knock) / (1.0 - knock)


## The knock-back itself — out and back once, over the front of that run.
static func topple_jerk(run: float, knock: float) -> float:
	if knock <= 0.0 or run <= 0.0 or run >= knock:
		return 0.0
	return CutsceneFx.ramp(run, [0.0, knock * 0.5, knock], [0.0, 1.0, 0.0])


# --- plates ------------------------------------------------------------------


## Name and HP above, terrain and defence stars below. Both slide in from the
## outer edge as `plate_p` rises, so the frame assembles itself rather than
## snapping into place.
func _draw_plates() -> void:
	if plate_p <= 0.0:
		return
	var slide := _inward(-40.0 * (1.0 - plate_p))
	draw_set_transform(Vector2(slide, 0.0))
	CutscenePlates.draw_frames(self, size, plate_p)
	var top := Rect2(0.0, 0.0, size.x, CutscenePlates.TOP_H)
	_draw_name_row(top)
	_draw_pips(top)
	_draw_terrain_row(Rect2(0.0, size.y - CutscenePlates.BOT_H, size.x, CutscenePlates.BOT_H))
	draw_set_transform(Vector2.ZERO)


func _draw_name_row(plate: Rect2) -> void:
	var font := get_theme_font(&"font", &"Label")
	var title := unit.type.display_name.to_upper()
	var text_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var bar_x := _outward_px(PLATE_MARGIN - 10.0) - (4.0 if mirror else 0.0)
	draw_rect(Rect2(bar_x, plate.position.y + 6.0, 4.0, 13.0), Color(accent, plate_p))
	var text_x := _outward_px(PLATE_MARGIN) - (text_width if mirror else 0.0)
	draw_string(
		font,
		Vector2(text_x, plate.position.y + 18.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(1.0, 1.0, 1.0, plate_p)
	)
	_draw_weapon_chip(font, plate, PLATE_MARGIN + text_width + CHIP_GAP)


## The weapon chip: a bordered box holding one word, set inward of the unit's name
## so it reads as an annotation on it. Laid out from the same outward measure the
## rest of the plate uses, so it lands beside the name on either half.
func _draw_weapon_chip(font: Font, plate: Rect2, from_edge: float) -> void:
	if weapon_label == "":
		return
	var text := font.get_string_size(weapon_label, HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT_PX)
	var box := Vector2(text.x + CHIP_PAD.x * 2.0, CHIP_FONT_PX + CHIP_PAD.y * 2.0)
	var left := _outward_px(from_edge) - (box.x if mirror else 0.0)
	var top := plate.position.y + (CutscenePlates.TOP_H - box.y) * 0.5 - 1.0
	var frame := Rect2(left, top, box.x, box.y)
	draw_rect(frame, Color(CutscenePalette.STROKE, 0.35 * plate_p))
	draw_rect(frame, Color(CHIP_BORDER, CHIP_BORDER.a * plate_p), false, 1.0)
	draw_string(
		font,
		Vector2(left + CHIP_PAD.x, top + box.y - CHIP_PAD.y - 1.0),
		weapon_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		CHIP_FONT_PX,
		Color(CHIP_TEXT, CHIP_TEXT.a * plate_p)
	)


## Ten pips, banded by health and depleting toward the seam, so both bars run
## out in the same direction and the two sides read as one gauge.
##
## The band comes from UiTheme, the one owner of that rule, and `hp_shown` is the
## displayed 0-10 it expects — the same number the bar's pips are set from. A
## private copy is what let the board and the cut-in call the same unit hurt in
## two different colours.
func _draw_pips(plate: Rect2) -> void:
	var band := UiTheme.hp_color(hp_shown)
	# Anchored to the seam and running outward, so both bars deplete toward the
	# middle of the frame and the two read as one gauge.
	var seam := _outward_px(size.x - SEAM_MARGIN)
	for i in PIP_COUNT:
		var step := (PIP_SIZE.x + PIP_GAP) * (PIP_COUNT - 1 - i)
		var x := seam - _inward(step) - (0.0 if mirror else PIP_SIZE.x)
		var pip := band if i < hp_shown else HP_EMPTY
		draw_rect(
			Rect2(x, plate.position.y + 9.0, PIP_SIZE.x, PIP_SIZE.y), Color(pip, pip.a * plate_p)
		)


## Anchored to this half's outer edge and reading inward, the way the tile panel
## already writes "DEF ★☆☆☆" — anchored to the seam instead, the two sides' rows
## grow toward each other and collide in the middle of the frame.
func _draw_terrain_row(plate: Rect2) -> void:
	CutscenePlates.draw_terrain_row(
		self,
		get_theme_font(&"font", &"Label"),
		plate.position.y,
		terrain.display_name.to_upper(),
		_outward_px(PLATE_MARGIN),
		_inward(1.0),
		TERRAIN_STAR_GAP,
		terrain.defense_stars,
		plate_p
	)


# --- mirroring helpers -------------------------------------------------------


## An x measured from this side's *outer* edge, so one set of layout numbers
## describes both halves.
func _outward_px(from_edge: float) -> float:
	return size.x - from_edge if mirror else from_edge


## The same thing as a share of the width.
func _outward(fraction: float) -> float:
	return _outward_px(size.x * fraction)


## Flips a delta so positive always points at the seam — the direction a unit
## lunges, fires and recoils along.
func _inward(delta: float) -> float:
	return -delta if mirror else delta


## The terrain atlas row this cell's own art is drawn from: the owner's faction
## row on a property, the untinted row 0 on plain terrain and on anything unowned.
func _atlas_row() -> int:
	return SideIdentity.terrain_row(terrain, owner_row)


## And the row the paved floor is drawn from — asked of the *paving* terrain, not
## the cell's. A city stands on road, and road wears nobody's colours.
func _ground_row() -> int:
	return SideIdentity.terrain_row(ground, owner_row)
