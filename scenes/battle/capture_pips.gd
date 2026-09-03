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

## The flip flash's own spark: where it sits in the tile, and how far it reaches.
## Anchored on the tile rather than on a badge, because the badge is gone by the
## time the flash runs — a completed capture clears the cell's progress, and a
## fallen army's forfeited cities never had one. Over the building's upper half,
## where a property wears its colours, and short enough that the star and its
## outline stay inside the 16 pixels the tile owns.
const FLIP_AT := Vector2(TILE * 0.5, TILE * 0.5 - 2.0)
const FLIP_REACH := 4.0

## Cell -> capture points still owed.
var _pips: Dictionary[Vector2i, int] = {}

## Cell -> how bright that property's flip flash still is: 1.0 the moment a
## repaint reaches the viewer, spent when it reaches 0.0 — MuzzleFlash's own
## shape, so a property changing hands catches the same spark a shot does. A
## dictionary rather than one slot because a single repaint pass can flip many
## properties at once (a scout revealing several fog-deferred captures, an army
## falling and forfeiting its cities), and each one has its own flash to run.
## Driven by BattleAnimator, one tween a cell.
var _flips: Dictionary[Vector2i, float] = {}


## Replaces everything drawn. An empty dictionary clears, so callers never need a
## separate hide — the same contract the overlay painters have.
func set_pips(pips: Dictionary[Vector2i, int]) -> void:
	_pips = pips
	queue_redraw()


## Marks `cell`'s property as having just changed hands — BattleView emits the
## fact only when a repaint actually presents to the viewer, fog-deferred
## captures included. Starts that one cell's flash at full; `set_flip` runs it
## down and `clear_flip` takes it off, the way `clear_shot` is MuzzleFlash's.
func show_flip(cell: Vector2i) -> void:
	set_flip(1.0, cell)


## One cell's flash progress — the tween's own writer, and bound-argument order
## because `tween_method` hands the value in first.
func set_flip(progress: float, cell: Vector2i) -> void:
	_flips[cell] = progress
	queue_redraw()


func clear_flip(cell: Vector2i) -> void:
	_flips.erase(cell)
	queue_redraw()


func _draw() -> void:
	var font := UiTheme.stat(true)
	for cell: Vector2i in _pips:
		_draw_badge(font, Vector2(cell * TILE) + ORIGIN, str(_pips[cell]))
	for cell: Vector2i in _flips:
		_draw_flip(Vector2(cell * TILE) + FLIP_AT, _flips[cell])


## The flip's own spark, over the property that just changed hands —
## MuzzleFlash's star at a smaller reach and CAPTURE's own hue, so the flash
## reads as this building catching the light rather than a foreign mark landing
## on it. Drawn off the cell alone, so it plays whether or not the tile still
## carries a progress badge.
func _draw_flip(at: Vector2, progress: float) -> void:
	MuzzleFlash.draw_star(self, at, MuzzleFlash.reach_for(FLIP_REACH, progress), UiTheme.CAPTURE)


## A green flag and the count, both outlined rather than boxed — BoardMark says
## why, and draws the count.
func _draw_badge(font: Font, origin: Vector2, text: String) -> void:
	for mark: Rect2 in [POLE, PENNANT]:
		draw_rect(Rect2(origin + mark.position, mark.size).grow(1.0), UiTheme.HARD_BORDER)
	for mark: Rect2 in [POLE, PENNANT]:
		draw_rect(Rect2(origin + mark.position, mark.size), UiTheme.CAPTURE)
	BoardMark.count(self, font, origin + Vector2(TEXT_X, BASELINE), text, OUTLINE)
