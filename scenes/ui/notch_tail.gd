class_name NotchTail
extends Control
## The notch that points a dark panel at what it describes: an ink triangle with a
## slate core whose base runs past the panel's border, so the notch opens into the
## panel rather than sitting on it.
##
## Drawn rather than rotated — a rotated Control resamples, and this UI is
## pixel-crisp everywhere else. Every colour and border is UiTheme's, so a notch
## matches the panel it opens into (`UiTheme.dark_panel_box`).

## Canvas pixels, so both are half the handoff's and double on screen.
const WIDTH := 10
const HEIGHT := 5
## The notch's own edges are BORDER, not the panel's PANEL_BORDER: on a triangle
## this small a 2px inset swallows the slate core whole, and the notch reads as a
## solid ink arrowhead instead of an opening in the panel.
const BORDER := UiTheme.BORDER

var _points_up := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Puts the notch on the panel edge that faces what it points at — the top edge
## when the panel sits below it (`points_up`), the bottom edge when it sits above
## — centred on `anchor` (that target's centre, in the panel's own coordinates)
## but never so far along the edge that it leaves the panel's border behind.
func place(points_up: bool, anchor: Vector2, panel: Vector2) -> void:
	_points_up = points_up
	var thick := float(UiTheme.PANEL_BORDER)  # the panel's border, its no-go strip
	size = Vector2(WIDTH, HEIGHT)
	var along := _along(anchor.x, panel.x, thick)
	position = Vector2(along, -HEIGHT if points_up else panel.y).round()
	queue_redraw()


func _along(anchor: float, span: float, thick: float) -> float:
	return clampf(anchor - WIDTH * 0.5, thick + 1.0, maxf(thick + 1.0, span - WIDTH - thick - 1.0))


func _draw() -> void:
	var outer := PackedVector2Array(
		[Vector2(0, HEIGHT), Vector2(WIDTH * 0.5, 0), Vector2(WIDTH, HEIGHT)]
	)
	# The core's base runs past the panel's own border, so the notch opens into the
	# panel's fill rather than sitting on top of its outline.
	var inner := _inset(outer, float(BORDER))
	inner[0].y = HEIGHT + UiTheme.PANEL_BORDER
	inner[2].y = HEIGHT + UiTheme.PANEL_BORDER
	draw_colored_polygon(_orient(outer), UiTheme.HARD_BORDER)
	draw_colored_polygon(_orient(inner), UiTheme.SLATE_800)


## The triangle is written apex-up; a notch on a panel's bottom edge is that same
## geometry flipped, so the shape is described once.
func _orient(points: PackedVector2Array) -> PackedVector2Array:
	if _points_up:
		return points
	var out := PackedVector2Array()
	for point in points:
		out.append(Vector2(point.x, HEIGHT - point.y))
	return out


## Every edge of a triangle pulled `thick` pixels inward: the triangle scaled
## about its incentre, whose distance to all three edges is the inradius.
func _inset(tri: PackedVector2Array, thick: float) -> PackedVector2Array:
	var a := tri[1].distance_to(tri[2])
	var b := tri[2].distance_to(tri[0])
	var c := tri[0].distance_to(tri[1])
	var perimeter := a + b + c
	var incentre := (tri[0] * a + tri[1] * b + tri[2] * c) / perimeter
	var radius := absf((tri[1] - tri[0]).cross(tri[2] - tri[0])) / perimeter
	var shrink := maxf((radius - thick) / radius, 0.0) if radius > 0.0 else 0.0
	var out := PackedVector2Array()
	for point in tri:
		out.append(incentre + (point - incentre) * shrink)
	return out
