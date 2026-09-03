class_name EditorToolbar
extends HBoxContainer
## The editor's one row of actions: [Back] [Undo] [Redo] [Erase] … [Open] [Save].
##
## It holds no draft and decides nothing — every press is a signal the editor
## answers, and whether Undo is live is the history's answer, handed in. The row
## exists as its own control because the header is where an editor's actions are
## expected to be, and a header that also built them would be the page's fourth
## job after the board, the columns and the validator.
##
## Back is the one press that is not a signal: it dispatches the `cancel` action
## through `UiKit.action_chip`, so what leaving asks and what it then does stay
## the key path's alone. It stands on both builds: a finger had no way out of the
## editor at all, and a pointer had only Esc.

signal undo_asked
signal redo_asked
signal erase_asked
signal brushes_asked
signal open_asked
signal save_asked

## How wide every action button stands, so six short words read as one row of
## plates rather than six sizes. Height is `UiKit.touchable`'s business.
const _BUTTON_W := 44

var _undo: Button
var _redo: Button
var _erase: Button
var _headline: Label


## Builds the row. `with_brushes` opens the tool sheet and is a touch build's
## only way to the columns, so a desktop one is not offered it.
func configure(with_brushes: bool) -> void:
	add_theme_constant_override("separation", 6)
	var back := UiKit.action_chip("BACK", &"cancel")
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(back)
	var title := UiKit.page_title("MAP EDITOR")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(title)
	_undo = _button("Undo", func() -> void: undo_asked.emit())
	_redo = _button("Redo", func() -> void: redo_asked.emit())
	_erase = _button("Erase", func() -> void: erase_asked.emit())
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(gap)
	if with_brushes:
		_button("Brushes", func() -> void: brushes_asked.emit())
	_button("Open", func() -> void: open_asked.emit())
	_button("Save", func() -> void: save_asked.emit())
	_headline = UiKit.micro_label("")
	_headline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_headline)
	show_history(false, false)
	show_erase(false)


## Lights Undo and Redo only while there is something behind or ahead.
func show_history(undo_ready: bool, redo_ready: bool) -> void:
	_undo.disabled = not undo_ready
	_redo.disabled = not redo_ready


## Whether the Erase brush is the one in hand. The row is a row of plates, so
## the armed one takes the accent every chosen action in this game wears —
## nothing else on the page may read as chosen at the same time.
func show_erase(active: bool) -> void:
	var variant := UiTheme.ButtonVariant.PRIMARY if active else UiTheme.ButtonVariant.SECONDARY
	UiTheme.apply_button(_erase, variant, null, UiTheme.SIZE_BUTTON)


## What the draft is, in the corner of the row: its size and its seats.
func show_headline(text: String) -> void:
	_headline.text = text


func _button(text: String, on_press: Callable) -> Button:
	var button := UiKit.action_button(text, "", UiTheme.ButtonVariant.SECONDARY, null, _BUTTON_W)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(on_press)
	UiKit.touchable(button)
	add_child(button)
	return button
