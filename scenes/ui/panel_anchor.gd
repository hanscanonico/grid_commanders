class_name PanelAnchor
extends RefCounted
## Where a panel floating over the board opens beside a cell: a whole tile clear of
## it, on the side away from what the player is deciding about, so the menu and the
## forecast never sit on the units the choice is about. The side flips when it has
## no room, and the answer stays inside the band the docked bars leave.
##
## Screen geometry only — `BattleView.beside` measures the cell, and this places a
## panel of a given size against it.

## The cell and a tile of margin either side of it, in screen pixels.
var zone: Rect2
## +1 opens to the right of `zone`, -1 to its left.
var side := 1


func _init(p_zone: Rect2, p_side: int) -> void:
	zone = p_zone
	side = 1 if p_side >= 0 else -1


## The anchor beside `cell` as `camera` draws it. It opens on the side away from
## the cells in `away`, read in screen space so a turned 3D board answers the
## same; with nothing to keep clear of it opens toward the middle of the screen,
## where there is room.
static func beside(camera: BoardCamera, cell: Vector2i, away: Array[Vector2i] = []) -> PanelAnchor:
	var corner := camera.screen_pos_for_cell(cell)  # the cell's top-right, on screen
	var tile := maxf(
		corner.distance_to(camera.screen_pos_for_cell(cell + Vector2i.RIGHT)),
		corner.distance_to(camera.screen_pos_for_cell(cell + Vector2i.DOWN))
	)
	var zone := Rect2(corner.x - 2.0 * tile, corner.y, 3.0 * tile, tile)
	var lean := 0.0
	for other in away:
		lean += camera.screen_pos_for_cell(other).x - corner.x
	if away.is_empty() or is_zero_approx(lean):
		lean = corner.x - camera.viewport_size().x / 2.0
	return PanelAnchor.new(zone, -1 if lean > 0.0 else 1)


## The top-left corner a panel of `size` takes inside `band`; `rise` lifts it off
## the top of the cell's row (zero lines its top up with the cell's).
func place(size: Vector2, band: Rect2, rise: float = 0.0) -> Vector2:
	var right := zone.end.x
	var left := zone.position.x - size.x
	var x := right if side > 0 else left
	if side > 0 and right + size.x > band.end.x and left >= band.position.x:
		x = left
	elif side < 0 and left < band.position.x and right + size.x <= band.end.x:
		x = right
	var pos := Vector2(x, zone.position.y - rise)
	return pos.clamp(band.position, (band.end - size).max(band.position))
