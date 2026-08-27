class_name CaptureStage
extends Control
## The diorama half of the capture cut-in: a strip of ground, the property being
## taken drawn from the board's own atlas cell, and a squad of infantry marching
## up to mash it down. The name/CAPTURE plate sits above, the property/defence
## plate below.
##
## Draws, and does nothing else — the sibling of CutsceneSide. Every value it
## renders is written onto it by CaptureCutscene, which owns the clock; the stage
## never reads the simulation, never advances time, and never decides an outcome.
## The squad is the board's own unit art, blown up, never redrawn (plan D2).
##
## The property is that plan's one recorded departure, taken here for the reason
## CutsceneScenery states: an atlas cell is a square of ground with the building
## drawn on it, so blitting the cell brought its opaque plate along and stood the
## property on a hard-edged green rectangle (COM-231). The shape is drawn instead
## and its colour sampled off that same cell — in the owner's team row, swapped to
## the capturer's at the flip — so the flip is the colour changing under a shape
## that keeps standing, and nothing about it is re-derived here.

## Share of the arena the grass plane fills, up from the bottom.
const GROUND_RATIO := 0.42
## How many steps the sky is graded in over what is left above it.
const SKY_BANDS := 28
## How tall the property's tallest shape stands. The board cell is 64 px; here it
## fills a good third of the frame so the flip is the thing the eye lands on.
const PROP_PX := 132.0
## The blocks the property is built out of, back to front: an x offset and a
## height, both shares of PROP_PX, with `y` the depth — 1.0 stands on the squad's
## own line and 0.0 sits furthest back. One tower reads as a wall at this size;
## three at three depths read as a place, the same reason CutsceneSide stands four.
const PROP_BLOCKS: Array[Vector3] = [
	Vector3(-0.30, 0.0, 0.60),
	Vector3(0.30, 0.45, 0.74),
	Vector3(0.0, 1.0, 1.0),
]
## How far back a block sits per unit of depth, as a share of PROP_PX.
const PROP_DEPTH_PX := 0.14
## The part of the atlas cell this cut-in takes the property's colour from: the
## roof band, where the board paints a property's owner. CutsceneSide averages the
## whole object instead, which is right for scenery a fight happens in front of —
## but here the property is the only thing on the stage and the flip is what the
## frame is *for*, and the object average carries enough grey wall and grass either
## side of the roof to leave two factions the same olive.
const ROOF_WINDOW := Rect2i(16, 24, 34, 16)
## Where the property's base sits, as a share of the arena, and how high off the
## bottom its feet rest.
const PROP_CENTER := 0.66
const FEET_RATIO := 0.82
## How many figures march (plan: infantry/mech capture, a three-figure squad
## carries it — the pip-exact number lives on the meter). The cell they are cut
## from is CutscenePlates'.
const SQUAD_SIZE := 3
## Where each figure stands relative to the squad's anchor, back to front.
const SQUAD_SLOTS: Array[Vector2] = [
	Vector2(0.0, 8.0),
	Vector2(30.0, -10.0),
	Vector2(58.0, 12.0),
]
## How far off the left edge the squad starts its march, and where it settles —
## a share of the width left of the property.
const MARCH_FROM := -280.0
const MARCH_TO := 0.24

const GRASS := Color(0.471, 0.784, 0.314)
const GRASS_DARK := Color(0.353, 0.651, 0.235)
const DUST := Color(0.941, 0.925, 0.886)

# --- pose, written every frame by CaptureCutscene -----------------------------

var unit: Unit
var terrain: TerrainType
## The property's atlas column and the two atlas rows the flip crosses between.
var prop_col := 0
var row_before := 0
var row_after := 0
## The capturer's faction accent, for the name-plate bar.
var accent := Color.WHITE
## 0 -> 1 as the plates slide in and their text appears.
var plate_p := 0.0
## Squad march, 0 -> 1: slides in from the left. Then `hop_advance` (0 -> 1)
## carries it the rest of the way to the building over the hops, and `squad_y`
## lifts it on each one. `hop_advance` is a fraction so the director never needs
## the control's pixel width.
var march_p := 0.0
var hop_advance := 0.0
var squad_y := 0.0
## The building's squash on a landing: wider and shorter, about its base.
var squash := 0.0
## 0 -> 1 white over-brighten as the flip flash peaks.
var brightness := 0.0
## Once true, the property is drawn in the capturer's row instead of the owner's.
var flipped := false
## One dust puff per hop, its own 0 -> 1; drawn at the building's base.
var dust := PackedFloat32Array()
## The cut-in's clock, for the squad's marching bob and its idle pose. Written by
## the director like everything else, so a posed still stays a pure function of
## the clock.
var clock := 0.0

