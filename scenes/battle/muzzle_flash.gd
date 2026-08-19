class_name MuzzleFlash
extends Node2D
## The board's half of a shot: a star at the firing unit's muzzle, thrown toward
## what it is shooting at, in the colours of the weapon that fired.
##
## The cut-in has flashed a muzzle since BA1, but the map path it stands in for —
## battle animations off, an exchange watched at speed — showed the firing unit
## nothing at all: the target flinched and whatever hit it was never on screen.
## This is the cut-in's flash at the board's scale, and it is the only thing the
## map path draws for the shooter.
##
## Dumb, like CapturePips and PowerMarks: BattleAnimator hands over two cells and
## the BattleStyle the exchange already named, and this only draws them. It reads
## no rule, asks no damage chart and decides nothing about the shot — which weapon
## fired is a snapshot fact off CombatResult (battle-animations plan D1).
##
## Outlined whole-pixel marks rather than a soft glow, for the reason CapturePips
## wears them: on a 16-pixel tile the flash has to read on any terrain, and the
## board is pixel art — so the star shrinks a pixel at a time rather than fading.

## A style's `muzzle` is authored in the atlas's own pixels, which is what the
## cut-in draws its figures at; the board draws the same art at UnitSprite's
## scale, so the same number arrives here through that ratio — one flash at two
## scales, and no second opinion about how big a cannon's is. It arrives as the
## star's **width** where the cut-in spends it as a radius, because the cut-in's
## flash is a soft disc that has all but faded by its rim while this one is opaque
## to its last pixel: read as a radius it covers the shooter it belongs to.
const BOARD_SCALE := UnitSprite.SPRITE_SCALE * 0.5
## How far out of the firing cell's centre the star sits, toward the target: clear
## of the sprite's middle, still inside its own tile.
const REACH := 6.0
## Arm and core thickness, and the dark edge every board mark carries.
const ARM := 2.0
const CORE := 2.0
const OUTLINE := 1.0

## 1.0 the moment the shot leaves, 0.0 at rest. Tweened by BattleAnimator, and
## quantised to whole pixels on the way to the screen — see `reach_for`.
var spark: float = 0.0:
	set(value):
		spark = value
		queue_redraw()

var _at := Vector2.ZERO
var _radius: float = 0.0
var _tint := Color.WHITE


## Puts a star at `from`'s muzzle, pointed at `at`. Replaces whatever was drawn;
## `clear_shot` is the only other writer, so a flash can never outlive its shot.
func show_shot(from: Vector2i, at: Vector2i, style: BattleStyle) -> void:
	var line := Vector2(at - from)
	var toward := line.normalized() if line != Vector2.ZERO else Vector2.RIGHT
	_at = (BattleView.cell_center(from) + toward * REACH).round()
	_radius = style.muzzle * BOARD_SCALE
	_tint = style.tint
	spark = 1.0


func clear_shot() -> void:
	spark = 0.0


## How far the arms reach right now, in whole world pixels. Rounded rather than
## tweened smoothly: a star drawn on half a pixel shimmers against art that is
## drawn on whole ones, and at these radii the round is what makes the flash read
## as two beats — full, halved, gone.
static func reach_for(radius: float, at_spark: float) -> float:
	return roundf(radius * clampf(at_spark, 0.0, 1.0))


## The star's two bars, as whole-pixel rects centred on the muzzle. Pure, so the
## geometry is checked without a scene (the path arrow's split, for the same
## reason). `ARM` and `CORE` are even so that centring stays on whole pixels.
static func arms(at: Vector2, reach: float) -> Array[Rect2]:
	if reach < 1.0:
		return []
	var span := reach * 2.0 + ARM
	var bars: Array[Rect2] = [
		Rect2(at - Vector2(span, ARM) * 0.5, Vector2(span, ARM)),
		Rect2(at - Vector2(ARM, span) * 0.5, Vector2(ARM, span)),
	]
	return bars


## The white heart of the star, once there are arms standing out past it: the
## smallest spark the board draws is all flame, and a core in it would be the
## whole star.
static func core_mark(at: Vector2, reach: float) -> Array[Rect2]:
	if reach <= 1.0:
		return []
	return [Rect2(at - Vector2(CORE, CORE) * 0.5, Vector2(CORE, CORE))]


func _draw() -> void:
	var reach := reach_for(_radius, spark)
	var bars := arms(_at, reach)
	if bars.is_empty():
		return
	var heart := core_mark(_at, reach)
	for mark in bars + heart:
		draw_rect(mark.grow(OUTLINE), UiTheme.HARD_BORDER)
	for mark in bars:
		draw_rect(mark, _tint)
	for mark in heart:
		draw_rect(mark, UiTheme.WHITE)
