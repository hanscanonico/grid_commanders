class_name EditorNewMapPanel
extends Control
## The three questions a new board is opened with: how wide, how tall, and how
## many armies it is meant to seat.
##
## The seat count is a *plan*, not a fact — a board's roster is read off the
## seats its properties and units name (four-players D1), so nothing here can
## decide it. It is carried so the editor can say what the draft is still short
## of; ownership is what will make it true.

signal created(board_size: Vector2i, seats: int)
## The author would rather start from a board that already exists.
signal open_asked
signal cancelled

## The smallest board worth authoring — under this there is no room for two HQs
## and the ground between them — and the largest one a player can still pan
## across. Bulwark, the biggest board that ships, is 49x32.
const MIN_SIDE := 8
const MAX_SIDE := 60
const DEFAULT_SIZE := Vector2i(20, 15)
## The width of the page's controls. Narrower than a reading column on purpose:
## these rows are three words and a number, and a caption stranded a page-width
## from the buttons that move it reads as two separate controls.
const _ROW_WIDTH := 180

var _size := DEFAULT_SIZE
var _seats: int = MapData.DEFAULT_TEAMS.size()
var _width_value: Label
var _height_value: Label
var _create_button: Button


## Every board side the editor offers, so a stepper can never walk a draft to a
## size `MapDocument` would have to be resized out of.
static func clamp_side(value: int) -> int:
	return clampi(value, MIN_SIDE, MAX_SIDE)


## The seats a board may plan for: a match is at least a duel, and the board
## format seats no fifth army (MapData.PLAYER_TEAMS).
static func clamp_seats(value: int) -> int:
	return clampi(value, MapData.DEFAULT_TEAMS.size(), MapData.PLAYER_TEAMS.size())


func _ready() -> void:
	_build()
	hide()


## Opens the page on the size it was last left at.
func begin() -> void:
	show()
	_create_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if TransitionInput.dismissed_by_cancel(self, event):
		hide()
		cancelled.emit()


func _build() -> void:
	UiKit.page_veil(self)
	var main := UiKit.page_body(self, 6)
	main.add_child(UiKit.page_title("NEW MAP"))
	main.add_child(UiKit.page_note("Paint the ground first, or open a board you already have."))

	_width_value = UiKit.micro_label("")
	_height_value = UiKit.micro_label("")
	main.add_child(_size_row("Width", _width_value, func(step: int) -> void: _step_width(step)))
	main.add_child(_size_row("Height", _height_value, func(step: int) -> void: _step_height(step)))
	main.add_child(_build_seats())
	_show_size()

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UiTheme.GAP)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_create_button = UiKit.action_button(
		"Create", "", UiTheme.ButtonVariant.PRIMARY, UiTheme.menu_identity().theme(1), 96
	)
	_create_button.pressed.connect(_confirm)
	actions.add_child(UiKit.touchable(_create_button))
	var open_button := UiKit.action_button("Open", "", UiTheme.ButtonVariant.SECONDARY, null, 96)
	open_button.pressed.connect(
		func() -> void:
			hide()
			open_asked.emit()
	)
	actions.add_child(UiKit.touchable(open_button))
	var back := UiKit.action_button("Cancel", "", UiTheme.ButtonVariant.GHOST, null, 96)
	back.pressed.connect(
		func() -> void:
			hide()
			cancelled.emit()
	)
	actions.add_child(UiKit.touchable(back))
	main.add_child(actions)
	main.add_child(UiKit.key_legend("ENTER  CREATE      ESC  BACK      MOUSE OK"))


## One measurement, at this page's row width.
func _size_row(name_text: String, value: Label, on_step: Callable) -> Control:
	var row := UiKit.stepper(name_text, value, on_step)
	row.custom_minimum_size = Vector2(_ROW_WIDTH, 0)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return row


func _build_seats() -> Control:
	var labels := PackedStringArray()
	for seats in range(MapData.DEFAULT_TEAMS.size(), MapData.PLAYER_TEAMS.size() + 1):
		labels.append("%d" % seats)
	var group := UiKit.segment(
		"Armies",
		labels,
		_seats - MapData.DEFAULT_TEAMS.size(),
		UiTheme.menu_identity().theme(1).color,
		"How many armies this board is meant to seat",
		"Its properties are what will actually seat them",
		func(index: int) -> void: _seats = clamp_seats(index + MapData.DEFAULT_TEAMS.size())
	)
	group.custom_minimum_size = Vector2(_ROW_WIDTH, 0)
	group.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return group


func _step_width(step: int) -> void:
	_size.x = clamp_side(_size.x + step)
	_show_size()


func _step_height(step: int) -> void:
	_size.y = clamp_side(_size.y + step)
	_show_size()


func _show_size() -> void:
	_width_value.text = "%d" % _size.x
	_height_value.text = "%d" % _size.y


func _confirm() -> void:
	hide()
	created.emit(_size, _seats)
