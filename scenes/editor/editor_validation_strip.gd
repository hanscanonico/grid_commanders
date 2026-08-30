class_name EditorValidationStrip
extends PanelContainer
## What still stands between the draft and a playable board, in the author's own
## words, kept current under the board it is about.
##
## It reads `MapValidator` and nothing else — the rules are the simulation's and
## a strip with its own opinion would tell an author their board plays and then
## watch the picker refuse it. Every line is one `MapDefect`, so pressing it walks
## the cursor to the very cell the sentence names rather than to a cell the strip
## went looking for.

## The author asked to be shown the cell a complaint is about.
signal focused(cell: Vector2i)

## How many lines of complaint stand open; the rest scroll. The strip is chrome
## under a board, so it may not grow into the board as the draft gets worse.
const LINES := 2
## A complaint's plate and its words, inset from the strip's outline.
const ROW_INSET := 3
## The leading a complaint is set with, stated here rather than left to the
## default theme: the strip's height is a whole number of these, so the two may
## not be answered by different files.
const LINE_GAP := 3


func _init() -> void:
	custom_minimum_size = Vector2(0, _height_for(LINES))
	add_theme_stylebox_override("panel", UiTheme.dark_panel_box(UiTheme.SLATE_900))


## Says what is wrong now, replacing whatever it said before. An empty list is the
## one line an author is working towards, so it is stated rather than left blank.
func show_defects(defects: Array[MapDefect]) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var rows := VBoxContainer.new()
	# No gap between complaints: the strip is a whole number of lines tall, and a
	# gap the lines are not a multiple of puts the slice back where it was.
	rows.add_theme_constant_override("separation", 0)
	# A scrolling frame lays its child out at the child's own width unless the
	# child asks for the frame's, and a sentence given its own width wraps to one
	# letter a line.
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if defects.is_empty():
		rows.add_child(_line("This board plays. Save it.", UiTheme.CAPTURE))
	for defect in defects:
		rows.add_child(_row(defect))
	var frame := UiKit.vscroll()
	frame.add_child(rows)
	add_child(UiKit.pad(frame, ROW_INSET, ROW_INSET))


## The strip is exactly `lines` whole lines tall, measured off the face it prints
## in rather than picked: a height that lands mid-glyph slices the last line it
## shows in half, which reads as a broken font rather than as more to scroll.
static func _height_for(lines: int) -> int:
	var pitch := ceili(UiTheme.stat().get_height(UiTheme.SIZE_STAT)) + LINE_GAP
	return lines * pitch + 2 * (ROW_INSET + UiTheme.PANEL_BORDER)


## Every cell any complaint names, for the board to mark.
static func marked_cells(defects: Array[MapDefect]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for defect in defects:
		for cell in defect.cells:
			if not cells.has(cell):
				cells.append(cell)
	return cells


## A complaint that names a cell is a button that walks the cursor there; one
## about the whole board is a line, since there is nowhere for it to go.
func _row(defect: MapDefect) -> Control:
	var label := _line(defect.text, UiTheme.DANGER)
	if defect.cells.is_empty():
		return label
	var button := Button.new()
	button.tooltip_text = "Show me"
	button.pressed.connect(func() -> void: focused.emit(defect.cells[0]))
	UiTheme.apply_button(button, UiTheme.ButtonVariant.GHOST, null, UiTheme.SIZE_BUTTON)
	UiKit.touchable(button)
	# The row takes its height from the words and the plate stands behind them: a
	# Button lays out no child and asks for no height for one, so a complaint
	# hung inside it drew over the complaint below as soon as it wrapped.
	var row := MarginContainer.new()
	row.add_theme_constant_override("margin_left", ROW_INSET)
	row.add_theme_constant_override("margin_right", ROW_INSET)
	row.add_child(button)
	row.add_child(label)
	return row


## A complaint is a whole sentence, so it wraps rather than being cut short — and
## it must, since a frame that never scrolls sideways asks its contents for their
## full width and a strip of unwrapped sentences would push the board off screen.
static func _line(text: String, ink: Color) -> Label:
	var label := UiTheme.hud_label(text, UiTheme.SIZE_STAT, ink)
	label.add_theme_constant_override("line_spacing", LINE_GAP)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
