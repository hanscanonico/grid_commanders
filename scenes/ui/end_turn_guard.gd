class_name EndTurnGuard
extends Control
## A human-side confirmation shown only when End Turn would discard ready unit
## actions. Battle decides which units are ready and still owns the command; this
## modal only names the cost and returns one of two explicit choices.

signal review_requested
signal end_requested

const PANEL_W := 300.0
const LIST_H := 78.0
const PAD := 8

var _built := false
var _title_label: Label
var _count_label: Label
var _body_label: Label
var _unit_label: Label
var _list: ScrollContainer
var _review_button: Button
var _end_button: Button
var _buttons: Array[Button] = []


func _ready() -> void:
	_build()
	hide()


## Opens over the board with Review armed, so the Enter that reached End Turn
## cannot fall through onto the destructive choice. Unit coordinates use the
## board's own zero-based cells, matching map data and the ticket's notation.
func open(day: int, ready_units: Array[Unit], side_theme: CommanderVisuals.FactionTheme) -> void:
	if not _built:
		_build()
	_title_label.text = "END DAY %d?" % day
	_count_label.text = "%d READY" % ready_units.size()
	_body_label.text = (
		"One unit can still act."
		if ready_units.size() == 1
		else "%d units can still act." % ready_units.size()
	)
	var lines := PackedStringArray()
	for unit in ready_units:
		lines.append("%s at (%d,%d)" % [unit.type.display_name, unit.cell.x, unit.cell.y])
	_unit_label.text = "\n".join(lines)
	UiTheme.apply_button(_review_button, UiTheme.ButtonVariant.PRIMARY, side_theme)
	_list.scroll_vertical = 0
	show()
	_review_button.grab_focus.call_deferred()


func close() -> void:
	hide()
	for button in _buttons:
		button.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cursor_up", true):
		get_viewport().set_input_as_handled()
		if not _scroll_list(-1):
			_step(-1)
	elif event.is_action_pressed(&"cursor_down", true):
		get_viewport().set_input_as_handled()
		if not _scroll_list(1):
			_step(1)
	elif event.is_action_pressed(&"cursor_left", true):
		get_viewport().set_input_as_handled()
		_step(-1)
	elif event.is_action_pressed(&"cursor_right", true):
		get_viewport().set_input_as_handled()
		_step(1)
	elif event.is_action_pressed(&"confirm"):
		get_viewport().set_input_as_handled()
		# Native UI focus may have handled an arrow before this custom action
		# arrived, so the focused button — not a parallel index — decides.
		_choose(_end_button.has_focus())
	elif event.is_action_pressed(&"cancel"):
		get_viewport().set_input_as_handled()
		_choose(false)


func _choose(end_anyway: bool) -> void:
	close()
	if end_anyway:
		end_requested.emit()
	else:
		review_requested.emit()


## Native UI focus navigation moves between the two buttons on its own and marks
## those presses handled, so the focused button — never a parallel index — is
## where a step starts.
func _step(delta: int) -> void:
	var from := 0
	for index in _buttons.size():
		if _buttons[index].has_focus():
			from = index
			break
	_buttons[wrapi(from + delta, 0, _buttons.size())].grab_focus()


## Scrolls the ready-unit list a line at a time so a keyboard or controller can
## read past the modal's bounded band. Returns false when the list fits, leaving
## up/down to move between the two actions.
func _scroll_list(delta: int) -> bool:
	var bar := _list.get_v_scroll_bar()
	if bar.max_value <= bar.page:
		return false
	_list.scroll_vertical += delta * maxi(_unit_label.get_line_height(), 1)
	return true


func _build() -> void:
	if _built:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(UiTheme.SLATE_900, 0.82)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = UiTheme.HUD_TOP_H
	center.offset_bottom = -UiTheme.HUD_BOTTOM_H
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = PANEL_W
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box())
	center.add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiTheme.header_box())
	rows.add_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	header.add_child(header_row)
	_title_label = UiTheme.hud_label("", UiTheme.SIZE_TITLE, UiTheme.WHITE, true)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_title_label)
	_count_label = UiTheme.hud_label("", UiTheme.SIZE_SEGMENT, UiTheme.AMMO)
	header_row.add_child(_count_label)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", PAD)
	body_margin.add_theme_constant_override("margin_right", PAD)
	body_margin.add_theme_constant_override("margin_bottom", PAD)
	rows.add_child(body_margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body_margin.add_child(body)

	_body_label = UiTheme.hud_label("", UiTheme.SIZE_BODY, UiTheme.INK, true)
	body.add_child(_body_label)

	_list = ScrollContainer.new()
	_list.custom_minimum_size.y = LIST_H
	_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.focus_mode = Control.FOCUS_NONE
	_list.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	body.add_child(_list)
	_unit_label = UiTheme.hud_label("", UiTheme.SIZE_SEGMENT, UiTheme.INK)
	_unit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(_unit_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	body.add_child(actions)
	_review_button = Button.new()
	_review_button.text = "Review units"
	_review_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_review_button.pressed.connect(func() -> void: _choose(false))
	actions.add_child(_review_button)
	_end_button = Button.new()
	_end_button.text = "End anyway"
	_end_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_button.pressed.connect(func() -> void: _choose(true))
	UiTheme.apply_button(_end_button, UiTheme.ButtonVariant.SECONDARY)
	actions.add_child(_end_button)
	_buttons.assign([_review_button, _end_button])
	_built = true
