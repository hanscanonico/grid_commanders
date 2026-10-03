class_name UnitStillShot3D
extends RefCounted
## How a unit's 3D icon still is shot: an orthographic lens a little above and
## off the model's flank, its nose turned toward the right of the frame, fitted
## to the model's bounds. Pure arithmetic over a model's box and the window's
## scale, checked without a scene.

## The lens looks down this far, gentler than the board's camera, so a hull's
## side and a tank's turret both read in a square a few dozen pixels wide.
const PITCH_DEG := 30.0
## How far the lens swings from broadside toward the nose: a three-quarter view.
const YAW_DEG := 30.0
## How far from the aim the lens stands; orthographic, so only clearance.
const LENS_DISTANCE := 4.0
## Air left round the model's projected box, as a share of its longer side.
const MARGIN := 0.08
## The still is rendered this many times its drawn size and filtered down, so
## its edges are smooth at the size the menu draws it at.
const SUPERSAMPLE := 4


## The direction the lens looks along, in the model's space (it faces +X).
static func forward() -> Vector3:
	var pitch := deg_to_rad(PITCH_DEG)
	var yaw := deg_to_rad(YAW_DEG)
	var flat := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return (flat * cos(pitch) + Vector3.DOWN * sin(pitch)).normalized()


## The lens's frame: its right, its up and its back, the way `Basis` holds them.
static func basis() -> Basis:
	var back := -forward()
	var right := Vector3.UP.cross(back).normalized()
	return Basis(right, back.cross(right), back)


## The middle of `bounds` as the lens sees it, in the model's space — the point
## the lens aims at so the model sits centred in the frame.
static func aim(bounds: AABB) -> Vector3:
	var frame := basis()
	var span := _projected(bounds, frame)
	var middle := span.get_center()
	var depth := frame.z.dot(bounds.get_center())
	return frame.x * middle.x + frame.y * middle.y + frame.z * depth


## Where the lens stands to look at `bounds`.
static func eye(bounds: AABB) -> Vector3:
	return aim(bounds) - forward() * LENS_DISTANCE


## The lens's orthographic height in world units: the projected box's longer
## side and its margin, so the square frame holds the whole model.
static func lens_height(bounds: AABB) -> float:
	var span := _projected(bounds, basis()).size
	return maxf(span.x, span.y) * (1.0 + 2.0 * MARGIN)


## The still's side in pixels: the menu's icon slot as the window draws it, so
## the still is drawn one pixel a pixel at the window's scale.
static func pixels(window_scale: float) -> int:
	return maxi(UiTheme.MENU_ICON, roundi(UiTheme.MENU_ICON * window_scale))


## The cache's name for one still: a unit type, an army's atlas row, a size.
static func key(type_id: StringName, row: int, side: int) -> String:
	return "%s/%d/%d" % [type_id, row, side]


## `bounds` flattened onto the lens's right and up axes.
static func _projected(bounds: AABB, frame: Basis) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i in 8:
		var corner := bounds.get_endpoint(i)
		var at := Vector2(frame.x.dot(corner), frame.y.dot(corner))
		low = low.min(at)
		high = high.max(at)
	return Rect2(low, high - low)
