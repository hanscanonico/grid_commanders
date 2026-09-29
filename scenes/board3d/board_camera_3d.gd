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

var camera: Camera3D
## An unrendered twin posed where the camera is heading rather than where it is.
## A menu or a callout placed against a cell asks this one, so it lands where
## that cell will come to rest instead of where it was mid-glide.
var probe: Camera3D
## Quarter turns anticlockwise, seen from above, from looking north.
var quarters := 0

var _yaw := 0.0
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
	_target = focus
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
	_target = _target.lerp(focus, ease_follow)
	_reach = lerpf(_reach, reach, ease_follow)
	_yaw = lerp_angle(_yaw, yaw, 1.0 if BoardBeat.still() else 1.0 - exp(-delta * TURN_RATE))
	_place(camera, _target, _reach, _yaw, lift_px, shake)
	pose_probe(focus, rung, lift_px)


## Stands the probe where the camera will come to rest on `focus`.
func pose_probe(focus: Vector3, rung: float, lift_px: float) -> void:
	var reach := REACH_AT_RUNG_ONE / maxf(rung, 0.1)
	_place(probe, focus, reach, quarters * PI / 2.0, lift_px, Vector2.ZERO)


func turn(step: int) -> void:
	quarters = posmod(quarters + step, 4)


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
