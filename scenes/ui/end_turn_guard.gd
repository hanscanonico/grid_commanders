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
## Scrolling the ready-unit list is the guard's own, and the board's direction
## actions carry keyboard events only, so it answers Godot's built-in pair — the
## one a pad's d-pad and left stick arrive as — alongside them. Picking an action
## is not here: left and right belong to Control focus, wired in _build.
const SCROLL_ACTIONS: Dictionary = {
	&"cursor_up": -1,
	&"ui_up": -1,
	&"cursor_down": 1,
	&"ui_down": 1,
}

var _built := false
var _title_label: Label
var _count_label: Label
var _body_label: Label
var _unit_label: Label
var _list: ScrollContainer
var _review_button: Button
var _end_button: Button
var _buttons: Array[Button] = []
## One scroll line or one button step per directional gesture; see
## DirectionalInput.
var _dirs := DirectionalInput.new()


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
	var scrolled := _dirs.step(event, SCROLL_ACTIONS.keys())
	if not visible:
		return
	if not scrolled.is_empty():
		get_viewport().set_input_as_handled()
		_scroll_list(SCROLL_ACTIONS[scrolled])
	elif event.is_action_pressed(&"confirm"):
		get_viewport().set_input_as_handled()
		# Focus navigation owns which action is armed, so the focused button —
		# not a parallel index — decides what confirm takes.
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


## Scrolls the ready-unit list a line at a time, so every name is reachable
## without a mouse. ScrollContainer clamps the value, so a list that already
## fits — or an edge — simply does not move; picking an action is left/right's.
func _scroll_list(delta: int) -> void:
	_list.scroll_vertical += delta * maxi(_unit_label.get_line_height(), 1)


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
	# Two buttons that wrap into each other both ways, so focus navigation always
	# has a neighbour to move to and no press can fall through it to a second
	# opinion. Left and right have exactly this one owner.
	_review_button.focus_neighbor_left = _review_button.get_path_to(_end_button)
	_review_button.focus_neighbor_right = _review_button.get_path_to(_end_button)
	_end_button.focus_neighbor_left = _end_button.get_path_to(_review_button)
	_end_button.focus_neighbor_right = _end_button.get_path_to(_review_button)
	_built = true
