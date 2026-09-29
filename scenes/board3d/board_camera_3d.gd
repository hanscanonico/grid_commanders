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

var camera: Camera3D
## An unrendered twin posed where the camera is heading rather than where it is.
## A menu or a callout placed against a cell asks this one, so it lands where
## that cell will come to rest instead of where it was mid-glide.
var probe: Camera3D
## Quarter turns anticlockwise, seen from above, from looking north.
var quarters := 0
## The board's extent on the ground plane: the camera never frames past it.
var bounds := Rect2()

var _yaw := 0.0
## Where the camera is heading and where it is, both on the ground plane.
var _goal := Vector3.ZERO
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
func snap(focus: Vector3, rung: float, lift_px: float) -> void:
	_goal = _grounded(focus)
	_target = _goal
	_reach = REACH_AT_RUNG_ONE / maxf(rung, 0.1)
	_yaw = quarters * PI / 2.0
	_place(camera, _target, _reach, _yaw, lift_px, Vector2.ZERO)
	_place(probe, _target, _reach, _yaw, lift_px, Vector2.ZERO)


## Eases toward the cursor, the rung and the quarter turn in hand. `lift_px` is
## how far above the window's middle the board band's middle sits, in canvas
## pixels, so the cursor lands in the band between the HUD bars.
func follow(delta: float, focus: Vector3, rung: float, lift_px: float, shake: Vector2) -> void:
	# A still board — Instant, or a pinned capture — lands rather than glides, so
	# a captured frame never depends on how many frames it was taken after.
	var ease_follow := 1.0 if BoardBeat.still() else 1.0 - exp(-delta * FOLLOW_RATE)
	var reach := REACH_AT_RUNG_ONE / maxf(rung, 0.1)
	var yaw := quarters * PI / 2.0
	pose_probe(focus, rung, lift_px)
	_target = _target.lerp(_goal, ease_follow)
	_reach = lerpf(_reach, reach, ease_follow)
	_yaw = lerp_angle(_yaw, yaw, 1.0 if BoardBeat.still() else 1.0 - exp(-delta * TURN_RATE))
	_place(camera, _target, _reach, _yaw, lift_px, shake)


## Frames `focus` and stands the probe where the camera will come to rest on it.
## Safe to ask twice in a frame: a cursor already inside the box moves nothing.
func pose_probe(focus: Vector3, rung: float, lift_px: float) -> void:
	var reach := REACH_AT_RUNG_ONE / maxf(rung, 0.1)
	var yaw := quarters * PI / 2.0
	_goal = _framed(_grounded(focus), reach, yaw)
	_place(probe, _goal, reach, yaw, lift_px, Vector2.ZERO)


func turn(step: int) -> void:
	quarters = posmod(quarters + step, 4)


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
	if bounds.has_area():
		goal.x = clampf(goal.x, bounds.position.x, bounds.end.x)
		goal.z = clampf(goal.z, bounds.position.y, bounds.end.y)
	return goal


## A point on the board's ground plane, so a cursor on a peak or at sea does not
## bob the whole view up and down with it.
static func _grounded(spot: Vector3) -> Vector3:
	return Vector3(spot.x, BoardSpace3D.LAND_TOP, spot.z)


static func _place(
	lens: Camera3D, target: Vector3, reach: float, yaw: float, lift_px: float, shake: Vector2
) -> void:
	var pitch := deg_to_rad(PITCH_DEG)
	var back := Vector3(sin(yaw), 0, cos(yaw)) * cos(pitch) * reach
	lens.position = target + back + Vector3.UP * sin(pitch) * reach
	lens.look_at_from_position(lens.position, target, Vector3.UP)
	var view_h := lens.get_viewport().get_visible_rect().size.y
	var world_per_px := 2.0 * reach * tan(deg_to_rad(FOV_DEG) / 2.0) / maxf(view_h, 1.0)
	lens.h_offset = shake.x * SHAKE_PER_PX
	lens.v_offset = -lift_px * world_per_px - shake.y * SHAKE_PER_PX
