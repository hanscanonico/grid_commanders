class_name CampaignInterludePanel
extends Control
## The page between two blocks of a campaign — what the act that just closed cost
## and what the war did about it.
##
## `CampaignDebriefPanel`'s sibling and built the same way, because it is the
## same kind of beat one step further out: the debrief speaks about the mission,
## this speaks about the block. It shows on the way back from the mission that
## closed a block, between the debrief and the hub.
##
## Presentation only, and it decides nothing at all — not even which lines are
## said. `MissionLine.spoken` filters those against the ledger it is handed, the
## same filter the briefing and the debrief use, so a block that went badly reads
## differently without a second kind of variant existing.

signal continued

const _TITLE_SIZE := 15

var _title: Label
var _heading: Label
var _body: VBoxContainer
var _continue_button: Button
var _commanders := CommanderDB.load_default()


func _ready() -> void:
	_build()
	hide()


## Opens on one page, read against the war as the profile now records it. A null
## ledger is a campaign with no profile on disk, where every fact reads zero and
## the unconditional lines are what is said.
func begin(interlude: CampaignInterlude, ledger: CampaignState = null) -> void:
	_title.text = interlude.title.to_upper()
	_title.visible = interlude.title != ""
	for child in _body.get_children():
		child.queue_free()
	for line: MissionLine in MissionLine.spoken(interlude.lines, ledger):
		_body.add_child(MissionSpeech.render(line, _commanders))
	show()
	_continue_button.grab_focus()


func chrome() -> Dictionary[String, Control]:
	return {"the interlude heading": _heading, "Continue": _continue_button}


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if TransitionInput.is_press(event):
		get_viewport().set_input_as_handled()
		_leave()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.veil(0.985)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	add_child(margin)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 5)
	margin.add_child(main)

	_heading = Label.new()
	_heading.text = "INTERLUDE"
	_heading.add_theme_font_override("font", UiTheme.stat())
	_heading.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	_heading.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_heading)

	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.display(true))
	_title.add_theme_font_size_override("font_size", _TITLE_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_title)

	var frame := ScrollContainer.new()
	frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(frame)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(_body)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	UiTheme.apply_button(_continue_button, UiTheme.ButtonVariant.PRIMARY, null, UiTheme.SIZE_BUTTON)
	_continue_button.custom_minimum_size = Vector2(140, 20)
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_button.pressed.connect(_leave)
	main.add_child(_continue_button)


func _leave() -> void:
	hide()
	continued.emit()
