class_name CinemaPose3D
extends RefCounted
## Where a cinematic stands the lens: the point it looks at, how far back it
## stands, and from which bearing and pitch — the four numbers `BoardCamera3D`
## places a camera by. A value, never a node, so a shot is arithmetic.

var target: Vector3
var reach: float
## Radians anticlockwise, seen from above, from looking north (the camera's `quarters` axis).
var yaw: float
## Radians above the horizon.
var pitch: float


func _init(
	p_target: Vector3 = Vector3.ZERO, p_reach: float = 1.0, p_yaw: float = 0.0, p_pitch: float = 0.0
) -> void:
	target = p_target
	reach = p_reach
	yaw = p_yaw
	pitch = p_pitch


## The pose `weight` of the way to `to`, turning the short way round.
func toward(to: CinemaPose3D, weight: float) -> CinemaPose3D:
	return CinemaPose3D.new(
		target.lerp(to.target, weight),
		lerpf(reach, to.reach, weight),
		lerp_angle(yaw, to.yaw, weight),
		lerpf(pitch, to.pitch, weight)
	)


## The lens's own position for this pose.
func eye() -> Vector3:
	var back := Vector3(sin(yaw), 0, cos(yaw)) * cos(pitch) * reach
	return target + back + Vector3.UP * sin(pitch) * reach


## Screen-right on the ground plane, as seen from this bearing.
func across() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


## A move from `from` to `to`, `t` of the way through it (0..1), eased at both
## ends and lifted on a crane's arc: the lens pulls back in the middle by
## `arc` per cell travelled, so a jump across the board reads as a flight over
## it rather than a skim along the ground.
static func glide(from: CinemaPose3D, to: CinemaPose3D, t: float, arc: float) -> CinemaPose3D:
	var eased := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	var pose := from.toward(to, eased)
	var flight := Vector2(from.target.x, from.target.z).distance_to(
		Vector2(to.target.x, to.target.z)
	)
	pose.reach += sin(PI * eased) * flight * arc
	return pose
