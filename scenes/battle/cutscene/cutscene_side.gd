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
## figure is the board's own unit art — blown up, never redrawn (plan D2). The
## scenery a standing terrain puts on that ground is the one exception, and says
## so where it is declared (TerrainType.cutin_scenery). The other thing derived
## rather than drawn is the horizon ridge's colour, which is averaged off the
## terrain tile so a new terrain needs no entry anywhere.

const PLATE_TOP_H := 26
const PLATE_BOT_H := 20
## Share of the arena the ground plane fills, measured up from the bottom.
const GROUND_RATIO := 0.45
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
## How tall each kind stands at full size. A ridge dwarfs a pine, and a tower
## splits the difference while going far higher than either above the horizon.
const TREE_PX := 40.0
const PEAK_PX := 64.0
const BUILDING_PX := 68.0
## How far the dark edge around a drawn silhouette reaches past it.
const SCENERY_EDGE := 1.6
## The part of an atlas cell that is the object rather than the ground around it:
## the middle, where every one of these tiles draws its peak, canopy or building.
## The scenery's colour is averaged over this and nothing else.
const OBJECT_WINDOW := Rect2i(20, 14, 24, 30)
## Figures are the 64 px atlas art at its own resolution — nearest-neighbour
## scaling of pixel art to a fractional size drops rows unevenly, so it isn't.
const FIGURE_PX := 64
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
## What a knocked-out figure burns down to on its way off the field.
const WRECK_TINT := Color(0.22, 0.20, 0.21)
## The snowline on a ridge, and a building's two window states.
const SNOW := Color(0.933, 0.953, 0.965)
const WINDOW_LIT := Color(CutscenePalette.GOLD, 0.85)
const WINDOW_DARK := Color(CutscenePalette.SKY_HORIZON, 0.45)
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
const MAX_STARS := 4
const STAR_STEP := 11.0
## How far plate content is held off the frame's outer edge. Generous on purpose:
## the band pushes in slightly over the exchange, so a few pixels either side are
## outside the viewport at the moment the volley lands.
const PLATE_MARGIN := 26.0
## The matching hold-off from the seam, for the content that sits against it.
const SEAM_MARGIN := 18.0

## Cached average colour per sampled atlas band — the horizon ridge's tint and the
## scenery's. Keyed by atlas (column, row, depth) rather than terrain id so an
## owner-tinted city ridge follows the same team colour the board paints, and the
## two depths one cell is read at cannot overwrite each other.
static var _tint_cache: Dictionary = {}
## The atlas as a mutable RGBA8 Image, decompressed once for `_cell_tint`'s reads
## (MapThumbnail._atlas_source_image documents the same trade).
static var _atlas_image: Image

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
## 0 -> 1 as the surplus figures rise, spin and fall away.
var fall_p := 0.0
## Recoil offset along the firing axis: negative pulls back, positive thrusts.
var lunge := 0.0
## 0 -> 1 white over-brighten on taking a hit.
var flash := 0.0
## Fades whatever is left standing — what the death explosion takes with it.
var squad_alpha := 1.0
## 0 -> 1 as the plates slide in and their text appears.
var plate_p := 0.0
## The cut-in's clock, in seconds, for the one thing here that is a function of
## time rather than of a beat: an aircraft's hover bob. Written by the director
## like everything else, so a posed still is still a pure function of `_t`.
var clock := 0.0

var _art: AtlasTexture
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
	_art = UnitSprite.texture_for(p_unit.type, p_unit_row)
	_ridge_tint = _ground_tint(ground.atlas_col, _ground_row())
	_flying = p_unit.type.domain == UnitType.AIR
	_floating = p_unit.type.domain == UnitType.SEA


## The atlas row this side's figures are really drawn from, read back off the
## region `bind` baked, and the row its ground strip is drawn from. Both are
## reads for the scenario driver's row check, which asks what is on screen rather
## than what was remembered — the side stays draw-only.
func drawn_unit_row() -> int:
	if _art == null:
		return -1
	return int(_art.region.position.y) / UnitSprite.SPRITE_PX


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
## the squad is drawn with rather than hand-tuned twice.
func muzzle_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	var arena := _arena()
	for slot in squad_now:
		var at := figure_point(arena, slot) + Vector2(_inward(22.0), -34.0)
		points.append(at + Vector2(0.0, _altitude(slot, 0.0)))
	return points


