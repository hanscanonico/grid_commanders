class_name ReplayPickerPanel
extends Control
## The list of recorded matches, shown over the main menu without tearing it down
## — `CommanderSelectPanel`'s smaller sibling, and built the same way for the same
## reason: a Back has to land on the setup exactly as it was left.
##
## Every match records itself (replay plan D5), so this page is the only place a
## player meets that fact. It reads `ReplayFile.list()`, which parses one line per
## file and no commands at all, and hands back the path of whatever was picked. It
## never opens a recording, never starts a battle and never touches `core/`.
##
## A recording is three facts — the board, the table and when it was played — and
## the page sets them as three, in the campaign hub's row shape: a headline over a
## micro detail line, with the stamp in a right-hand column so the dates line up
## down the list. One padded string across a row read as a table missing its
## columns.

signal picked(path: String)
signal cancelled

## Two lines of ink plus the button's own frame.
const _ROW_HEIGHT := 24
## The page's one inset, the campaign hub's: a row's face from its button's
## edges, and the list from the frame's.
const _INSET := 6
## The list is a reading column, not a banner: the shell's content width, which is
## about as wide as the longest real row needs. The frame, its rows and Back all
## take it, so nothing on the page has a width of its own.
const _LIST_WIDTH := UiTheme.CONTENT_W

var _title: Label
var _rows: VBoxContainer
var _count: Label
var _empty: Label
var _back_button: Button
var _row_buttons: Array[Button] = []
## Parallel to `_row_buttons`: the file each one plays.
var _paths: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_build()
	hide()


## Opens the page on a list of recordings, newest first. The list is handed in
## rather than read here for the reason `ContinueSlot` is handed its save summary
## through the capture driver: a photographed frame must not depend on how many
## matches the machine that took it happens to have played.
func begin(summaries: Array[ReplayFile.Summary]) -> void:
	_fill(summaries)
	show()
	if _row_buttons.is_empty():
		_back_button.grab_focus()
	else:
		_row_buttons[0].grab_focus()


## What a capture measures itself against, in `CommanderSelectPanel.chrome`'s
## shape and for its reason: a page built in code can lay out inside the frame and
## still be photographed with a control off the bottom of it.
## The first row only, not every one: past a full slate the list scrolls, so a
## gate demanding that all ten sit inside the frame would be measuring the wrong
## promise. What it proves is that the page laid out and the list rendered.
func chrome() -> Dictionary[String, Control]:
	var named: Dictionary[String, Control] = {"the replays title": _title, "Back": _back_button}
	if _row_buttons.is_empty():
		named["the empty note"] = _empty
	else:
		named["the first replay row"] = _row_buttons[0]
	return named


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cancel"):
		get_viewport().set_input_as_handled()
		_leave()


# --- build -------------------------------------------------------------------


func _build() -> void:
	UiKit.page_veil(self)
	var main := UiKit.page_body(self, 6)

	_title = Label.new()
	_title.text = "REPLAYS"
	_title.add_theme_font_override("font", UiTheme.display(true))
	_title.add_theme_font_size_override("font_size", UiTheme.SIZE_PAGE_TITLE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_title)

	# This page is the only surface that tells a player their matches are being
	# kept, so it says so whether or not the list has anything in it yet.
	main.add_child(_note("Every match records itself. The last %d are kept." % ReplayFile.KEEP))

	main.add_child(_build_frame())

	_back_button = Button.new()
	_back_button.text = "Back"
	UiTheme.apply_button(_back_button, UiTheme.ButtonVariant.GHOST, null, UiTheme.SIZE_BUTTON)
	_back_button.custom_minimum_size = Vector2(_LIST_WIDTH, 20)
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(_leave)
	main.add_child(_back_button)

	var footer := Label.new()
	footer.add_theme_font_override("font", UiTheme.stat())
	footer.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	footer.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	footer.text = "UP/DOWN  BROWSE      ENTER  WATCH      ESC  BACK      MOUSE OK"
	main.add_child(footer)


## The list's frame: a titled slate panel of a fixed width taking whatever height
## the page has left, so a page holding three recordings and a page holding ten
## are the same page. Slate rather than the cream `panel_box`, because the rows
## are cream themselves and a cream list on a cream card is one surface.
func _build_frame() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.dark_panel_box())
	panel.custom_minimum_size = Vector2(_LIST_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiTheme.header_box(UiTheme.SLATE_700))
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	var heading := UiKit.micro_label("Recordings")
	heading.add_theme_color_override("font_color", UiTheme.WHITE)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(heading)
	_count = UiKit.micro_label("")
	_count.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	header_row.add_child(_count)
	header.add_child(header_row)
	col.add_child(header)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	var padded := UiKit.pad(body, _INSET, _INSET)
	padded.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(padded)

	_empty = _note("Nothing recorded yet — play a match and it will be here.")
	body.add_child(_empty)

	# Scrolled because ten rows are more than the frame holds, and focus-following
	# because otherwise the list stays put while the keyboard walks off the bottom
	# of it — the campaign hub's list learned the same lesson.
	var scroll := UiKit.vscroll()
	scroll.follow_focus = true
	body.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	return panel


