class_name ActionMenu
extends PanelContainer
## Minimal AW-style action menu (M2: Wait / Cancel; Fire etc. arrive in M3).
## The battle scene opens it with a list of actions; it emits the chosen id.
## Keyboard or pad: cursor up/down + confirm/cancel. Mouse: click a row.
##
## Dressed as slate chrome, like the two docked bars it opens between: the rows
## are ghost buttons on a dark panel, and the armed one takes the design system's
## cream — a fill rather than a brightening, so which row confirm would take is
## legible over any terrain the menu happens to be standing on.

signal action_chosen(action: StringName)

## How far the menu stays off the edges of the board band.
const MARGIN := 4.0
## Which way each direction action walks the highlight.
const ROW_ACTIONS: Dictionary = {
	&"cursor_up": -1,
	&"cursor_down": 1,
}
## Which way each direction action steps the armed row's own value (COM-229).
## A row carries one by handing over a `cycle` callable that takes the step and
## answers with the row's new label; a row that hands over none has no value to
## step, so left and right stay unclaimed there and keep whatever they meant to
## whoever opened the menu. The menu never reads the setting itself — it asks the
## row, the same way every row above is gated by the authority that owns it.
const VALUE_ACTIONS: Dictionary = {
	&"cursor_left": -1,
	&"cursor_right": 1,
}

@onready var rows: VBoxContainer = %MenuRows

var _ids: Array[StringName] = []
var _labels: Array[String] = []
var _disabled: Array[bool] = []
var _cycles: Array[Callable] = []
var _index := 0
## One highlight step per directional gesture; see DirectionalInput.
var _dirs := DirectionalInput.new()


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.dark_panel_box())


## actions: [{id, label, disabled?: bool, icon?: Texture2D, cycle?: Callable}, ...]
## At least one entry must be enabled (menus always include Cancel).
## `icon` draws to the left of the label; rows that omit it in an illustrated
## menu get a spacer so every label still starts in the same column. `cycle` makes
## the row a value row — see VALUE_ACTIONS.
func open(actions: Array[Dictionary], screen_pos: Vector2) -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	_ids.clear()
	_labels.clear()
	_disabled.clear()
	_cycles.clear()
	var spacer := _spacer_icon(actions)
	for entry: Dictionary in actions:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		var icon: Texture2D = entry.get("icon", spacer)
		if icon != null:
			button.add_theme_constant_override("icon_max_width", icon_cap(icon))
			button.custom_minimum_size.y = UiTheme.MENU_ICON_ROW
		button.icon = icon
		var id: StringName = entry.id
		var is_disabled: bool = entry.get("disabled", false)
		button.disabled = is_disabled
		button.pressed.connect(func() -> void: choose(id))
		rows.add_child(UiKit.touchable(button))
		_ids.append(id)
		_labels.append(entry.label)
		_disabled.append(is_disabled)
		_cycles.append(entry.get("cycle", Callable()))
	_index = -1
	_step_index(1)
	_update_labels()
	position = screen_pos
	show()
	_place()


func close() -> void:
	hide()


## Whether the menu on screen carries a value row. The key legend asks this rather
## than asking which menu was opened, so left and right are advertised exactly
## where a row answers to them. A closed menu carries nothing: its rows are the
## last menu's until the next open replaces them.
func has_value_rows() -> bool:
	return visible and _cycles.any(func(cycle: Callable) -> bool: return cycle.is_valid())


## Every recognised action claims the event *before* it runs, not after: a row may
## now leave the match, and the scene change frees the viewport out from under this
## handler, so a trailing set_input_as_handled() would be called on nothing. The
## menu has consumed the press the moment it recognises the action anyway — what
## the chosen row then does is not the input layer's business. An unrecognised
## event still falls through unclaimed.
func _unhandled_input(event: InputEvent) -> void:
	var dir := _dirs.step(event, ROW_ACTIONS.keys() + VALUE_ACTIONS.keys())
	if not visible:
		return
	if ROW_ACTIONS.has(dir):
		get_viewport().set_input_as_handled()
		_step_index(ROW_ACTIONS[dir])
		_update_labels()
	elif VALUE_ACTIONS.has(dir) and _cycles[_index].is_valid():
		get_viewport().set_input_as_handled()
		_step_value(_index, VALUE_ACTIONS[dir])
	elif event.is_action_pressed(&"confirm"):
		get_viewport().set_input_as_handled()
		choose(_ids[_index])
	elif event.is_action_pressed(&"cancel"):
		get_viewport().set_input_as_handled()
		choose(&"cancel")


