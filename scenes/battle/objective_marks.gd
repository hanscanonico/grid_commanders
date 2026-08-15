class_name ObjectiveMarks
extends Node2D
## The mission's targets, pinned to the squares they are about: a ring on the
## depot the card is telling you to take.
##
## The card names its ground in words — "the crossroads base", "the northern
## relay" — because that is how a mission reads. Words alone leave the player
## hunting a 20-wide board for which building was meant, which is a puzzle the
## mission never intended to set: an objective is the one thing in the game the
## player is *told* rather than has to discover.
##
## Dumb, like CapturePips and UnitSprite: Battle hands over the cells and this
## only draws them. It reads no mission, no objective and no state, so what is
## marked and what is drawn can never disagree.

const TILE := BattleView.TILE

## The mark sits in the tile's top-right, the last free corner: CapturePips takes
## the top-left and UnitSprite hangs its HP and fuel badges along the bottom.
const CENTER := Vector2(TILE - 3.5, 3.5)
## Half-widths of the ring, outer then inner — a diamond outline rather than a
## disc, and a badge rather than a banner: at a 16-pixel tile anything bigger
## covers the very building the mission is pointing at, which is the mistake the
## capture chip was already redrawn once to avoid.
const OUTER := 3.0
const INNER := 1.0

var _cells: Array[Vector2i] = []


## Replaces everything drawn. An empty list clears, the same contract every
## painter on this board has.
func set_cells(cells: Array[Vector2i]) -> void:
	_cells = cells
	queue_redraw()


func _draw() -> void:
	for cell in _cells:
		var center := Vector2(cell * TILE) + CENTER
		draw_colored_polygon(_diamond(center, OUTER + 1.0), UiTheme.HARD_BORDER)
		draw_colored_polygon(_diamond(center, OUTER), UiTheme.AMMO)
		draw_colored_polygon(_diamond(center, INNER), UiTheme.HARD_BORDER)


static func _diamond(center: Vector2, radius: float) -> PackedVector2Array:
	return PackedVector2Array(
		[
			center + Vector2(0, -radius),
			center + Vector2(radius, 0),
			center + Vector2(0, radius),
			center + Vector2(-radius, 0),
		]
	)