## Where one figure of the squad stands, in this control's coordinates.
##
## The formation is laid out from its own middle rather than from its outermost
## figure: the posted squad's span is measured off `squad_was` and halved, so
## every size stays centred on SQUAD_CENTER.
func figure_point(arena: Rect2, slot: int) -> Vector2:
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
	return Rect2(0.0, PLATE_TOP_H, size.x, size.y - PLATE_TOP_H - PLATE_BOT_H)


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
	var bands := 32
	for i in bands:
		var top := arena.position.y + (horizon - arena.position.y) * float(i) / bands
		var bottom := arena.position.y + (horizon - arena.position.y) * float(i + 1) / bands
		var shade := CutscenePalette.SKY_TOP.lerp(
			CutscenePalette.SKY_HORIZON, float(i) / float(bands - 1)
		)
		draw_rect(Rect2(0.0, top, size.x, bottom - top + 1.0), shade)
	_draw_cloud(Vector2(_outward(0.30), arena.position.y + arena.size.y * 0.17), 1.0)
	_draw_cloud(Vector2(_outward(0.74), arena.position.y + arena.size.y * 0.07), 0.62)
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
	var atlas := _terrain_atlas()
	var source := _cell_region(ground, _ground_row())
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
	return arena.position.y + arena.size.y * (1.0 - GROUND_RATIO)


func _draw_cloud(at: Vector2, scale: float) -> void:
	var white := Color(1.0, 1.0, 1.0, 0.85)
	draw_rect(Rect2(at.x - 30.0 * scale, at.y, 60.0 * scale, 9.0 * scale), white)
	draw_circle(at + Vector2(-14.0, 1.0) * scale, 9.0 * scale, white)
	draw_circle(at + Vector2(2.0, -3.0) * scale, 13.0 * scale, white)
	draw_circle(at + Vector2(18.0, 0.0) * scale, 8.0 * scale, white)


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
## blitted and coloured from the board's own cell. That is the cut-in's one
## departure from plan D2 — TerrainType.cutin_scenery carries why. Nothing is
## drawn for a terrain that paves: there the floor already *is* that terrain,
## which is the whole of the distinction.
func _draw_scenery(arena: Rect2) -> void:
	if terrain == null or terrain.cutin_scenery == TerrainType.NO_SCENERY:
		return
	# The colour is the cell's own, averaged off the atlas at the row its owner
	# paints it in — so a base standing here is the same slate or green the board
	# shows, and a neutral one the same grey, without a table of scenery colours
	# anywhere. Each shape darkens it to taste; the average of a whole cell is
	# already muted, and darkening it again here turned a pine into a black blob.
	var tint := _object_tint(terrain.atlas_col, _atlas_row())
	var kind := terrain.cutin_scenery
	var full := (
		TREE_PX
		if kind == TerrainType.TREES
		else (PEAK_PX if kind == TerrainType.PEAKS else BUILDING_PX)
	)
	for slot in SCENERY_SLOTS:
		var base := Vector2(_outward(slot.x), arena.position.y + arena.size.y * slot.y)
		var height := full * slot.z
		# Distance drains contrast here exactly as it does on the ground rows, so
		# the one furthest back sits behind the field rather than on top of it.
		var lit := lerpf(0.86, 1.0, clampf((slot.y - _GROUND_TOP) / _GROUND_DEPTH, 0.0, 1.0))
		var shade := Color(tint.r * lit, tint.g * lit, tint.b * lit, 1.0)
		draw_set_transform(base + Vector2(0.0, -2.0), 0.0, Vector2(1.0, 0.24))
		draw_circle(Vector2.ZERO, height * 0.3, Color(CutscenePalette.GROUND_SHADOW, 0.22))
		draw_set_transform(Vector2.ZERO)
		match kind:
			TerrainType.TREES:
				_draw_tree(base, height, shade)
			TerrainType.PEAKS:
				_draw_peak(base, height, shade)
			_:
				_draw_building(base, height, shade)


