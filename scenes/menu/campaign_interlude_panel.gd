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
const _LINE_STAGGER := 0.35
const _LINE_FADE := 0.3

var _title: Label
var _heading: Label
var _body: VBoxContainer
var _continue_button: Button
var _commanders := CommanderDB.load_default()
var _line_tween: Tween


func _ready() -> void:
	_build()
	hide()


## Opens on one page, read against the war as the profile now records it. A null
## ledger is a campaign with no profile on disk, where every fact reads zero and
## the unconditional lines are what is said.
##
## The lines land one at a time — the page is the act's payoff, and a wall of
## text that appears whole is a page that gets skimmed. A press completes the
## reveal; the next one turns the page. Captures pose the finished frame.
func begin(
	interlude: CampaignInterlude, ledger: CampaignState = null, animate: bool = true
) -> void:
	if _line_tween != null and _line_tween.is_valid():
		_line_tween.kill()
	_line_tween = null
	_title.text = interlude.title.to_upper()
	_title.visible = interlude.title != ""
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var spoken: Array[Control] = []
	for line: MissionLine in MissionLine.spoken(interlude.lines, ledger):
		var block := MissionSpeech.render(line, _commanders)
		_body.add_child(block)
		spoken.append(block)
	show()
	_continue_button.grab_focus()
	if not animate or spoken.is_empty():
		return
	for block: Control in spoken:
		block.modulate.a = 0.0
	_line_tween = create_tween()
	for block: Control in spoken:
		_line_tween.tween_property(block, "modulate:a", 1.0, _LINE_FADE)
		_line_tween.tween_interval(_LINE_STAGGER)


## Every line on the page at once — where a press mid-reveal lands.
func _finish_reveal() -> void:
	if _line_tween != null and _line_tween.is_valid():
		_line_tween.kill()
	_line_tween = null
	for block: Control in _body.get_children():
		block.modulate.a = 1.0


func chrome() -> Dictionary[String, Control]:
	return {"the interlude heading": _heading, "Continue": _continue_button}


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if TransitionInput.is_press(event):
		get_viewport().set_input_as_handled()
		if _line_tween != null and _line_tween.is_valid():
			_finish_reveal()
		else:
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
	_finish_reveal()
	hide()
	continued.emit()
