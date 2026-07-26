class_name CommanderHudChip
extends PanelContainer
## The compact battle-HUD identity of the side in hand: a portrait, the
## commander's name and Command Power, and a charge meter whose colour and label
## say which of four states it is in — charging, ready, active, or (for a side
## playing without a power) hidden entirely, so the HUD looks exactly as it did
## before commanders existed.
##
## The same "portrait + faction tint + exact power copy" treatment as the full
## card and the activation banner, at chip density (plan G1's "one component,
## three densities"). The side's resolved theme is handed in by BattleView, so a
## mirror commander borrows the same colour here as it does on the board. The
## numbers come straight from the live CommanderState. Presentation only — the
## Fire button is wired by Battle to PowerCommand, which stays the single
## authority on legality.

const _READY := Color(0.957, 0.745, 0.196)
const _ACTIVE := Color(0.451, 0.808, 0.435)
const _PORTRAIT := 48
const _WIDTH := 278
## How far the chip fades while it is standing on the tile the player is looking
## at, and how long it takes to get there and back.
const _DIM_ALPHA := 0.25
const _FADE_TIME := 0.12

## Wired by Battle to _fire_command_power. Lives in the chip so the fire control
## sits with the readiness it reflects.
var fire_button: Button

var _built := false
## True while the chip covers the cursor's tile — BattleView owns that geometry
## and tells us. Pointing the mouse at the chip overrides it: the Fire button has
## to stay legible under the hand that is about to click it.
var _covering_cursor := false
var _hovered := false
var _fade: Tween
var _field: Panel
var _portrait: TextureRect
var _name_label: Label
var _sub_label: Label
var _meter: ProgressBar
var _state_label: Label
var _hint_label: Label


func _ready() -> void:
	_build()


func _build() -> void:
	custom_minimum_size = Vector2(_WIDTH, 0)
	add_theme_stylebox_override("panel", _box(UiTheme.SLATE_900, CommanderVisuals.HARD_BORDER))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	_field = Panel.new()
	_field.custom_minimum_size = Vector2(_PORTRAIT, _PORTRAIT + 12)
	_field.clip_contents = true
	row.add_child(_field)
	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field.add_child(_portrait)

	var data := VBoxContainer.new()
	data.add_theme_constant_override("separation", 2)
	data.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(data)

	_name_label = _display(10, UiTheme.WHITE, true)
	data.add_child(_name_label)
	_sub_label = _mono(6, UiTheme.NEUTRAL_LIGHT)
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	data.add_child(_sub_label)

	_meter = ProgressBar.new()
	_meter.custom_minimum_size = Vector2(0, 7)
	_meter.max_value = 1.0
	_meter.step = 0.001
	_meter.show_percentage = false
	_meter.add_theme_stylebox_override("background", _flat(CommanderVisuals.HARD_BORDER))
	data.add_child(_meter)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	_state_label = _mono(7, UiTheme.WHITE, true)
	_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_state_label)
	fire_button = Button.new()
	fire_button.text = "FIRE"
	# The battle's keyboard route stays the map menu: confirm on empty ground,
	# then its first row. Letting this button take focus would make Enter silently
	# disappear when the battle is in a state PowerCommand refuses. The visible
	# hint below teaches the reliable route instead.
	fire_button.focus_mode = Control.FOCUS_NONE
	fire_button.tooltip_text = (
		"Mouse: fire now. " + "Keyboard: Enter on an empty tile, then choose the power."
	)
	_style_fire_button()
	foot.add_child(fire_button)
	data.add_child(foot)

	_hint_label = _mono(6, UiTheme.NEUTRAL_LIGHT, true)
	data.add_child(_hint_label)

	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))

	_built = true


