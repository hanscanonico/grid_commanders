class_name EditorLeaveGuard
extends Control
## The question asked when a draft with unsaved work is about to be parted with.
##
## A board is an hour of somebody's evening, so every press that would throw one
## away asks first — leaving for the menu, and opening another board over it. It
## decides nothing: the editor knows whether anything is unsaved and what each
## answer does, and this page only offers the three of them. Which press raised
## it is a word on one button rather than a second signal, because the answers
## are the same three either way and the editor is the one that knows them.

## Part with the draft, losing whatever is unsaved.
signal discarded
## Take the save dialog on the way to it.
signal save_asked
signal cancelled

## What the page says while nothing has been refused.
const _NOTE := "This board has work in it that is not on disk yet."

var _keep_button: Button
var _discard_button: Button
var _note: Label


func _ready() -> void:
	_build()
	hide()


## Asks the question, `discard_word` naming what the press it stands in front of
## would do.
func begin(discard_word: String) -> void:
	_discard_button.text = discard_word
	_say(_NOTE, UiTheme.NEUTRAL_LIGHT)
	show()
	_keep_button.grab_focus()


## Says why the save this page was answered with did not happen, and stands the
## question back up on the same three answers: it hid to hand the ask over, so a
## refusal with nowhere to land reads as a press that did nothing at all.
func refuse(message: String) -> void:
	_say(message, UiTheme.DANGER)
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
	_note = UiKit.page_note(_NOTE)
	main.add_child(_note)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UiTheme.GAP)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_keep_button = _action("Keep editing", UiTheme.ButtonVariant.PRIMARY, cancelled)
	actions.add_child(UiKit.touchable(_keep_button))
	actions.add_child(UiKit.touchable(_action("Save", UiTheme.ButtonVariant.SECONDARY, save_asked)))
	_discard_button = _action("Leave", UiTheme.ButtonVariant.GHOST, discarded)
	actions.add_child(UiKit.touchable(_discard_button))
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


func _say(message: String, ink: Color) -> void:
	_note.text = message
	_note.add_theme_color_override("font_color", ink)