## The idle clip, frame A then frame B, both cut at bind. Which one marches is
## this cut-in's own clock's answer (`_squad_now`) rather than the board's wall
## beat, so a posed still does not depend on when the shutter fired.
var _squad_figures: Array[AtlasTexture] = []


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Poses the stage for one capture. Called once, before the clock starts.
##
## Both rows arrive resolved off SideIdentity, never as team ints: the property
## starts in its owner's faction row and flips to the capturer's, and the squad
## marching up to it draws in that same capturer's row *by construction*. Deriving
## the squad's row separately is what once put red soldiers on an already-slate
## city — two palettes in one frame, and the whole of COM-10.
func bind(
	p_unit: Unit, p_terrain: TerrainType, p_col: int, p_owner_row: int, p_capturer_row: int
) -> void:
	unit = p_unit
	terrain = p_terrain
	prop_col = p_col
	row_before = p_owner_row
	row_after = p_capturer_row
	_squad_figures = [
		UnitSprite.figure_texture_for(p_unit.type, p_capturer_row, 0),
		UnitSprite.figure_texture_for(p_unit.type, p_capturer_row, 1),
	]


## The atlas row the marching squad is really drawn from, read back off the
## region `bind` baked. A read for the scenario driver's row check, which asks
## what is on screen rather than what was remembered — the stage stays draw-only.
func drawn_squad_row() -> int:
	if _squad_figures.is_empty():
		return -1
	return int(_squad_figures[0].region.position.y) / UnitSprite.SPRITE_H


func _draw() -> void:
	if unit == null or terrain == null:
		return
	var arena := _arena()
	_draw_sky(arena)
	_draw_ground(arena)
	_draw_property(arena)
	_draw_squad(arena)
	_draw_dust(arena)
	_draw_plates()


func _arena() -> Rect2:
	return CutscenePlates.arena(size)


# --- backdrop ----------------------------------------------------------------


func _draw_sky(arena: Rect2) -> void:
	var horizon := _horizon(arena)
	CutsceneScenery.draw_sky_gradient(self, arena, size.x, horizon, SKY_BANDS)
	CutsceneScenery.draw_cloud(
		self, Vector2(size.x * 0.22, arena.position.y + arena.size.y * 0.16), 1.0
	)
	CutsceneScenery.draw_cloud(
		self, Vector2(size.x * 0.72, arena.position.y + arena.size.y * 0.08), 0.66
	)


## A grass plane receding to the horizon: rows that lighten and thin toward the
## back, so the field reads as ground rather than a wall.
func _draw_ground(arena: Rect2) -> void:
	var horizon := _horizon(arena)
	var floor_y := arena.position.y + arena.size.y
	var depth := floor_y - horizon
	var y := horizon
	var row_h := depth * 0.06
	var toggle := 0
	while y < floor_y:
		var lit := lerpf(0.82, 1.0, clampf((y - horizon) / depth, 0.0, 1.0))
		var base := GRASS if toggle % 2 == 0 else GRASS_DARK
		draw_rect(
			Rect2(0.0, y, size.x, row_h + 1.0), Color(base.r * lit, base.g * lit, base.b * lit)
		)
		y += row_h
		row_h *= 1.5
		toggle += 1
	draw_rect(Rect2(0.0, horizon, size.x, 2.0), Color(GRASS_DARK.darkened(0.35), 0.9))
	draw_rect(Rect2(0.0, horizon - 1.0, size.x, 1.0), Color(1.0, 1.0, 1.0, 0.3))
	draw_rect(Rect2(0.0, floor_y - 16.0, size.x, 16.0), Color(0.0, 0.0, 0.0, 0.14))


func _horizon(arena: Rect2) -> float:
	return CutsceneScenery.horizon_of(arena, GROUND_RATIO)


# --- the property ------------------------------------------------------------


