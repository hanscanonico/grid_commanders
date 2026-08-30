class_name EditorOpenPanel
extends Control
## Which board to open: one of the author's own, or a shipped one to start from.
##
## Both lists are the same thing to the editor, because a board is a board —
## `MapDocument.from_map` seeds a draft from any of them. What differs is the
## name it comes with: a board of the author's own opens under its own name and
## saves straight back over itself, while a shipped one opens nameless, since
## `UserMaps` refuses a name the game already ships and an author who found that
## out at the save dialog would have painted a whole board first.

## The board to open, by file path.
signal chosen(path: String)
signal cancelled

## A row's height and the inset its words sit at — the palette's, so every list
## in the editor is one kind of list.
const ROW_HEIGHT := EditorPalette.ROW_HEIGHT
const ROW_INSET := EditorPalette.ROW_INSET
## The reading column, the width the editor's other two pages stand at.
const _ROW_WIDTH := 180

var _rows: VBoxContainer
var _first: Button


func _ready() -> void:
	_build()
	hide()


## Opens the page on what is on disk right now — a board saved a minute ago is
## in the list, and one deleted outside the game is not.
func begin() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_first = null
	_add_group("Your maps")
	var mine := UserMaps.list()
	for map_name in mine:
		_add_row(map_name.capitalize(), UserMaps.path_for(map_name))
	if mine.is_empty():
		_rows.add_child(UiKit.help_label("None yet — start one from a board below."))
	_add_group("Start from a shipped board")
	for path in MapCatalog.paths():
		_add_row(MapCatalog.display_name(path), path)
	show()
	if _first != null:
		_first.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if TransitionInput.dismissed_by_cancel(self, event):
		hide()
		cancelled.emit()


func _build() -> void:
	UiKit.page_veil(self)
	var main := UiKit.page_body(self, 6)
	main.add_child(UiKit.page_title("OPEN A BOARD"))
	main.add_child(UiKit.page_note("A shipped board opens as a copy under a new name."))

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 1)
	var frame := UiKit.vscroll()
	frame.follow_focus = true
	frame.custom_minimum_size = Vector2(_ROW_WIDTH, 0)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_child(_rows)
	main.add_child(frame)

	var back := UiKit.action_button("Cancel", "", UiTheme.ButtonVariant.GHOST, null, 96)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(
		func() -> void:
			hide()
			cancelled.emit()
	)
	main.add_child(back)
	main.add_child(UiKit.key_legend("ENTER  OPEN      ESC  BACK"))


func _add_group(caption: String) -> void:
	_rows.add_child(UiKit.micro_label(caption))


func _add_row(caption: String, path: String) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.pressed.connect(
		func() -> void:
			hide()
			chosen.emit(path)
	)
	UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY, null, UiTheme.SIZE_BUTTON)
	var face := ListRow.face(ROW_INSET)
	face.add_child(ListRow.cell(caption.to_upper(), UiTheme.INK))
	button.add_child(face)
	_rows.add_child(UiKit.touchable(button))
	if _first == null:
		_first = button
