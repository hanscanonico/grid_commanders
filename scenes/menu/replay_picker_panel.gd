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

signal picked(path: String)
signal cancelled

const _TITLE_SIZE := 15
const _ROW_HEIGHT := 18
## The list is a reading column, not a banner. Full-frame rows set a 41-character
## label across 624px with the last third empty, which reads as a table missing a
## column; this is about as wide as the longest real label needs.
const _ROW_WIDTH := 360

var _title: Label
var _rows: VBoxContainer
var _empty: Label
var _back_button: Button
var _row_buttons: Array[Button] = []
## Parallel to `_row_buttons`: the file each one plays.
var _paths: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_build()
	hide()


## Opens the page on a list of recordings, newest first. The list is handed in
## rather than read here for the reason `_refresh_continue` reads its save summary
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
func chrome() -> Dictionary:
	var named := {"the replays title": _title, "Back": _back_button}
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
	# Anchors *and* offsets, for the reason CommanderSelectPanel spells out: a page
	# built in code and added to an already-sized menu has a 0x0 rect, and
	# `set_anchors_preset` alone would preserve it.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(UiTheme.SLATE_900.r, UiTheme.SLATE_900.g, UiTheme.SLATE_900.b, 0.985)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	add_child(margin)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	margin.add_child(main)

	_title = Label.new()
	_title.text = "REPLAYS"
	_title.add_theme_font_override("font", UiTheme.display(true))
	_title.add_theme_font_size_override("font_size", _TITLE_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_title)

	# This page is the only surface that tells a player their matches are being
	# kept, so it says so whether or not the list has anything in it yet.
	main.add_child(_note("Every match records itself. The last %d are kept." % ReplayFile.KEEP))

	_empty = _note("Nothing recorded yet — play a match and it will be here.")
	main.add_child(_empty)

	# Scrolled for the same reason the select page's card is: ten rows fit today,
	# and the list's height must not be able to carry Back off the bottom.
	var frame := ScrollContainer.new()
	frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(frame)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(_rows)

	_back_button = Button.new()
	_back_button.text = "Back"
	UiTheme.apply_button(_back_button, UiTheme.ButtonVariant.GHOST, null, UiTheme.SIZE_BUTTON)
	_back_button.custom_minimum_size = Vector2(_ROW_WIDTH, 20)
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(_leave)
	main.add_child(_back_button)

	var footer := Label.new()
	footer.add_theme_font_override("font", UiTheme.stat())
	footer.add_theme_font_size_override("font_size", 8)
	footer.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	footer.text = "UP/DOWN  BROWSE      ENTER  WATCH      ESC  BACK      MOUSE OK"
	main.add_child(footer)


## A centred Silkscreen micro-line, the panel's one kind of explanatory text.
func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.stat())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	label.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Rebuilds the rows for `summaries`. The buttons are made fresh each time rather
## than pooled: the list changes length between openings, and a stale row is a row
## that plays the wrong match.
func _fill(summaries: Array[ReplayFile.Summary]) -> void:
	for button in _row_buttons:
		button.queue_free()
	_row_buttons.clear()
	_paths = PackedStringArray()
	_empty.visible = summaries.is_empty()
	for summary in summaries:
		var button := Button.new()
		button.text = _row_text(summary)
		UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY, null, UiTheme.SIZE_BUTTON)
		button.custom_minimum_size = Vector2(_ROW_WIDTH, _ROW_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var index := _paths.size()
		button.pressed.connect(func() -> void: _pick(index))
		_rows.add_child(button)
		_row_buttons.append(button)
		_paths.append(summary.path)


## "Ironworks · Alina Ward vs Cass Orlov   —   2026-08-01 19:06". The label is
## what the recording called itself; the board is only named again when it did
## not name one, which is what an older or hand-made file looks like.
func _row_text(summary: ReplayFile.Summary) -> String:
	var name := summary.label
	if name.is_empty():
		name = MapCatalog.display_name(summary.map_path)
	var when := summary.recorded.replace("T", " ")
	return name if when.is_empty() else "%s   —   %s" % [name, when]


func _pick(index: int) -> void:
	if index < 0 or index >= _paths.size():
		return
	hide()
	picked.emit(_paths[index])


func _leave() -> void:
	hide()
	cancelled.emit()