## A conifer: a short dark trunk under three stacked skirts, each narrower and a
## shade lighter than the one below, which is what makes a flat triangle read as
## a tree rather than as a road sign.
func _draw_tree(base: Vector2, height: float, shade: Color) -> void:
	var half := height * 0.30
	draw_rect(
		Rect2(base.x - height * 0.05, base.y - height * 0.30, height * 0.10, height * 0.30),
		shade.darkened(0.45)
	)
	for tier in 3:
		var top := base.y - height * (0.42 + tier * 0.22)
		var bottom := top + height * 0.30
		var spread := half * (1.0 - tier * 0.24)
		_outlined_triangle(
			Vector2(base.x - spread, bottom),
			Vector2(base.x + spread, bottom),
			Vector2(base.x, top),
			shade.darkened(0.34 - tier * 0.11)
		)


## A triangle with a hard dark edge around it. Scenery is drawn in the terrain's
## own colour, and woods over plains is green on green — the outline is what keeps
## a pine legible against ground the same hue, the way every round in the volley
## carries one for the same reason.
func _outlined_triangle(a: Vector2, b: Vector2, c: Vector2, fill: Color) -> void:
	var middle := (a + b + c) / 3.0
	var grown := PackedVector2Array()
	for corner in [a, b, c]:
		grown.append(corner + (corner - middle).normalized() * SCENERY_EDGE)
	draw_colored_polygon(grown, Color(CutscenePalette.STROKE, 0.55))
	draw_colored_polygon(PackedVector2Array([a, b, c]), fill)


## A ridge: one broad triangle with a snowline capping it.
func _draw_peak(base: Vector2, height: float, shade: Color) -> void:
	var half := height * 0.78
	var apex := Vector2(base.x, base.y - height)
	_outlined_triangle(
		Vector2(base.x - half, base.y), Vector2(base.x + half, base.y), apex, shade.darkened(0.28)
	)
	var cap := height * 0.34
	var cap_half := half * cap / height
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(apex.x - cap_half, apex.y + cap),
				Vector2(apex.x + cap_half, apex.y + cap),
				apex,
			]
		),
		SNOW
	)


## A block with a darker parapet and lit windows. The windows are what sell it at
## this size — a plain rectangle reads as a wall, and two rows of squares read as
## somewhere people are.
func _draw_building(base: Vector2, height: float, shade: Color) -> void:
	var width := height * 0.52
	var left := base.x - width * 0.5
	draw_rect(Rect2(left, base.y - height, width, height), shade.darkened(0.18))
	draw_rect(Rect2(left, base.y - height, width, height * 0.07), shade.darkened(0.45))
	# The sunless face, so the block has a corner rather than being a flat card.
	draw_rect(
		Rect2(left + width * 0.82, base.y - height, width * 0.18, height), shade.darkened(0.38)
	)
	var columns := 2
	var rows := maxi(2, int(height / 14.0))
	var pane := Vector2(width * 0.17, height * 0.055)
	for row in rows:
		for column in columns:
			var at := Vector2(
				left + width * (0.22 + column * 0.34), base.y - height * 0.86 + row * height * 0.13
			)
			if at.y + pane.y > base.y - height * 0.06:
				continue
			var pane_tint := WINDOW_LIT if (row + column) % 3 == 0 else WINDOW_DARK
			draw_rect(Rect2(at, pane), pane_tint)


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
	var posted := maxi(squad_now, squad_was)
	# Each falls a beat after the one before it, so a squad losing three figures
	# reads as three going down rather than a row vanishing. `reach` is what pays
	# for that: the last one to start still has a full fall left when the window
	# closes, so the run has to be long enough for all of them to finish it.
	var reach := 1.0 + TOPPLE_STAGGER * maxf(posted - squad_now - 1, 0.0)
	for slot in range(posted - 1, -1, -1):
		var ground := figure_point(arena, slot)
		var toppling := slot >= squad_now
		var fall := 0.0
		if toppling:
			fall = clampf(fall_p * reach - (slot - squad_now) * TOPPLE_STAGGER, 0.0, 1.0)
		if fall >= 1.0:
			continue
		# The shadow stays on the ground whatever the figure is doing above it —
		# which is exactly what makes an aircraft read as flying rather than as a
		# tank drawn too high.
		_draw_shadow(ground, 1.0 - fall)
		_draw_figure(ground + Vector2(_inward(lunge), _altitude(slot, fall)), fall, not toppling)


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
	draw_set_transform(ground + Vector2(0.0, -2.0), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, reach, tint)
	draw_set_transform(Vector2.ZERO)


