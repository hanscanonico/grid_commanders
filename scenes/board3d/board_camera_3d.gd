class_name BoardCamera3D
extends RefCounted
## Where the 3D board is looked at from: a camera on a fixed pitch, orbiting the
## cursor in quarter turns, pulled back by the 2D board's own zoom rung.
##
## The 2D camera stays the authority on *what* is framed — the cursor it rides
## and the rung BattleZoom settled on — and this only answers from where. So a
## zoom key, a pinch and the next-unit jump reach both boards by one route, and
## flipping boards mid-turn keeps the same cell in the middle of the screen.
##
## It frames with slack, the way a tactics camera does: the cursor roams a box in
## the middle of the view and the camera only moves to keep it inside. Centring on
## every cursor step would make the mouse chase itself — hovering moves the cursor,
## the camera recentres, and a new cell slides under a pointer that never moved.
## A cursor that lands off screen (a jump to the next unit, a new day) is centred.
##
## Unlike the flat board it glides: the whole-texel rule that makes the 2D
## camera land on a cell (presentation.md, the zoom ladder) is about sampling
## pixel art, and a perspective render has no texel grid to keep.

const PITCH_DEG := 52.0
const FOV_DEG := 30.0
## Distance at rung 1. A rung of z shows about as many cells as the flat board
## does at z, so a player's zoom habit carries across the flip.
const REACH_AT_RUNG_ONE := 40.0
const FOLLOW_RATE := 9.0
const TURN_RATE := 10.0
## The 2D board's shake is in world pixels; this is how far one moves the lens.
const SHAKE_PER_PX := 1.0 / 16.0
## The slack box, in fractions of the reach along the ground: across the screen,
## up it and down it. About three fifths of what the board band shows at the pitch
## and field of view above, so the cursor turns the camera well before an edge.
const SLACK_ACROSS := 0.28
const SLACK_AHEAD := 0.2
const SLACK_BEHIND := 0.14
## Past these the cursor is off the band altogether, and is centred rather than
## merely brought back inside the box.
const SEEN_ACROSS := 0.47
const SEEN_AHEAD := 0.33
const SEEN_BEHIND := 0.23
## A cursor this far past the box, in cells, is dragged even when that is off the
## band: at the closest rungs the band's near edge sits less than a cell past the
## box's, and a single arrow step would otherwise re-centre every other press.
const STEP_PAST := 1.01
## How much of the band the board may leave empty at a side, as the flat board's
## camera limits keep its view on the map: the goal stays this far in from each
## side, so an edge shows the diorama's rim and a sliver of table, not half a
## screen of it. Inside what SEEN_ACROSS allows, so a cursor on the edge stays in
## view.
const KEEP_ACROSS := 0.4
## Cells of table left showing past the rim at a side.
const RIM_SHOWN := 0.6
## Up and down the screen the board is held by its projected outline instead —
## the slab's foot, its rim and the tallest thing standing on an edge cell (the
## HQ's tower, a hovering aircraft) — which a fraction of the reach only
## approximates: the far side is foreshortened, and a quarter turn stands the
## long side up the screen. The outline stops this many canvas pixels short of
## the band's edges.
const EDGE_MARGIN_PX := 6.0
const EDGE_HEADROOM := 0.9
## Re-measures it takes perspective to settle: each one moves the pose by what
## the last missed by, and the outline stops moving well inside a pixel.
const EDGE_PASSES := 4
const WHOLE_PASSES := 8

var camera: Camera3D
## An unrendered twin posed where the camera is heading rather than where it is.
## A menu or a callout placed against a cell asks this one, so it lands where
## that cell will come to rest instead of where it was mid-glide.
var probe: Camera3D
## Quarter turns anticlockwise, seen from above, from looking north.
var quarters := 0
## The board's extent on the ground plane: the camera never frames past it.
var bounds := Rect2()
## Where on the screen the board is framed, in canvas pixels: the band between
## the HUD bars, less whatever stands over its top (the tutorial strip).
var band := Rect2()
## Whether the rung in hand is the board's floor — the survey view, which shows
## the whole board from whichever side it is seen.
var whole := false

