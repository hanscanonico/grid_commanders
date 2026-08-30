class_name EditorSaveDialog
extends Control
## The two things a saved board needs that painting it cannot say: what it is
## called, and the one line the map list shows under the name.
##
## It refuses a name before the disk does — `UserMaps.name_error` is the one
## authority on what a name may be, asked here on every keystroke, so an author
## learns a name is taken while they can still change it rather than after a
## write. It does not write anything itself and does not close on Save: the
## document belongs to the editor, so the editor writes it and either closes this
## page or hands back the refusal the disk gave, which is the only way a failed
## write can leave the author looking at the name that failed.

## The author asked for the draft to be written under these words.
signal saved(map_name: String, description: String)
signal cancelled

## The reading column's width — the same 180 the new-map page's rows stand at, so
## the two pages of the editor are one page-width.
const _ROW_WIDTH := 180
## How long a pitch may be. The map list shows one line under a name.
const MAX_DESCRIPTION := 72

var _name_field: LineEdit
var _description_field: LineEdit
var _notice: Label
var _save_button: Button


func _ready() -> void:
	_build()
	hide()


## Opens the page on the words the draft already carries.
func begin(map_name: String, description: String) -> void:
	_name_field.text = map_name
	_description_field.text = description
	_read_name()
	show()
	_name_field.grab_focus()


## Says why the write did not happen, leaving the page open on the name that
## failed.
func refuse(message: String) -> void:
	_say(message, UiTheme.DANGER)
	_save_button.disabled = true


func close() -> void:
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if TransitionInput.dismissed_by_cancel(self, event):
		hide()
		cancelled.emit()


func _build() -> void:
	UiKit.page_veil(self)
	var main := UiKit.page_body(self, 6)
	main.add_child(UiKit.page_title("SAVE MAP"))
	main.add_child(UiKit.page_note("Your maps are yours alone; nothing overwrites a shipped one."))

	_name_field = _field("Name", UserMaps.MAX_NAME_LENGTH)
	_name_field.text_changed.connect(func(_text: String) -> void: _read_name())
	_name_field.text_submitted.connect(func(_text: String) -> void: _confirm())
	main.add_child(_labelled("Name", _name_field))

	_description_field = _field("What makes this board", MAX_DESCRIPTION)
	_description_field.text_submitted.connect(func(_text: String) -> void: _confirm())
	main.add_child(_labelled("One line", _description_field))

	_notice = UiKit.page_note("")
	main.add_child(_notice)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UiTheme.GAP)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_save_button = UiKit.action_button(
		"Save", "", UiTheme.ButtonVariant.PRIMARY, UiTheme.menu_identity().theme(1), 96
	)
	_save_button.pressed.connect(_confirm)
	actions.add_child(_save_button)
	var back := UiKit.action_button("Cancel", "", UiTheme.ButtonVariant.GHOST, null, 96)
	back.pressed.connect(
		func() -> void:
			hide()
			cancelled.emit()
	)
	actions.add_child(back)
	main.add_child(actions)
	main.add_child(UiKit.key_legend("ENTER  SAVE      ESC  BACK"))


func _labelled(caption: String, field: LineEdit) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.custom_minimum_size = Vector2(_ROW_WIDTH, 0)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(UiKit.micro_label(caption))
	row.add_child(field)
	return row


## A typed line at the page's reading width. The dress is `UiKit.text_field`'s —
## the rename prompt in the map picker types into the same control.
func _field(placeholder: String, max_length: int) -> LineEdit:
	return UiKit.text_field(placeholder, max_length, _ROW_WIDTH)


## What the name currently is, and whether it may be written: a refusal disables
## Save, a name already in use warns that saving replaces that board, and a good
## new name says the file it will become.
func _read_name() -> void:
	var typed := _name_field.text
	var error := UserMaps.name_error(typed)
	_save_button.disabled = error != ""
	if error != "":
		_say(error, UiTheme.DANGER)
		return
	if UserMaps.exists(typed):
		_say(
			"This replaces the map you already have called '%s'." % UserMaps.slug(typed),
			UiTheme.AMMO
		)
		return
	_say("Saved as %s." % UserMaps.path_for(typed), UiTheme.NEUTRAL_LIGHT)


func _say(message: String, ink: Color) -> void:
	_notice.text = message
	_notice.add_theme_color_override("font_color", ink)


func _confirm() -> void:
	if _save_button.disabled:
		return
	saved.emit(_name_field.text, _description_field.text)