## One figure, standing on `feet` and facing the seam. Drawn twice: a hard offset
## shadow first, then the art, over-brightened while flashing — the same
## white-hit language UnitSprite already uses on the board.
##
## `fall` above zero knocks it out: kicked up and back, tipping over, burning
## down to a dark silhouette as it goes. The tip is deliberately shallow — these
## are the board's own three-quarter-view sprites, and spinning one right over
## reads as a rendering glitch rather than a casualty (plan R3).
##
## A figure already on its way down does not flash: it has taken its hit.
func _draw_figure(feet: Vector2, fall: float, hittable: bool) -> void:
	var flip := Vector2(-1.0 if mirror else 1.0, 1.0)
	var box := Rect2(-FIGURE_PX * 0.5, -FIGURE_PX, FIGURE_PX, FIGURE_PX)
	var lift := 0.0
	var spin := 0.0
	var alpha := squad_alpha
	var tint := Color(1.0, 1.0, 1.0)
	if fall > 0.0:
		lift = CutsceneFx.ramp(fall, [0.0, 0.3, 1.0], [0.0, -13.0, 46.0])
		spin = CutsceneFx.ramp(fall, [0.0, 1.0], [0.0, _inward(-0.55)])
		alpha *= CutsceneFx.ramp(fall, [0.0, 0.55, 1.0], [1.0, 1.0, 0.0])
		tint = tint.lerp(WRECK_TINT, CutsceneFx.ramp(fall, [0.0, 0.35, 1.0], [0.0, 0.85, 1.0]))
	elif hittable:
		tint = tint.lerp(Color(3.4, 3.4, 3.4), flash)
	var at := feet + Vector2(_inward(-fall * 10.0), lift)
	draw_set_transform_matrix(Transform2D(spin, flip, 0.0, at))
	var shadow := Color(CutscenePalette.FIGURE_SHADOW, 0.4 * alpha)
	draw_texture_rect(_art, Rect2(box.position + Vector2(2.0, 3.0), box.size), false, shadow)
	tint.a = alpha
	draw_texture_rect(_art, box, false, tint)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# --- plates ------------------------------------------------------------------


## Name and HP above, terrain and defence stars below. Both slide in from the
## outer edge as `plate_p` rises, so the frame assembles itself rather than
## snapping into place.
func _draw_plates() -> void:
	if plate_p <= 0.0:
		return
	var slide := _inward(-40.0 * (1.0 - plate_p))
	draw_set_transform(Vector2(slide, 0.0))
	var top := Rect2(0.0, 0.0, size.x, PLATE_TOP_H)
	draw_rect(top, Color(CutscenePalette.PLATE, plate_p))
	draw_rect(Rect2(0.0, PLATE_TOP_H - 2.0, size.x, 2.0), Color(CutscenePalette.STROKE, plate_p))
	_draw_name_row(top)
	_draw_pips(top)
	var bottom := Rect2(0.0, size.y - PLATE_BOT_H, size.x, PLATE_BOT_H)
	draw_rect(bottom, Color(CutscenePalette.PLATE, plate_p))
	draw_rect(Rect2(0.0, bottom.position.y, size.x, 2.0), Color(CutscenePalette.STROKE, plate_p))
	_draw_terrain_row(bottom)
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
	var top := plate.position.y + (PLATE_TOP_H - box.y) * 0.5 - 1.0
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