## Brings the chip in step with the side in hand. `theme` and `side_name` come
## from SideIdentity rather than being re-derived from the commander, so mirror
## matches wear their borrowed board colour while keeping their faction name.
## A computer commander fills the same meter, but gets an explicit AI-controlled
## line instead of a control the viewing player cannot use.
func update_state(
	co_state: CommanderState, is_ai: bool, theme: CommanderVisuals.FactionTheme, side_name: String
) -> void:
	if not _built:
		return
	var commander: CommanderType = co_state.type
	if not commander.has_power():
		hide()
		return
	show()
	_apply_alpha()  # a chip that hid mid-fade comes back at the right opacity
	add_theme_stylebox_override("panel", _box(theme.color_dark, _state_border(co_state, theme)))
	_field.add_theme_stylebox_override("panel", _flat(theme.color))
	_portrait.texture = CommanderVisuals.portrait_for(commander)
	_name_label.add_theme_color_override("font_color", theme.ink)
	_name_label.text = commander.display_name.to_upper()
	_sub_label.add_theme_color_override("font_color", Color(theme.ink, 0.82))
	_sub_label.text = "%s · %s" % [side_name.to_upper(), commander.power_name.to_upper()]

	if co_state.power_active:
		_meter.value = 1.0
		_set_fill(_ACTIVE)
		_state_label.add_theme_color_override("font_color", _ACTIVE)
		_state_label.text = "ACTIVE · %s" % commander.power_name.to_upper()
	elif co_state.is_ready():
		_meter.value = 1.0
		_set_fill(_READY)
		_state_label.add_theme_color_override("font_color", _READY)
		_state_label.text = "READY · POWER CHARGED"
	else:
		_meter.value = co_state.charge_ratio()
		_set_fill(theme.color_light)
		_state_label.add_theme_color_override("font_color", theme.ink)
		_state_label.text = "CHARGE · %d / %d" % [co_state.charge, commander.power_cost]

	fire_button.visible = co_state.is_ready() and not is_ai
	fire_button.disabled = not co_state.is_ready() or is_ai
	_hint_label.add_theme_color_override("font_color", theme.ink)
	_hint_label.visible = is_ai or (co_state.is_ready() and not co_state.power_active)
	if is_ai:
		_hint_label.text = "AI CONTROLLED · FIRES AUTOMATICALLY"
	else:
		_hint_label.text = "ENTER ON EMPTY TILE · POWER"


## Told by BattleView on every cursor move whether the chip is standing on the
## tile being looked at. Fades rather than moves: the chip keeps its corner and
## its readout, and the map underneath stays readable.
func set_covering_cursor(covering: bool) -> void:
	if covering == _covering_cursor:
		return
	_covering_cursor = covering
	_apply_alpha()


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_apply_alpha()


func _apply_alpha() -> void:
	var target := _DIM_ALPHA if _covering_cursor and not _hovered else 1.0
	# Cancel the old destination before comparing the current value. A cursor
	# that left before the first fade tick still had alpha 1.0, so the old order
	# returned here and left its live tween driving the chip down to 0.25 anyway.
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if is_equal_approx(modulate.a, target):
		return
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", target, _FADE_TIME)


func _set_fill(color: Color) -> void:
	_meter.add_theme_stylebox_override("fill", _flat(color))


func _state_border(co_state: CommanderState, theme: CommanderVisuals.FactionTheme) -> Color:
	if co_state.power_active:
		return _ACTIVE
	if co_state.is_ready():
		return _READY
	return theme.color_light


func _mono(size: int, color: Color, bold := false) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UiTheme.stat(bold))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _display(size: int, color: Color, bold := false) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UiTheme.display(bold))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _style_fire_button() -> void:
	fire_button.add_theme_font_override("font", UiTheme.stat(true))
	fire_button.add_theme_font_size_override("font_size", 7)
	fire_button.add_theme_stylebox_override("normal", _button_box(_READY))
	fire_button.add_theme_stylebox_override("hover", _button_box(_READY.lightened(0.12)))
	fire_button.add_theme_stylebox_override("pressed", _button_box(_READY.darkened(0.10)))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		fire_button.add_theme_color_override(state, CommanderVisuals.HARD_BORDER)


func _button_box(color: Color) -> StyleBoxFlat:
	var box := UiTheme.flat(color)
	box.border_color = CommanderVisuals.HARD_BORDER
	box.set_border_width_all(1)
	box.set_content_margin_all(3)
	return box


func _flat(color: Color) -> StyleBoxFlat:
	return UiTheme.flat(color)


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := _flat(bg)
	box.border_color = border
	box.set_border_width_all(2)
	box.set_content_margin_all(6)
	return UiTheme.hard_shadow(box)
