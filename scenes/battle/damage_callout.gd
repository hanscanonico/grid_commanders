class_name DamageCallout
extends Node2D
## The map path's damage number — PowerMarks' own rise-then-fade shape, and its
## neighbour above the fog layer for the same reason: the number lifts into the
## tile above the defender, which is often ground the board is still hiding, and
## a figure the fog dims is a figure that has to be read twice. The cut-in
## already prints what a hit cost the side that took it; the map path never
## has, which is what an exchange watched without the theatre showed: a flinch
## and no number.
##
## Dumb, like PowerMarks: BattleAnimator hands over the cell and the amount —
## displayed HP a hit cost, off the result's own snapshot — and this only
## draws and lifts it, off `BoardMark.count`. Only ever posed on the branch
## that already means the cut-in was gated out for this exchange; while the
## cut-in plays it prints its own callout, so the two are never both up.

const TILE := BattleView.TILE
## Where the number starts, and how far it lifts as `rise` runs 0 -> 1 —
## PowerMarks' own two constants, read the same way.
const ORIGIN := Vector2(TILE * 0.5, -6.0)
const LIFT := 10.0
const OUTLINE := 2

## 0 at rest, 1 when the number has finished lifting. Tweened by
## BattleAnimator, alongside a separate fade on `modulate:a` — the exact
## two-tween shape `show_power_effects` already drives PowerMarks with.
var rise: float = 0.0:
	set(value):
		rise = value
		queue_redraw()

var _cell := Vector2i.ZERO
var _amount := 0


## Puts the number over `cell` and puts the lift back at rest. Replaces
## whatever was showing; `clear_hit` is the only other writer.
func show_hit(cell: Vector2i, amount: int) -> void:
	_cell = cell
	_amount = amount
	modulate.a = 1.0
	rise = 0.0


func clear_hit() -> void:
	_amount = 0
	queue_redraw()


func _draw() -> void:
	if _amount <= 0:
		return
	var font := UiTheme.stat(true)
	var lift := Vector2(0.0, -LIFT * rise)
	var text := "-%d" % _amount
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_MARK).x
	BoardMark.count(
		self,
		font,
		Vector2(_cell * TILE) + ORIGIN + lift + Vector2(-width * 0.5, 0.0),
		text,
		OUTLINE
	)
