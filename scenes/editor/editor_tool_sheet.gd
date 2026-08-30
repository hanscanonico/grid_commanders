class_name EditorToolSheet
extends Control
## The two brush columns as a sheet a finger opens, for the build that is played
## with one (mobile plan D8).
##
## On a desktop the palette and the sidebar flank the board and are always up; on
## a phone the two of them are more than half the width of a landscape screen, and
## what is left is a board too small to aim at. So on a touch build they stand in
## a page instead, over the board rather than beside it — which costs a press to
## open and gives the whole screen back to the thing being painted.
##
## It holds no brush and decides nothing: the columns are the editor's, handed
## over as they are built, and picking from one closes the sheet because the very
## next press is meant for the board.

signal closed
## The one brush that is not in a column: it clears a cell rather than laying
## anything, so it has no swatch and no row to be picked from.
signal erase_asked

## The columns' width in here. They are drawn narrow enough to flank a board, and
## a sheet has no such constraint — so they take a reading width, which is also
## what puts a row's whole plate under a thumb.
const COLUMN_W := 150

var _erase: Button


## Takes the columns the editor built and stands them side by side.
func configure(columns: Array[Control]) -> void:
	UiKit.page_veil(self)
	var main := UiKit.page_body(self, 6)
	main.add_child(UiKit.page_title("BRUSHES"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.GAP)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for column in columns:
		column.custom_minimum_size = Vector2(COLUMN_W, 0)
		row.add_child(column)
	main.add_child(row)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UiTheme.GAP)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_erase = UiKit.action_button("Erase", "", UiTheme.ButtonVariant.SECONDARY, null, 96)
	_erase.pressed.connect(func() -> void: erase_asked.emit())
	actions.add_child(UiKit.touchable(_erase))
	var back := UiKit.action_button("Paint", "", UiTheme.ButtonVariant.PRIMARY, null, 96)
	back.pressed.connect(close)
	actions.add_child(UiKit.touchable(back))
	main.add_child(actions)
	hide()


## Whether the Erase brush is the one in hand, so a sheet opened again shows the
## brush the board is actually painting with.
func show_erase(active: bool) -> void:
	var variant := UiTheme.ButtonVariant.PRIMARY if active else UiTheme.ButtonVariant.SECONDARY
	UiTheme.apply_button(_erase, variant, null, UiTheme.SIZE_BUTTON)


func begin() -> void:
	show()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if TransitionInput.dismissed_by_cancel(self, event):
		close()
