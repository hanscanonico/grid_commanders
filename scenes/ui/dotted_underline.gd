class_name DottedUnderline
extends Control
## The dotted rule under a label — the one hint that hovering it will explain
## something. Drawn under the *text*, not the control, so a label wider than its
## string is still underlined only where the words are.
##
## Added as a child of the Label it underlines, and takes its colour from it.


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var label := get_parent() as Label
	if label != null:
		label.resized.connect(queue_redraw)


## Drawn off the *parent's* rect rather than this node's own. A Label is not a
## container, so a child added to one keeps whatever size it had when it entered
## the tree — here, none — and an anchored rule would land above the words instead
## of under them.
func _draw() -> void:
	var label := get_parent() as Label
	if label == null or label.text.is_empty():
		return
	var rect := label.size
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	var span := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var start := 0.0
	if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		start = roundf((rect.x - span) * 0.5)
	elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		start = rect.x - span
	var color := label.get_theme_color(&"font_color")
	var y := rect.y - 1.0
	var x := maxf(start, 0.0)
	while x < start + span:
		draw_rect(Rect2(x, y, 1, 1), color)
		x += 2.0
