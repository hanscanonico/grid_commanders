class_name BoardCamera
extends RefCounted
## Where the board sits on screen: the cursor's cell, the camera's rung, the
## docking shift into the band between the two HUD bars, the limits that pin the
## view inside the map, and the screen point any cell lands on.
##
## Split out of BattleView, which draws the board itself. Every invariant here is
## about one property having one writer — `camera.zoom` is `_apply_zoom`'s and
## `camera.offset` is `_apply_board_offset`'s — and those are easier to keep true
## in a class that owns nothing else.
##
## Assigned-not-constructed, like BattleView and BattleOverlays: the view sets the
## node fields and calls `setup`, so this holds no reference back to it.

var camera: Camera2D
var cursor: Sprite2D
var map: MapData
## The campaign mission's card, which parks in a board corner and so has to be
## told where the cursor went.
var mission_panel: MissionObjectivesPanel

## The transient jitter the animator lays over the board's docking shift. Set —
## and tweened — by `BattleAnimator.shake_camera` rather than written to the
## camera, so the two can never be the same property's second owner; see
## `_apply_board_offset`, which composes both and is the only writer.
var shake_offset := Vector2.ZERO:
	set(value):
		shake_offset = value
		if camera != null:
			_apply_board_offset()

## The zoom level the player is playing at. BattleZoom owns it and its clamp; this
## is the last level it set, kept so a punch can ride over it.
var _resting_zoom := 1.0


## Frames the opening board. Call once, after the node fields are set.
func setup() -> void:
	_apply_camera_limits()


## Moves the cursor sprite and the camera that follows it. The interaction
## state that hangs off a cursor move stays in Battle.
##
## The camera lands on the cell rather than gliding to it. Cell centres are whole
## world pixels and every rung of the ladder is whole, so a camera parked on one
## draws the board on whole screen pixels — while `position_smoothing` spent the
## third of a second after every cursor step somewhere between two cells, which
## is a fractional rest by another name and the exact thing the whole texel
## argument forbids. A step is one cell; the board should arrive with the cursor.
func move_cursor_to(cell: Vector2i) -> void:
	cursor.position = BattleView.cell_center(cell)
	camera.position = cursor.position
	# The mission card parks in a board corner, so a cursor walking under it would
	# be working blind; it steps aside from here rather than polling for the cell.
	mission_panel.follow_cursor(
		cell, roundi(BattleView.TILE * camera.zoom.x), _board_origin_on_screen(), viewport_size()
	)


## The level the player is playing at, from BattleZoom, which owns it and clamps
## it against `min_zoom`.
func set_zoom(zoom: float) -> void:
	_resting_zoom = zoom
	_apply_zoom()


## The furthest out the player may zoom, with the backdrop filling whatever the
## map's aspect leaves over. On a map smaller than the viewport this sits above
## the default zoom, so a small map starts at its floor. Which rungs exist is
## `BattleZoom`'s — this only hands it the board it has to frame.
func min_zoom() -> float:
	return BattleZoom.floor_for(_board_viewport_size(), Vector2(map.size() * BattleView.TILE))


func screen_pos_for_cell(cell: Vector2i) -> Vector2:
	var world := BattleView.cell_center(cell) + Vector2(BattleView.TILE, -BattleView.TILE) / 2.0
	return (world - _screen_center()) * camera.zoom + viewport_size() / 2.0 + Vector2(6, 0)


## Where the board's first cell lands on screen, in the same transform
## `screen_pos_for_cell` uses and without its tooltip nudge.
func _board_origin_on_screen() -> Vector2:
	return -_screen_center() * camera.zoom + viewport_size() / 2.0


## The whole window. Public because the view measures the backdrop ring and clamps
## the damage forecast against it, and a second reading of the same viewport is
## exactly the drift this split exists to prevent.
func viewport_size() -> Vector2:
	return cursor.get_viewport().get_visible_rect().size


