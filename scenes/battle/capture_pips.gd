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

## Cell -> capture points still owed.
var _pips: Dictionary = {}


## Replaces everything drawn. An empty dictionary clears, so callers never need a
## separate hide — the same contract the overlay painters have.
func set_pips(pips: Dictionary) -> void:
	_pips = pips
	queue_redraw()


func _draw() -> void:
	if _pips.is_empty():
		return
	var font := UiTheme.stat(true)
	for cell: Vector2i in _pips:
		_draw_badge(font, Vector2(cell * TILE) + ORIGIN, str(_pips[cell]))


## A green flag and the count, both outlined rather than boxed.
##
## The design reference set the chip on a filled ink panel. At a 44-pixel tile
## that panel is trim; at this board's 16 it covers the building being captured,
## so the player can no longer see what the number is counting down. Outlined
## marks carry on any terrain and leave the tile readable underneath — the badge
## idiom UnitSprite already wears for HP and fuel, for the same reason.
func _draw_badge(font: Font, origin: Vector2, text: String) -> void:
	for mark: Rect2 in [POLE, PENNANT]:
		draw_rect(Rect2(origin + mark.position, mark.size).grow(1.0), UiTheme.HARD_BORDER)
	for mark: Rect2 in [POLE, PENNANT]:
		draw_rect(Rect2(origin + mark.position, mark.size), UiTheme.CAPTURE)
	var pen := origin + Vector2(TEXT_X, BASELINE)
	draw_string_outline(
		font,
		pen,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiTheme.SIZE_MICRO,
		OUTLINE,
		UiTheme.HARD_BORDER
	)
	draw_string(font, pen, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_MICRO, UiTheme.WHITE)