## A centred Silkscreen micro-line, the panel's one kind of explanatory text.
## Unlike `UiKit.micro_label`/`help_label`, this reads a sentence rather than a
## caption, so it keeps its own case and centres rather than uppercasing —
## `UiTheme.hud_label` still carries the shared font/size/colour build, reset
## to this page's own alignment (hud_label centres vertically, for a bar row;
## this note wants that horizontally instead).
func _note(text: String) -> Label:
	var label := UiTheme.hud_label(text, UiTheme.SIZE_STAT, UiTheme.NEUTRAL_LIGHT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Rebuilds the rows for `summaries`. The buttons are made fresh each time rather
## than pooled: the list changes length between openings, and a stale row is a row
## that plays the wrong match.
func _fill(summaries: Array[ReplayFile.Summary]) -> void:
	for button in _row_buttons:
		_rows.remove_child(button)
		button.queue_free()
	_row_buttons.clear()
	_paths = PackedStringArray()
	_empty.visible = summaries.is_empty()
	_count.text = "%d OF %d" % [summaries.size(), ReplayFile.KEEP]
	for summary in summaries:
		var button := _row_button(summary, _paths.size())
		_rows.add_child(button)
		_row_buttons.append(button)
		_paths.append(summary.path)


func _row_button(summary: ReplayFile.Summary, index: int) -> Button:
	var button := Button.new()
	UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY, null, UiTheme.SIZE_BUTTON)
	button.custom_minimum_size = Vector2(0, _ROW_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_child(_row_face(summary))
	button.pressed.connect(func() -> void: _pick(index))
	return button


## The row as columns rather than a padded string: the board over the table on the
## left, the stamp in its own right-hand column. Children of a button, so the face
## ignores the mouse and the press stays the button's.
func _row_face(summary: ReplayFile.Summary) -> Control:
	var face := HBoxContainer.new()
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.offset_left = _INSET
	face.offset_right = -_INSET
	face.add_theme_constant_override("separation", 6)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lines := _row_lines(summary)
	var board := UiTheme.hud_label(lines[0], UiTheme.SIZE_BUTTON, UiTheme.INK, true)
	board.clip_text = true
	words.add_child(board)
	if lines.size() > 1:
		var table := _detail(lines[1], HORIZONTAL_ALIGNMENT_LEFT)
		table.clip_text = true
		words.add_child(table)
	face.add_child(words)

	var stamp := _stamp(summary)
	if not stamp.is_empty():
		var when := VBoxContainer.new()
		when.add_theme_constant_override("separation", 0)
		when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		when.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for line in stamp:
			when.add_child(_detail(line, HORIZONTAL_ALIGNMENT_RIGHT))
		face.add_child(when)
	return face


## One of a row's quiet lines, in the kit's micro dress. Unclipped: a clipped
## label asks for no width at all, which is right for the line that gives the
## expanding column its ground and wrong for the stamp column, whose whole width
## is what it has to say.
func _detail(text: String, align: HorizontalAlignment) -> Label:
	var label := UiKit.micro_label(text)
	label.horizontal_alignment = align
	return label


## A recording as the board it was played on and who was at the table. A label is
## written as those two joined by `BattleRecording.LABEL_SEPARATOR`, so the page
## reads it back at that one separator rather than setting the whole string on one
## line; a file that names no table — an older or hand-made one — keeps its label
## as the headline, and one that names nothing at all falls back to the board its
## own opening states.
func _row_lines(summary: ReplayFile.Summary) -> PackedStringArray:
	var parts := summary.label.split(BattleRecording.LABEL_SEPARATOR, true, 1)
	if parts.size() > 1:
		return parts
	if summary.label.is_empty():
		return PackedStringArray([MapCatalog.display_name(summary.map_path)])
	return parts


## When it was played, as the day over the time — a recording stamps itself
## `Time.get_datetime_string_from_system`, which joins the two at a T. Empty when
## the file carries no stamp, and the column is then left off the row entirely.
func _stamp(summary: ReplayFile.Summary) -> PackedStringArray:
	if summary.recorded.is_empty():
		return PackedStringArray()
	return summary.recorded.split("T", true, 1)


func _pick(index: int) -> void:
	if index < 0 or index >= _paths.size():
		return
	hide()
	picked.emit(_paths[index])


func _leave() -> void:
	hide()
	cancelled.emit()