var _yaw := 0.0
## The pitch and lift the lens stands at now. Both sit at the board's own values
## unless a cinematic has just `direct`ed the lens, and then ease back to them.
var _pitch := deg_to_rad(PITCH_DEG)
var _lift := 0.0
## Where the camera is heading and where it is, both on the ground plane.
var _goal := Vector3.ZERO
var _goal_reach := REACH_AT_RUNG_ONE / 2.0
var _target := Vector3.ZERO
var _reach := REACH_AT_RUNG_ONE / 2.0


func _init(p_camera: Camera3D, p_probe: Camera3D) -> void:
	camera = p_camera
	probe = p_probe
	for lens: Camera3D in [camera, probe]:
		lens.fov = FOV_DEG
		lens.near = 0.1
		lens.far = 250.0


## Stands the camera on its goal with no glide — the first frame after a flip.
func snap(focus: Vector3, rung: float) -> void:
	_goal = _grounded(focus)
	pose_probe(focus, rung)
	_target = _goal
	_reach = _goal_reach
	_yaw = quarters * PI / 2.0
	_pitch = deg_to_rad(PITCH_DEG)
	_lift = _band_lift()
	_place(camera, _target, _reach, _yaw, _pitch, _lift, Vector2.ZERO)


## Eases toward the cursor, the rung and the quarter turn in hand, framed in
## `band`.
func follow(delta: float, focus: Vector3, rung: float, shake: Vector2) -> void:
	# A still board — Instant, or a pinned capture — lands rather than glides, so
	# a captured frame never depends on how many frames it was taken after.
	var ease_follow := 1.0 if BoardBeat.still() else 1.0 - exp(-delta * FOLLOW_RATE)
	var yaw := quarters * PI / 2.0
	pose_probe(focus, rung)
	_target = _target.lerp(_goal, ease_follow)
	_reach = lerpf(_reach, _goal_reach, ease_follow)
	_pitch = lerpf(_pitch, deg_to_rad(PITCH_DEG), ease_follow)
	_lift = lerpf(_lift, _band_lift(), ease_follow)
	_yaw = lerp_angle(_yaw, yaw, 1.0 if BoardBeat.still() else 1.0 - exp(-delta * TURN_RATE))
	_place(camera, _target, _reach, _yaw, _pitch, _lift, shake)


## Stands the lens exactly where a cinematic says, off the board's framing. The
## pose is kept as the lens's own, so once the cinematic lets go `follow` glides
## home from wherever it left the lens rather than cutting back.
func direct(pose: CinemaPose3D) -> void:
	_target = pose.target
	_reach = pose.reach
	_yaw = pose.yaw
	_pitch = pose.pitch
	_lift = 0.0
	_place(camera, _target, _reach, _yaw, _pitch, 0.0, Vector2.ZERO)


## Where the lens stands now, for a cinematic to start its first move from.
func pose_now() -> CinemaPose3D:
	return CinemaPose3D.new(_target, _reach, _yaw, _pitch)


## Frames `focus` and stands the probe where the camera will come to rest on it.
## Safe to ask twice in a frame: a cursor already inside the box moves nothing.
func pose_probe(focus: Vector3, rung: float) -> void:
	var yaw := quarters * PI / 2.0
	if whole and bounds.has_area() and band.has_area():
		var pose := _whole_pose(yaw, REACH_AT_RUNG_ONE / _next_rung(rung))
		_goal = pose.target
		_goal_reach = pose.reach
	else:
		_goal_reach = REACH_AT_RUNG_ONE / maxf(rung, 0.1)
		_goal = _framed(_grounded(focus), _goal_reach, yaw)
	_place(probe, _goal, _goal_reach, yaw, deg_to_rad(PITCH_DEG), _band_lift(), Vector2.ZERO)