## The property: the cut-in's own scenery shapes in the colour of the board's
## cell, squashing on each mash and whiting out as it flips to the capturer's.
## The squash is a transform about the base, so a shape drawn in its own
## coordinates is squashed rather than each shape knowing about the mash.
func _draw_property(arena: Rect2) -> void:
	var base := _prop_base(arena)
	CutsceneScenery.draw_contact_shadow(self, base, PROP_PX * 0.46, 0.34)
	if not terrain.stands_in_cutin():
		_draw_paved_property(base)
		return
	var tint := CutsceneScenery.cell_tint(prop_col, _atlas_row(), ROOF_WINDOW)
	draw_set_transform(base, 0.0, Vector2(1.0 + squash * 0.4, 1.0 - squash))
	for block in PROP_BLOCKS:
		# Distance drains contrast here as it does on the ground bands, so the
		# blocks behind sit back rather than crowding the one in front.
		var lit := lerpf(0.86, 1.0, block.y)
		var shade := Color(tint.r * lit, tint.g * lit, tint.b * lit, 1.0)
		CutsceneScenery.draw_shape(
			self,
			terrain.cutin_scenery,
			Vector2(PROP_PX * block.x, -PROP_PX * PROP_DEPTH_PX * (1.0 - block.y)),
			PROP_PX * block.z,
			shade.lerp(Color.WHITE, brightness)
		)
	draw_set_transform(Vector2.ZERO)


## A property whose art is a surface rather than an object — no terrain that ships
## can be captured from one, but the stage draws whatever the board hands it, and
## a paving cell tiles rather than stands (TerrainType.stands_in_cutin).
func _draw_paved_property(base: Vector2) -> void:
	var w := PROP_PX * (1.0 + squash * 0.4)
	var h := PROP_PX * (1.0 - squash)
	var source := Rect2(
		prop_col * BattleView.TERRAIN_PX,
		_atlas_row() * BattleView.TERRAIN_PX,
		BattleView.TERRAIN_PX,
		BattleView.TERRAIN_PX
	)
	var tint := Color(1.0, 1.0, 1.0).lerp(Color(3.0, 3.0, 3.0), brightness)
	# Snapped: an atlas cell drawn at a continuously animated fractional size and
	# offset resamples itself every frame, so the building's own rows crawl through
	# the mash. Whole pixels hold the sampling still between landings, and the
	# squash still reads — the shape is 132 px tall and the rounding is one.
	var box := Rect2(Vector2(base.x - w * 0.5, base.y - h).round(), Vector2(w, h).round())
	draw_texture_rect_region(CutscenePlates.terrain_atlas(), box, source, tint)


## The atlas row the property is drawn from: the owner's faction row, swapped to
## the capturer's at the flip, and the untinted row on terrain that wears nobody's
## colours — CutsceneSide._atlas_row's rule, asked here for the same reason.
func _atlas_row() -> int:
	return SideIdentity.terrain_row(terrain, row_after if flipped else row_before)


func _prop_base(arena: Rect2) -> Vector2:
	return Vector2(size.x * PROP_CENTER, arena.position.y + arena.size.y * FEET_RATIO)


# --- the squad ---------------------------------------------------------------


## Three infantry, marching in from the left with a bob, then hopping onto the
## property. Drawn back to front so the frontmost figure overlaps the ones behind.
func _draw_squad(arena: Rect2) -> void:
	var anchor := _squad_anchor(arena)
	var bob := 0.0
	if march_p > 0.0 and march_p < 1.0:
		bob = -absf(sin(clock * 16.0)) * 5.0
	for i in range(SQUAD_SIZE - 1, -1, -1):
		var slot: Vector2 = SQUAD_SLOTS[i]
		var stagger := (
			-absf(sin(clock * 16.0 + i)) * 4.0 if (march_p > 0.0 and march_p < 1.0) else 0.0
		)
		var feet := anchor + slot + Vector2(0.0, squad_y + bob + stagger)
		_draw_shadow(Vector2(feet.x, anchor.y + slot.y), 1.0)
		_draw_figure(feet)


## The squad's back-left anchor: it slides in from off-screen as `march_p` rises,
## then `hop_advance` carries it right to just short of the building base.
func _squad_anchor(arena: Rect2) -> Vector2:
	var settled := size.x * MARCH_TO
	var target := size.x * PROP_CENTER - PROP_PX * 0.62
	var x := lerpf(MARCH_FROM, settled, march_p) + (target - settled) * hop_advance
	var y := arena.position.y + arena.size.y * FEET_RATIO
	return Vector2(x, y)


