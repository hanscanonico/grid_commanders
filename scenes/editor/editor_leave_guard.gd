class_name EditorLeaveGuard
extends Control
## The question asked when a draft with unsaved work is about to be left behind.
##
## A board is an hour of somebody's evening and the editor's only exit was one
## press of Esc, so leaving is the one action here that asks first. It decides
## nothing: the editor knows whether anything is unsaved and what each answer
## does, and this page only offers the three of them.

## Leave anyway, losing whatever is unsaved.
signal discarded
## Take the save dialog on the way out.
signal save_asked
signal cancelled

var _keep_button: Button


func _ready() -> void:
	_build()
	hide()


func begin() -> void:
	show()
	_keep_button.grab_focus()


func close() -> void:
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if TransitionInput.dismissed_by_cancel(self, event):
		_answer(cancelled)


func _build() -> void:
	UiKit.page_veil(self)
	var main := UiKit.page_body(self, 6)
	main.add_child(UiKit.page_title("UNSAVED CHANGES"))
	main.add_child(UiKit.page_note("This board has work in it that is not on disk yet."))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UiTheme.GAP)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_keep_button = _action("Keep editing", UiTheme.ButtonVariant.PRIMARY, cancelled)
	actions.add_child(UiKit.touchable(_keep_button))
	actions.add_child(UiKit.touchable(_action("Save", UiTheme.ButtonVariant.SECONDARY, save_asked)))
	actions.add_child(UiKit.touchable(_action("Leave", UiTheme.ButtonVariant.GHOST, discarded)))
	main.add_child(actions)
	main.add_child(UiKit.key_legend("ESC  KEEP EDITING"))


func _action(text: String, variant: UiTheme.ButtonVariant, answer: Signal) -> Button:
	var accent: CommanderVisuals.FactionTheme = null
	if variant == UiTheme.ButtonVariant.PRIMARY:
		accent = UiTheme.menu_identity().theme(1)
	var button := UiKit.action_button(text, "", variant, accent, 96)
	button.pressed.connect(func() -> void: _answer(answer))
	return button


func _answer(answer: Signal) -> void:
	hide()
	answer.emit()