## The screen rect a ground-plane cell's top covers as the camera will come to
## rest, in canvas pixels: the four corners of its top face at `height`, boxed.
## For an overlay that has to step aside of a cell rather than point at it.
func screen_rect_of(cell: Vector2i, height: float) -> Rect2:
	var seen := Rect2(probe.unproject_position(Vector3(cell.x, height, cell.y)), Vector2.ZERO)
	for corner: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var at := cell + corner
		seen = seen.expand(probe.unproject_position(Vector3(at.x, height, at.y)))
	return seen


func turn(step: int) -> void:
	quarters = posmod(quarters + step, 4)


## How far along `ahead_axis` the goal stands when the board's outline lands its
## far edge (or its near one) on the screen row `line`, starting from `spot`.
func _ahead_landing(
	spot: Vector3, reach: float, ahead_axis: Vector3, line: float, far: bool
) -> float:
	var pitch := deg_to_rad(PITCH_DEG)
	var yaw := quarters * PI / 2.0
	for _pass in EDGE_PASSES:
		_place(probe, spot, reach, yaw, pitch, _band_lift(), Vector2.ZERO)
		var seen := _outline_on(probe)
		var edge := seen.position.y if far else seen.end.y
		spot += ahead_axis * (line - edge) * _world_per_px(probe, reach) / sin(pitch)
	return spot.dot(ahead_axis)


## The pose that frames the whole board in `band` from bearing `yaw`: the probe
## is stood, the board's outline measured on screen, and the pose re-centred and
## pulled back or in by what the outline missed by. Never nearer than `nearest`,
## so the floor rung is never closer than the rung above it.
func _whole_pose(yaw: float, nearest: float) -> CinemaPose3D:
	var pitch := deg_to_rad(PITCH_DEG)
	var centre := bounds.get_center()
	var pose := CinemaPose3D.new(
		Vector3(centre.x, BoardSpace3D.LAND_TOP, centre.y), nearest, yaw, pitch
	)
	var ahead_axis := Vector3(-sin(yaw), 0, -cos(yaw))
	var room := band.grow(-EDGE_MARGIN_PX)
	for _pass in WHOLE_PASSES:
		_place(probe, pose.target, pose.reach, yaw, pitch, _band_lift(), Vector2.ZERO)
		var seen := _outline_on(probe)
		var world_per_px := _world_per_px(probe, pose.reach)
		var miss := (room.get_center() - seen.get_center()) * world_per_px
		pose.target += -pose.across() * miss.x + ahead_axis * miss.y / sin(pitch)
		var spill := maxf(seen.size.x / room.size.x, seen.size.y / room.size.y)
		pose.reach = maxf(pose.reach * spill, nearest)
	return pose


## The board's outline as `lens` sees it: the slab's foot, the rim, and the top
## of the tallest thing an edge cell can hold standing in that cell's middle,
## boxed.
func _outline_on(lens: Camera3D) -> Rect2:
	var seen := Rect2()
	var first := true
	for layer: Array in [
		[bounds, BoardSpace3D.SLAB_BOTTOM],
		[bounds, BoardSpace3D.LAND_TOP],
		[bounds.grow(-0.5), BoardSpace3D.LAND_TOP + EDGE_HEADROOM],
	]:
		var rect: Rect2 = layer[0]
		var height: float = layer[1]
		for corner: Vector2 in [
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y)
		]:
			var spot := lens.unproject_position(Vector3(corner.x, height, corner.y))
			seen = Rect2(spot, Vector2.ZERO) if first else seen.expand(spot)
			first = false
	return seen


## How far above the window's middle the band's middle sits, in canvas pixels,
## so the cursor lands in the band rather than behind a bar.
func _band_lift() -> float:
	if not band.has_area():
		return 0.0
	return camera.get_viewport().get_visible_rect().size.y / 2.0 - band.get_center().y


## The rung above `rung` on its ladder — the floor's neighbour — or `rung` itself
## when it is the ladder's last.
static func _next_rung(rung: float) -> float:
	var ladder := BattleZoom.rungs_for(rung)
	return ladder[1] if ladder.size() > 1 else maxf(rung, 0.1)


