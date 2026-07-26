class_name ActionMenu
extends PanelContainer
## Minimal AW-style action menu (M2: Wait / Cancel; Fire etc. arrive in M3).
## The battle scene opens it with a list of actions; it emits the chosen id.
## Keyboard: cursor up/down + confirm/cancel. Mouse: click a row.

signal action_chosen(action: StringName)

## Row artwork is authored at the atlas's own resolution (64px for the unit
## sprites), which would dwarf a 10px label, so every icon is capped to one
## world tile wide. Aspect ratio is preserved, so square art lands at 16x16.
const ICON_PX := 16
## How far the menu stays off the edge of the frame, and off anything it dodges.
const MARGIN := 4.0

@onready var rows: VBoxContainer = %MenuRows

var _ids: Array[StringName] = []
var _labels: Array[String] = []
var _disabled: Array[bool] = []
var _index := 0
## A screen rect this menu must not cover, handed in by whoever opens it. Empty
## for the menus that have nothing to dodge.
var _avoid := Rect2()


## actions: [{id: StringName, label: String, disabled?: bool, icon?: Texture2D}, ...]
## At least one entry must be enabled (menus always include Cancel).
## `icon` draws to the left of the label; rows that omit it in an illustrated
## menu get a spacer so every label still starts in the same column.
## `avoid` is a HUD rect the rows must stay clear of — see _place.
func open(actions: Array[Dictionary], screen_pos: Vector2, avoid := Rect2()) -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	_ids.clear()
	_labels.clear()
	_disabled.clear()
	var spacer := _spacer_icon(actions)
	for entry: Dictionary in actions:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 10)
		button.add_theme_constant_override("icon_max_width", ICON_PX)
		button.icon = entry.get("icon", spacer)
		var id: StringName = entry.id
		var is_disabled: bool = entry.get("disabled", false)
		button.disabled = is_disabled
		button.pressed.connect(func() -> void: choose(id))
		rows.add_child(button)
		_ids.append(id)
		_labels.append(entry.label)
		_disabled.append(is_disabled)
	_index = -1
	_step_index(1)
	_update_labels()
	_avoid = avoid
	position = screen_pos
	show()
	_place()


func close() -> void:
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cursor_up", true):
		_step_index(-1)
		_update_labels()
	elif event.is_action_pressed(&"cursor_down", true):
		_step_index(1)
		_update_labels()
	elif event.is_action_pressed(&"confirm"):
		choose(_ids[_index])
	elif event.is_action_pressed(&"cancel"):
		choose(&"cancel")
	else:
		return
	get_viewport().set_input_as_handled()


## Public so scripted drivers (screenshot demos) exercise the same path as
## the buttons and keyboard.
##
## A closed menu chooses nothing. Whoever opened it may close it from outside
## the menu flow — firing a Command Power from the HUD abandons the move the
## menu belonged to — and the rows left behind would otherwise still act, on a
## selection that is gone.
func choose(id: StringName) -> void:
	if not visible:
		return
	var i := _ids.find(id)
	if i >= 0 and _disabled[i]:
		return
	action_chosen.emit(id)


## Transparent stand-in the size icons are capped to, so icon-less rows keep
## their labels in the same column. Null when no row has an icon at all: plain
## verb menus then draw exactly as they did before.
func _spacer_icon(actions: Array[Dictionary]) -> Texture2D:
	if not actions.any(func(entry: Dictionary) -> bool: return entry.get("icon") != null):
		return null
	var image := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return ImageTexture.create_from_image(image)


## Advances the highlight, skipping disabled rows.
func _step_index(delta: int) -> void:
	for attempt in _ids.size():
		_index = wrapi(_index + delta, 0, _ids.size())
		if not _disabled[_index]:
			return


func _update_labels() -> void:
	for i in rows.get_child_count():
		var button := rows.get_child(i) as Button
		button.text = ("> " if i == _index else "  ") + _labels[i]


## Settles the menu inside the frame and, when it was given one, off the `avoid`
## rect. Below it by preference — the map menu still reads downward from the
## cursor — and beside it when the rows are too tall to fit under. A menu with
## nowhere clear to go keeps the frame over the dodge: rows off screen cannot be
## read at all, rows behind a panel can at least be stepped through.
func _place() -> void:
	# Size is only valid one frame after the buttons were added.
	await get_tree().process_frame
	if not visible:
		return
	var view := get_viewport().get_visible_rect().size
	position = _inside(position, view)
	if not _avoid.intersects(Rect2(position, size)):
		return
	var below := _inside(Vector2(position.x, _avoid.end.y + MARGIN), view)
	var beside := _inside(Vector2(_avoid.end.x + MARGIN, position.y), view)
	if not _avoid.intersects(Rect2(below, size)):
		position = below
	elif not _avoid.intersects(Rect2(beside, size)):
		position = beside


func _inside(pos: Vector2, view: Vector2) -> Vector2:
	var margin := Vector2(MARGIN, MARGIN)
	return pos.clamp(margin, (view - size - margin).max(margin))
