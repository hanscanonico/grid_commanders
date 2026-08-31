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
## Grown off a shape rather than drawn over it, so a spike keeps its colour.
const OUTLINE := 2.0
## The blast a struck cell goes up in: the flame's spikes, how far it opens from
## and to in world pixels, and how deep the notches between the spikes cut. It
## opens from wide enough to read red at rest, which is where a capture poses it.
const BURST_SPIKES := 9
const BURST_FROM := 8.0
const BURST_TO := 13.0
const BURST_NOTCH := 0.55
## How far the flame turns while it opens, as a share of the gap between two of
## its outline's points, and how much of its red it has lost by the end.
const BURST_TWIST := 0.5
const BURST_FADE := 0.45
## The white core inside the flame, as a fraction of it, and the beat on the
## lift by which it has burnt out.
const CORE_RADIUS := 0.45
const CORE_OUT := 0.5
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
		var tile := Vector2(mark.cell * TILE)
		if mark.kind == PowerEffects.Kind.DESTROYED:
			_draw_burst(tile + Vector2(TILE, TILE) * 0.5)
		if mark.pips > 0:
			var sign := "-" if falls(mark.kind) else "+"
			_draw_number(font, tile + ORIGIN + lift, "%s%d" % [sign, mark.pips])


## True for the marks that are bad news for whoever is standing there: their
## number is signed negative.
static func falls(kind: PowerEffects.Kind) -> bool:
	return kind in [PowerEffects.Kind.HARMED, PowerEffects.Kind.HINDERED]


## The one coloured thing a mark carries: the blast a struck cell goes up in,
## sitting on the tile rather than lifting with the numbers, since that is where
## it happened. Every other kind is its signed number, the units under it
## blinking colourless so they stay their owner's.
##
## The meteor's vocabulary at a cell's scale — critical red under a dark rule,
## with a white core that burns out first — so the strike and what it took read
## as one event.
func _draw_burst(centre: Vector2) -> void:
	var radius := lerpf(BURST_FROM, BURST_TO, rise)
	var fade := 1.0 - rise * BURST_FADE
	draw_colored_polygon(_burst_points(centre, radius + OUTLINE), Color(UiTheme.HARD_BORDER, fade))
	draw_colored_polygon(_burst_points(centre, radius), Color(UiTheme.DANGER, fade))
	var core := 1.0 - minf(rise / CORE_OUT, 1.0)
	if core > 0.0:
		draw_circle(centre, radius * CORE_RADIUS, Color(UiTheme.WHITE, core))


## The flame's outline: BURST_SPIKES points out at `radius` with a notch between
## each pair, turned as it opens so it never poses the same shape twice. Drawn
## twice per burst — once grown by OUTLINE for the dark rule under it.
func _burst_points(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var step := TAU / float(BURST_SPIKES * 2)
	var twist := step * BURST_TWIST * rise
	for i in BURST_SPIKES * 2:
		var reach := radius if i % 2 == 0 else radius * BURST_NOTCH
		points.append(centre + Vector2.RIGHT.rotated(twist + step * float(i)) * reach)
	return points


## Centred on the tile, the number being the whole mark now that no glyph stands
## beside it.
func _draw_number(font: Font, origin: Vector2, text: String) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_MARK).x
	BoardMark.count(self, font, origin + Vector2(-width * 0.5, BASELINE), text, int(OUTLINE))