## Centred on the cell's own ground line, the combat cut-in's sibling rule: the
## cell's bottom rows are where the board's cast shadow spread to and the figure
## sheet has it subtracted, so an ellipse on the box's bottom edge sits below the
## feet it belongs under. See UnitSprite.CELL_GROUND_PX.
func _draw_shadow(ground: Vector2, strength: float) -> void:
	draw_set_transform(ground + Vector2(0.0, -UnitSprite.CELL_GROUND_PX), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 20.0, Color(CutscenePalette.GROUND_SHADOW, 0.3 * strength))
	draw_set_transform(Vector2.ZERO)


## One figure, standing on `feet` and facing the property (rightward). A hard
## offset shadow, then the art.
##
## `feet` is rounded because the squad art is drawn at 1:1 — CutscenePlates.
## FIGURE_PX is UnitSprite.SPRITE_W — so a whole-pixel origin puts one source
## texel on one screen pixel, while the march, the bob and the per-figure stagger
## otherwise walk the sprite through fractional offsets and shed a different row
## of it on every frame. The bob's amplitude is 5 px and the stagger's 4, so both
## still read; what goes is the shimmer inside them.
func _draw_figure(feet: Vector2) -> void:
	var box := Rect2(
		-CutscenePlates.FIGURE_PX * 0.5,
		-CutscenePlates.FIGURE_H,
		CutscenePlates.FIGURE_PX,
		CutscenePlates.FIGURE_H
	)
	var art := _squad_now()
	draw_set_transform(feet.round())
	draw_texture_rect(
		art,
		Rect2(box.position + Vector2(2.0, 3.0), box.size),
		false,
		Color(CutscenePalette.FIGURE_SHADOW, 0.4)
	)
	draw_texture_rect(art, box, false, Color.WHITE)
	draw_set_transform(Vector2.ZERO)


## Which pose of the idle clip the squad is marching in, off this cut-in's own
## clock at the board's ambient cadence.
func _squad_now() -> AtlasTexture:
	return CutscenePlates.figure_now(_squad_figures, clock)


## A fan of specks kicked up at the building's base on each landing.
func _draw_dust(arena: Rect2) -> void:
	var at := _prop_base(arena) + Vector2(-PROP_PX * 0.32, -6.0)
	for p in dust:
		if p <= 0.0 or p >= 1.0:
			continue
		for i in 6:
			var ang := PI + float(i) / 5.0 * PI
			var reach := lerpf(4.0, 44.0 + (i % 3) * 12.0, p)
			var s := CutsceneFx.ramp(p, [0.0, 0.4, 1.0], [6.0, 11.0, 3.0])
			var pos := at + Vector2(cos(ang) * reach, sin(ang) * reach * 0.5)
			draw_circle(pos, s * 0.5, Color(DUST, 1.0 - p))


# --- plates ------------------------------------------------------------------


func _draw_plates() -> void:
	if plate_p <= 0.0:
		return
	var slide := -40.0 * (1.0 - plate_p)
	draw_set_transform(Vector2(slide, 0.0))
	CutscenePlates.draw_frames(self, size, plate_p)
	_draw_name_row(Rect2(0.0, 0.0, size.x, CutscenePlates.TOP_H))
	_draw_terrain_row(Rect2(0.0, size.y - CutscenePlates.BOT_H, size.x, CutscenePlates.BOT_H))
	draw_set_transform(Vector2.ZERO)


func _draw_name_row(plate: Rect2) -> void:
	var font := get_theme_font(&"font", &"Label")
	draw_rect(Rect2(16.0, plate.position.y + 6.0, 4.0, 13.0), Color(accent, plate_p))
	var title := unit.type.display_name.to_upper()
	draw_string(
		font,
		Vector2(26.0, plate.position.y + 18.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(1.0, 1.0, 1.0, plate_p)
	)
	var name_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(
		font,
		Vector2(26.0 + name_width + 12.0, plate.position.y + 17.0),
		"CAPTURE",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color(CutscenePalette.GOLD, plate_p)
	)


func _draw_terrain_row(plate: Rect2) -> void:
	var font := get_theme_font(&"font", &"Label")
	var label := terrain.display_name.to_upper()
	draw_string(
		font,
		Vector2(20.0, plate.position.y + 14.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		Color(CutscenePalette.PLATE_TEXT, CutscenePalette.PLATE_TEXT.a * plate_p)
	)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	CutscenePlates.draw_stars(
		self,
		Vector2(20.0 + width + 14.0, plate.position.y + 10.0),
		CutscenePlates.STAR_STEP,
		mini(terrain.defense_stars, CutscenePlates.MAX_STARS),
		plate_p
	)
