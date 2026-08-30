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
## The destroyed cross: half its width, and its height. Two pixels of dark
## outline are grown off these, so the shape reads on any terrain.
const CROSS_HALF := 4.0
const CROSS_H := 7.0
const OUTLINE := 2.0
## The baseline the digits sit on.
const BASELINE := 5.0

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
	if mark.kind == PowerEffects.Kind.DESTROYED:
		_draw_cross(origin)
	if mark.pips <= 0:
		return
	var sign := "-" if falls(mark.kind) else "+"
	_draw_number(font, origin, "%s%d" % [sign, mark.pips])


## True for the marks that are bad news for whoever is standing there: their
## number is signed negative.
static func falls(kind: PowerEffects.Kind) -> bool:
	return kind in [PowerEffects.Kind.HARMED, PowerEffects.Kind.HINDERED]


## The one coloured thing a mark carries: critical red, for the one kind that is
## a loss. Every other kind is its signed number, the units under it blinking
## colourless so they stay their owner's.
func _draw_cross(origin: Vector2) -> void:
	var top_left := origin + Vector2(-CROSS_HALF, 0.0)
	var top_right := origin + Vector2(CROSS_HALF, 0.0)
	var bottom_left := origin + Vector2(-CROSS_HALF, CROSS_H)
	var bottom_right := origin + Vector2(CROSS_HALF, CROSS_H)
	draw_line(top_left, bottom_right, UiTheme.HARD_BORDER, OUTLINE + 1.0)
	draw_line(top_right, bottom_left, UiTheme.HARD_BORDER, OUTLINE + 1.0)
	draw_line(top_left, bottom_right, UiTheme.DANGER, OUTLINE)
	draw_line(top_right, bottom_left, UiTheme.DANGER, OUTLINE)


## Centred on the tile, the number being the whole mark now that no glyph stands
## beside it.
func _draw_number(font: Font, origin: Vector2, text: String) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_MARK).x
	BoardMark.count(self, font, origin + Vector2(-width * 0.5, BASELINE), text, int(OUTLINE))
