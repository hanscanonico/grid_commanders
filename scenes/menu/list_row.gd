class_name ListRow
extends RefCounted
## The scaffold a menu list row is drawn with: the face laid over a button, the
## column of words on it, and the two kinds of line those words are. The replay
## picker, the campaign picker and the campaign hub all draw the same row, so the
## shape is stated here once and each page keeps only what it says differently —
## the ink it resolves, whether a line clips or wraps, a thumbnail, an alignment.
##
## `CutscenePalette` and `OverlayPalette` are the precedent for a sibling class
## rather than another `UiKit` entry: the kit is at its public-method ceiling, and
## a row scaffold is a page's vocabulary rather than the design system's.
##
## Node-free statics — a face is built, handed back and parented by its caller.


## A row's face, laid over the whole button and inset from both edges. Children
## of a button, so the face ignores the mouse and the press stays the button's.
static func face(inset: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = inset
	row.offset_right = -inset
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


## The face's expanding column of lines, centred against the row's height and
## stacked with no gap: the lines are one block of copy, not a list.
static func words() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return column


## A row's spoken line, in the display face. The ink is the caller's, because a
## row on a coloured plate resolves its own label colour.
static func cell(text: String, ink: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.display())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_BUTTON)
	label.add_theme_color_override("font_color", ink)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A row's quiet line, in the stat face. Deliberately not vertically centred —
## a detail sits under the line it belongs to, so it takes the height it asks for.
static func detail(text: String, ink: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.stat())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	label.add_theme_color_override("font_color", ink)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
