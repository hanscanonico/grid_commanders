class_name CapturePips
extends Node2D
## The capture-progress badge: how many points a property still owes before it
## changes hands, pinned to the tile itself.
##
## The number was already in the game — the bottom bar prints it for whatever tile
## the cursor is on — but reading it meant walking the cursor onto every contested
## property in turn. On the tile it is read at a glance, which is the point: a
## capture is the one action that takes more than one turn to finish, so what it
## still owes is what the next turn gets planned around.
##
## Dumb, like UnitSprite: Battle hands it the cells and the numbers, already
## through the fog gate, and this only draws them. It never reads GameState and
## never asks CaptureCommand.capture_strength — the count is a presentation split
## of a number the sim already holds (capture-animation plan D1).

const TILE := BattleView.TILE

## The badge sits in the tile's top-left, which is the corner left over:
## UnitSprite hangs its HP badge below and right of centre and its fuel badge
## below and left, and the capturing unit is standing on this very cell.
const ORIGIN := Vector2(1, 1)
## The flag: a pole and a pennant, each outlined a pixel so it carries onto any
## terrain. World pixels, from ORIGIN. The pole is two wide rather than one
## because a one-pixel mark with a pixel of outline either side is an outline.
const POLE := Rect2(0, 0, 2, 6)
const PENNANT := Rect2(2, 0, 3, 3)
## Where the digits start, and the baseline they sit on.
const TEXT_X := 6.0
const BASELINE := 6.0
## Outline weight on the digits, matching unit_sprite.tscn's HP badge.
const OUTLINE := 2

## How far out the flip flash's own spark reaches, and how far in world pixels
## its centre sits from a badge's ORIGIN — the pennant's own middle.
const FLIP_REACH := 5.0
const FLIP_AT := PENNANT.position + PENNANT.size * 0.5

## Cell -> capture points still owed.
var _pips: Dictionary[Vector2i, int] = {}

## 1.0 the moment a repaint reaches the viewer, 0.0 at rest — MuzzleFlash's own
## shape, so the property's pennant catches the same spark a shot does.
## Tweened by BattleAnimator.
var flip: float = 0.0:
	set(value):
		flip = value
		queue_redraw()
var _flip_at := Vector2i.ZERO


## Replaces everything drawn. An empty dictionary clears, so callers never need a
## separate hide — the same contract the overlay painters have.
func set_pips(pips: Dictionary[Vector2i, int]) -> void:
	_pips = pips
	queue_redraw()


## Marks `cell`'s pennant as having just changed hands — BattleView emits the
## fact only when a repaint actually presents to the viewer, fog-deferred
## captures included. Replaces whatever was flashing; `clear_flip` is the only
## other writer, the way `clear_shot` is MuzzleFlash's.
func show_flip(cell: Vector2i) -> void:
	_flip_at = cell
	flip = 1.0


func clear_flip() -> void:
	flip = 0.0


func _draw() -> void:
	var font := UiTheme.stat(true)
	for cell: Vector2i in _pips:
		_draw_badge(font, Vector2(cell * TILE) + ORIGIN, str(_pips[cell]))
	if flip > 0.0:
		_draw_flip(Vector2(_flip_at * TILE) + ORIGIN + FLIP_AT)


## The flip's own spark, over the pennant it belongs to — MuzzleFlash's star at
## a smaller reach and CAPTURE's own hue, so the flash reads as this pennant
## catching the light rather than a foreign mark landing on it.
func _draw_flip(at: Vector2) -> void:
	var reach := MuzzleFlash.reach_for(FLIP_REACH, flip)
	var bars := MuzzleFlash.arms(at, reach)
	if bars.is_empty():
		return
	var heart := MuzzleFlash.core_mark(at, reach)
	for mark in bars + heart:
		draw_rect(mark.grow(1.0), UiTheme.HARD_BORDER)
	for mark in bars:
		draw_rect(mark, UiTheme.CAPTURE)
	for mark in heart:
		draw_rect(mark, UiTheme.WHITE)


## A green flag and the count, both outlined rather than boxed — BoardMark says
## why, and draws the count.
func _draw_badge(font: Font, origin: Vector2, text: String) -> void:
	for mark: Rect2 in [POLE, PENNANT]:
		draw_rect(Rect2(origin + mark.position, mark.size).grow(1.0), UiTheme.HARD_BORDER)
	for mark: Rect2 in [POLE, PENNANT]:
		draw_rect(Rect2(origin + mark.position, mark.size), UiTheme.CAPTURE)
	BoardMark.count(self, font, origin + Vector2(TEXT_X, BASELINE), text, OUTLINE)