## The goal moved just far enough to hold `spot` inside the slack box — or onto
## it, when it is off the band — and kept over the board.
func _framed(spot: Vector3, reach: float, yaw: float) -> Vector3:
	var across_axis := Vector3(cos(yaw), 0, -sin(yaw))
	var ahead_axis := Vector3(-sin(yaw), 0, -cos(yaw))
	var offset := spot - _goal
	var across := offset.dot(across_axis)
	var ahead := offset.dot(ahead_axis)
	var past_across := across - clampf(across, -SLACK_ACROSS * reach, SLACK_ACROSS * reach)
	var past_ahead := ahead - clampf(ahead, -SLACK_BEHIND * reach, SLACK_AHEAD * reach)
	var seen := (
		absf(across) <= SEEN_ACROSS * reach
		and ahead <= SEEN_AHEAD * reach
		and ahead >= -SEEN_BEHIND * reach
	)
	var goal := spot
	if seen or maxf(absf(past_across), absf(past_ahead)) <= STEP_PAST:
		goal = _goal + across_axis * past_across + ahead_axis * past_ahead
	return _over_board(goal, reach, across_axis, ahead_axis)


## `goal`, held in from the board's edges as seen from this side of it; a board
## narrower than the band on an axis is centred on that axis instead. Up and down
## the screen that is measured off the board's outline in `band`.
func _over_board(goal: Vector3, reach: float, across_axis: Vector3, ahead_axis: Vector3) -> Vector3:
	if not bounds.has_area():
		return goal
	var low := INF
	var high := -INF
	for corner: Vector2 in [
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	]:
		var seen_as := Vector3(corner.x, 0, corner.y).dot(across_axis)
		low = minf(low, seen_as)
		high = maxf(high, seen_as)
	var across := _held_in(
		goal.dot(across_axis),
		low + KEEP_ACROSS * reach - RIM_SHOWN,
		high - KEEP_ACROSS * reach + RIM_SHOWN
	)
	var ahead := goal.dot(ahead_axis)
	if band.has_area():
		var room := band.grow(-EDGE_MARGIN_PX)
		var spot := across_axis * across + ahead_axis * ahead + Vector3.UP * goal.y
		ahead = _held_in(
			ahead,
			_ahead_landing(spot, reach, ahead_axis, room.end.y, false),
			_ahead_landing(spot, reach, ahead_axis, room.position.y, true)
		)
	return across_axis * across + ahead_axis * ahead + Vector3.UP * goal.y


static func _held_in(value: float, lowest: float, highest: float) -> float:
	if lowest > highest:
		return (lowest + highest) / 2.0
	return clampf(value, lowest, highest)


## A point on the board's ground plane, so a cursor on a peak or at sea does not
## bob the whole view up and down with it.
static func _grounded(spot: Vector3) -> Vector3:
	return Vector3(spot.x, BoardSpace3D.LAND_TOP, spot.z)


static func _place(
	lens: Camera3D,
	target: Vector3,
	reach: float,
	yaw: float,
	pitch: float,
	lift_px: float,
	shake: Vector2
) -> void:
	var back := Vector3(sin(yaw), 0, cos(yaw)) * cos(pitch) * reach
	lens.position = target + back + Vector3.UP * sin(pitch) * reach
	lens.look_at_from_position(lens.position, target, Vector3.UP)
	lens.h_offset = shake.x * SHAKE_PER_PX
	lens.v_offset = -lift_px * _world_per_px(lens, reach) - shake.y * SHAKE_PER_PX


## World units per canvas pixel at the look-at point, `reach` from the lens.
static func _world_per_px(lens: Camera3D, reach: float) -> float:
	var view_h := lens.get_viewport().get_visible_rect().size.y
	return 2.0 * reach * tan(deg_to_rad(FOV_DEG) / 2.0) / maxf(view_h, 1.0)
