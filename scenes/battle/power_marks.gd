class_name PowerMarks
extends Node2D
## The board's half of a fired Command Power: a mark over every unit it touched,
## lifting off the tile and fading as it goes.
##
## Dumb, like CapturePips and UnitSprite: the marks are worked out by
## `PowerEffects` and handed over already through the fog gate, and this only
## draws them. It never reads GameState and never asks a commander anything.
##
## Outlined marks rather than filled chips, for the reason BoardMark states.

const TILE := BattleView.TILE

## Where a mark sits: centred on the tile and clear of its top edge, which is the
## band nothing else draws in — UnitSprite hangs HP below and right of centre,
## fuel below and left, and CapturePips takes the top-left corner.
const ORIGIN := Vector2(TILE * 0.5, -6.0)
## How far a mark travels while it fades, in world pixels.
const LIFT := 7.0
## The arrow: half its width, and its height. Two pixels of dark outline are
## grown off these, so the shape reads on any terrain.
const ARROW_HALF := 4.0
const ARROW_H := 7.0
const OUTLINE := 2.0
## Where the digits sit beside the arrow, and the baseline they sit on.
const TEXT_X := 5.0
const BASELINE := 5.0
## The arrow steps left by this much when a number is drawn beside it, so the
## pair reads as centred on the tile rather than the arrow alone.
const NUMBER_SHIFT := 4.0

## 0 at rest, 1 when the mark has finished travelling. Tweened by BattleAnimator.
var rise: float = 0.0:
	set(value):
		rise = value
		queue_redraw()

var _marks: Array[PowerEffects.Mark] = []


## Replaces everything drawn and puts the lift back at rest. An empty list
## clears, so callers never need a separate hide — the same contract the overlay
## painters have.
func set_marks(marks: Array[PowerEffects.Mark]) -> void:
	_marks = marks
	modulate.a = 1.0
	rise = 0.0
	queue_redraw()


## Takes everything off the board again, which is where a finished lift lands.
func clear_marks() -> void:
	_marks = []
	queue_redraw()


func _draw() -> void:
	if _marks.is_empty():
		return
	var font := UiTheme.stat(true)
	var lift := Vector2(0.0, -LIFT * rise)
	for mark in _marks:
		_draw_mark(font, Vector2(mark.cell * TILE) + ORIGIN + lift, mark)


func _draw_mark(font: Font, origin: Vector2, mark: PowerEffects.Mark) -> void:
	var colour := _colour_for(mark.kind)
	var pen := origin - Vector2(NUMBER_SHIFT if mark.pips > 0 else 0.0, 0.0)
	if mark.kind == PowerEffects.Kind.DESTROYED:
		_draw_cross(pen, colour)
	else:
		_draw_arrow(pen, colour, falls(mark.kind))
	if mark.pips <= 0:
		return
	var sign := "-" if falls(mark.kind) else "+"
	_draw_number(font, pen + Vector2(TEXT_X, BASELINE), "%s%d" % [sign, mark.pips])


## What each kind is painted in. Health speaks the board's own two colours —
## capture green for a pip back, critical red for one lost — while stores take the
## amber every ammo bar and charge meter is already drawn with, a refreshed unit
## takes the reach overlay's blue because that is what it just got back, and a
## doctrine mark takes the gold that means "chosen" everywhere else in the shell.
static func _colour_for(kind: PowerEffects.Kind) -> Color:
	match kind:
		PowerEffects.Kind.HEALED:
			return UiTheme.CAPTURE
		PowerEffects.Kind.RESUPPLIED:
			return UiTheme.AMMO
		PowerEffects.Kind.REFRESHED:
			return Color(OverlayPalette.MOVE, 1.0)
		PowerEffects.Kind.EMPOWERED:
			return UiTheme.SELECT_GOLD
		_:
			return UiTheme.DANGER


## True for the marks that are bad news for whoever is standing there: the arrow
## points down and a number is signed negative.
static func falls(kind: PowerEffects.Kind) -> bool:
	return kind in [PowerEffects.Kind.HARMED, PowerEffects.Kind.HINDERED]


func _draw_arrow(origin: Vector2, colour: Color, down: bool) -> void:
	var tip := origin + Vector2(0.0, ARROW_H if down else 0.0)
	var base_y := origin.y + (0.0 if down else ARROW_H)
	var shape := PackedVector2Array(
		[tip, Vector2(origin.x - ARROW_HALF, base_y), Vector2(origin.x + ARROW_HALF, base_y)]
	)
	draw_polyline(shape + PackedVector2Array([tip]), UiTheme.HARD_BORDER, OUTLINE)
	draw_colored_polygon(shape, colour)


func _draw_cross(origin: Vector2, colour: Color) -> void:
	var top_left := origin + Vector2(-ARROW_HALF, 0.0)
	var top_right := origin + Vector2(ARROW_HALF, 0.0)
	var bottom_left := origin + Vector2(-ARROW_HALF, ARROW_H)
	var bottom_right := origin + Vector2(ARROW_HALF, ARROW_H)
	draw_line(top_left, bottom_right, UiTheme.HARD_BORDER, OUTLINE + 1.0)
	draw_line(top_right, bottom_left, UiTheme.HARD_BORDER, OUTLINE + 1.0)
	draw_line(top_left, bottom_right, colour, OUTLINE)
	draw_line(top_right, bottom_left, colour, OUTLINE)


func _draw_number(font: Font, pen: Vector2, text: String) -> void:
	BoardMark.count(self, font, pen, text, int(OUTLINE))