func _draw_terrain_row(plate: Rect2) -> void:
	var font := get_theme_font(&"font", &"Label")
	var label := terrain.display_name.to_upper()
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var text_x := _outward_px(PLATE_MARGIN) - (width if mirror else 0.0)
	draw_string(
		font,
		Vector2(text_x, plate.position.y + 14.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		Color(CutscenePalette.PLATE_TEXT, CutscenePalette.PLATE_TEXT.a * plate_p)
	)
	# Beside the name and reading inward, the way the tile panel already writes
	# "DEF ★☆☆☆" — anchored to the seam instead, the two sides' rows grow toward
	# each other and collide in the middle of the frame.
	var first := _outward_px(PLATE_MARGIN + width + 12.0)
	var stars := mini(terrain.defense_stars, MAX_STARS)
	for i in MAX_STARS:
		var center := Vector2(first + _inward(STAR_STEP * i), plate.position.y + 10.0)
		var tint := CutscenePalette.GOLD if i < stars else CutscenePalette.STAR_OFF
		draw_colored_polygon(_star_points(center, 4.5), Color(tint, tint.a * plate_p))


func _star_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var reach := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI * 0.5 + float(i) * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * reach)
	return points


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
	return owner_row if terrain.team_tinted else SideIdentity.NEUTRAL_ROW


## And the row the paved floor is drawn from — asked of the *paving* terrain, not
## the cell's. A city stands on road, and road wears nobody's colours.
func _ground_row() -> int:
	return owner_row if ground.team_tinted else SideIdentity.NEUTRAL_ROW


## One cell of the terrain atlas, as a source rect.
static func _cell_region(of: TerrainType, row: int) -> Rect2:
	return Rect2(
		of.atlas_col * BattleView.TERRAIN_PX,
		row * BattleView.TERRAIN_PX,
		BattleView.TERRAIN_PX,
		BattleView.TERRAIN_PX
	)


static func _terrain_atlas() -> Texture2D:
	return load(BattleView.ATLAS_PATH)


## The atlas image `_cell_tint` samples, decompressed once and kept — `get_image`
## on every cache miss was ~140 decompressions a run.
static func _atlas_source_image() -> Image:
	if _atlas_image == null:
		_atlas_image = _terrain_atlas().get_image()
		if _atlas_image.get_format() != Image.FORMAT_RGBA8:
			_atlas_image.convert(Image.FORMAT_RGBA8)
	return _atlas_image


## The terrain tile's average colour, for the horizon ridge behind it. Sampled
## off the art rather than tabled here, so a new terrain — or a repainted one —
## needs no entry in the presentation layer at all.
static func _ground_tint(column: int, row: int) -> Color:
	return _cell_tint(column, row, Rect2i(0, 0, BattleView.TERRAIN_PX, BattleView.TERRAIN_PX))


## And the colour of the *object* on that cell, for the scenery standing here.
##
## Only the middle of the cell is sampled, and that window is the whole idea: a
## mountain tile is a grey peak drawn on a green square, so averaging the square
## returns grass and paints the ridge the colour of the field it rises out of.
## Every one of these tiles is its object drawn centred with its ground around the
## outside — true of the peak, the canopy and the tower alike, which is why one
## window serves all three and no shape needs a colour of its own.
static func _object_tint(column: int, row: int) -> Color:
	return _cell_tint(column, row, OBJECT_WINDOW)


## Average colour over one window of one atlas cell. Sampled off the art rather
## than tabled here, so a new terrain — or a repainted one — needs no entry in
## the presentation layer at all.
static func _cell_tint(column: int, row: int, window: Rect2i) -> Color:
	var key := [column, row, window]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var tint := CutscenePalette.PLATE
	var image := _atlas_source_image()
	if image != null:
		var total := Color(0.0, 0.0, 0.0)
		var samples := 0
		for y in range(window.position.y, window.end.y, 2):
			for x in range(window.position.x, window.end.x, 2):
				var pixel := image.get_pixel(
					column * BattleView.TERRAIN_PX + x, row * BattleView.TERRAIN_PX + y
				)
				total += Color(pixel.r, pixel.g, pixel.b)
				samples += 1
		if samples > 0:
			tint = Color(total.r / samples, total.g / samples, total.b / samples)
	_tint_cache[key] = tint
	return tint