## **`camera.zoom` has one writer, and this is it**, and what it writes is a whole
## rung of `BattleZoom`'s ladder and nothing else. The combat flinch used to be
## composed in here as a multiplier; it is a scale on a rendered still now
## (`BoardPunch`), which is what keeps the camera on a rung for the whole match.
func _apply_zoom() -> void:
	camera.zoom = Vector2.ONE * _resting_zoom
	_apply_board_offset()
	_apply_camera_limits()


## Slides the camera so the cell it is centred on lands in the middle of the
## *board band* — the strip between the two docked HUD bars — rather than the
## middle of the window, which the bottom bar's larger height would put low.
##
## The bars are chrome outside the map, so the board's viewport is the window
## minus their combined height, computed from constants that never change while a
## match is running (hud handoff SPEC, "Fixed heights"). Applied on zoom because
## Camera2D.offset is world units: the same screen inset is a different world
## distance at each zoom level, and re-deriving it here is what keeps the band
## centred without the camera ever re-laying-out mid-turn.
##
## **`camera.offset` has one writer, and this is it.** The docking shift and the
## combat shake are two different things that both want that property; a shake
## written straight to the camera settles at Vector2.ZERO and takes the docking
## shift down with it, leaving the board half a bar low for the rest of the
## match. So the shake is asked for through `shake_offset` and composed here.
## Anything else that wants to move the camera belongs in this sum too.
func _apply_board_offset() -> void:
	camera.offset = Vector2(0, float(MobileDock.board_lift_px()) / camera.zoom.y) + shake_offset


## Camera limits pin the view inside the map. On an axis where the view shows
## more than the whole map they expand just enough to centre it instead,
## splitting the exposed backdrop evenly. Floor/ceil keeps the limit span at
## least the visible extent, so the camera is never pushed against one edge.
##
## The vertical limits carry one extra term. Godot clamps the camera against the
## *rendered* rect, which is the whole window, while the strip a player can
## actually see is the board band; pushing the limits out by half the bars' world
## height makes the engine's clamp land on the band's edges instead, so the board
## still reaches the chrome rather than stopping short of it and showing a seam
## of backdrop.
func _apply_camera_limits() -> void:
	var map_px := Vector2(map.size() * BattleView.TILE)
	var extra := ((_board_viewport_size() / camera.zoom.x - map_px) / 2.0).max(Vector2.ZERO)
	var hidden := float(MobileDock.chrome_h()) / (2.0 * camera.zoom.y)
	camera.limit_left = floori(-extra.x)
	camera.limit_top = floori(-extra.y - hidden)
	camera.limit_right = ceili(map_px.x + extra.x)
	camera.limit_bottom = ceili(map_px.y + extra.y + hidden)


## The strip of window the board actually gets: everything the two docked HUD
## bars do not cover. Derived from constants, so it answers the same on every
## call in a match and the camera is never re-framed mid-turn.
func _board_viewport_size() -> Vector2:
	return viewport_size() - Vector2(0, MobileDock.chrome_h())


## The world point the middle of the screen shows, clamped the way the engine
## clamps the camera itself so UI placed near a map edge lands on the tile it
## points at rather than off it.
##
## `camera.offset` is part of the answer: it is what pushes the board down into
## the band between the bars, so a transient overlay measured against the screen
## centre has to carry the same shift or it would sit a bar's height off the tile
## it points at.
func _screen_center() -> Vector2:
	return _camera_target() + camera.offset


func _camera_target() -> Vector2:
	var view_size := viewport_size()
	return Vector2(
		clampf(
			camera.position.x,
			camera.limit_left + view_size.x / (2.0 * camera.zoom.x),
			camera.limit_right - view_size.x / (2.0 * camera.zoom.x)
		),
		clampf(
			camera.position.y,
			camera.limit_top + view_size.y / (2.0 * camera.zoom.y),
			camera.limit_bottom - view_size.y / (2.0 * camera.zoom.y)
		)
	)
