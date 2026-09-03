class_name DeathBlast
extends Node2D
## The board's death blast: a burst over the tile a unit just died on — the
## map path's own answer to the cut-in's kill blast, and MuzzleFlash's sibling.
##
## Dumb, like MuzzleFlash and CapturePips: BattleAnimator hands over the cell
## and the BattleStyle the killing shot already named (the weapon slot off the
## result's own snapshot, never re-decided), and this only draws it.
##
## Whole-pixel outlined marks rather than a soft fireball, for MuzzleFlash's own
## reason: on a 16-pixel tile a burst that fades a pixel at a time reads on any
## terrain, and the board is pixel art. Reuses MuzzleFlash's own star geometry
## rather than a second copy of it — a blast is the same outlined mark, only
## bigger and growing instead of shrinking.

## How far the ring reaches at its widest, in world pixels.
const RING := 9.0

## 0 at rest, 1 through the burst's whole run — a single travel progress, the
## way CutsceneFx's own beats are: the ring's reach and its fade both come off
## this one number, so the two can never drift out of step.
var blast: float = 0.0:
	set(value):
		blast = value
		queue_redraw()

var _at := Vector2.ZERO
var _tint := Color.WHITE


## Puts a burst on `cell`, in the colours of the shot that just ended it.
## Replaces whatever was drawn; `clear_blast` is the only other writer.
func show_blast(cell: Vector2i, style: BattleStyle) -> void:
	_at = BattleView.cell_center(cell)
	_tint = style.tint
	blast = 0.0


func clear_blast() -> void:
	blast = 0.0


## How far the ring has reached, off the one progress value. Pure, so the
## geometry is checked without a scene, the way MuzzleFlash.reach_for is.
static func reach_for(progress: float) -> float:
	return roundf(RING * clampf(progress, 0.0, 1.0))


## How solid it still is at that same progress — out fast, thinning as it
## goes, rather than snapping to size and only then dimming.
static func alpha_for(progress: float) -> float:
	return clampf(1.0 - progress, 0.0, 1.0)


func _draw() -> void:
	MuzzleFlash.draw_star(self, _at, reach_for(blast), _tint, alpha_for(blast))