## Public so scripted drivers (screenshot demos) exercise the same path as
## the buttons and keyboard.
##
## A closed menu chooses nothing. Whoever opened it may close it from outside
## the menu flow — firing a Command Power from the HUD abandons the move the
## menu belonged to — and the rows left behind would otherwise still act, on a
## selection that is gone.
##
## A value row is never handed out as a chosen action: it answers a confirm the
## way it answers a right press, below.
func choose(id: StringName) -> void:
	if not visible:
		return
	var i := _ids.find(id)
	if i >= 0 and _disabled[i]:
		return
	if i >= 0 and _cycles[i].is_valid():
		_step_value(i, 1)
		return
	action_chosen.emit(id)


## Steps a value row where it stands, and leaves the menu up over it (COM-246).
## Confirm and a right press are one gesture here: a confirm that stepped the
## setting and then took the menu away with it left a player who pressed ENTER on
## "Speed: Normal" meaning to *pick* it one tier faster, with the row that says
## so gone and nothing left to step back with — which is how a device ends up
## playing at Instant nobody chose. The stepped row is armed too, so a click and
## the two arrow keys act on the same row.
func _step_value(i: int, step: int) -> void:
	_index = i
	_labels[i] = _cycles[i].call(step)
	_update_labels()


## The width that lands a row's artwork inside UiTheme.MENU_ICON's square slot.
## `Button.icon` is not a TextureRect, so STRETCH_KEEP_ASPECT is not on offer;
## what the row has is `icon_max_width`, which scales the icon by width and
## adjusts the height to its ratio. Capping at the slot therefore fits anything
## square or wider — a taller-than-wide sprite has to be capped at the width its
## own ratio puts at the slot's height instead, or it would stand out of the row.
## Public and pure, like PathArrow.segments, so the fit is checked without a scene
## — today's art is square, so no capture can answer for a shape it does not hold.
static func icon_cap(icon: Texture2D) -> int:
	var size := icon.get_size()
	if size.x <= 0.0 or size.y <= size.x:
		return UiTheme.MENU_ICON
	return maxi(1, int(UiTheme.MENU_ICON * size.x / size.y))


## Transparent stand-in the size icons are capped to, so icon-less rows keep
## their labels in the same column. Null when no row has an icon at all: plain
## verb menus then draw exactly as they did before.
func _spacer_icon(actions: Array[Dictionary]) -> Texture2D:
	if not actions.any(func(entry: Dictionary) -> bool: return entry.get("icon") != null):
		return null
	var image := Image.create(UiTheme.MENU_ICON, UiTheme.MENU_ICON, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return ImageTexture.create_from_image(image)


## Advances the highlight, skipping disabled rows.
func _step_index(delta: int) -> void:
	for attempt in _ids.size():
		_index = wrapi(_index + delta, 0, _ids.size())
		if not _disabled[_index]:
			return


## The armed row, marked twice: the two-character cursor the whole flow is written
## around, and the cream fill that carries it. Both are rewritten on every step
## rather than tracked, so the row that was armed cannot keep the dress.
func _update_labels() -> void:
	for i in rows.get_child_count():
		var button := rows.get_child(i) as Button
		button.text = ("> " if i == _index else "  ") + _labels[i]
		UiTheme.apply_button(
			button, UiTheme.ButtonVariant.SECONDARY if i == _index else UiTheme.ButtonVariant.GHOST
		)


## Settles the menu inside the *board band* — the strip the docked HUD bars leave
## over — rather than inside the window. The bars are opaque, so a menu that slid
## under one would be unreadable rather than merely off-centre, and clamping
## against the band is what the old dodge around the floating commander chip
## became: with nothing persistent left over the map, the only thing a menu has to
## stay clear of is the chrome.
##
## How much chrome sits below the board is `MobileDock`'s answer, not a constant
## here: on a touch build the bottom bar rides up by the dock's height, and a menu
## clamped against the desktop band covered both.
func _place() -> void:
	# A PanelContainer grows to fit its rows and never shrinks back on its own, so
	# a short menu opened where a tall one just was keeps the tall one's panel
	# standing behind it — the two-row abandon confirmation under the seven-row map
	# menu is the flow that shows it. Sizing down is also what makes the clamp below
	# honest: it then measures the panel the player actually sees.
	reset_size()
	var view := get_viewport().get_visible_rect().size
	var top_left := Vector2(MARGIN, UiTheme.HUD_TOP_H + MARGIN)
	var below := UiTheme.HUD_BOTTOM_H + MobileDock.height()
	var max_pos := (view - size - Vector2(MARGIN, below + MARGIN)).max(top_left)
	position = position.clamp(top_left, max_pos)
