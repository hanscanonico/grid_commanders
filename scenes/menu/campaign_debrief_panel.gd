class_name CampaignDebriefPanel
extends Control
## What is said after a mission — the scene between battles.
##
## The briefing's mirror, and it exists because a campaign that only speaks
## *before* a fight has no way to land what the fight cost or changed: the
## victory dialogue and the defeat line were authored per mission and had
## nowhere to be read. It plays on the way back from the battle, before the hub,
## so the story sits between the missions rather than only in front of them.
##
## Presentation only. It decides no outcome — `MissionRuntime` did that and
## `CampaignSession` recorded it — and it shows what happened rather than
## working it out. That holds for the ledger too: which facts the mission wrote
## and what they are called are handed over already settled.

signal continued

const _TITLE_SIZE := 15

var _verdict: Label
var _title: Label
var _stars: Label
var _body: VBoxContainer
var _unlocked: Label
var _continue_button: Button
var _commanders := CommanderDB.load_default()


func _ready() -> void:
	_build()
	hide()


## Opens on a finished mission. `next_title` is the mission this one unlocked,
## or "" at the end of a campaign or after a loss — the one forward-looking
## thing a debrief can say, and the reason to press on.
##
## `ledger` is the war as it now reads, for the victory lines that are only said
## on one kind of run, and `recorded` is what this mission wrote to it in its own
## beats' words — the debrief being the one screen that can say what changed.
## Both are handed over rather than read off `CampaignSession`, which the caller
## is about to clear.
func begin(
	mission: MissionDefinition,
	outcome: MissionRuntime.Outcome,
	max_stars: int,
	next_title: String,
	ledger: CampaignState = null,
	recorded: Array[String] = []
) -> void:
	var won := outcome.status == MissionRuntime.Status.SUCCESS
	_verdict.text = "MISSION COMPLETE" if won else "MISSION FAILED"
	_verdict.add_theme_color_override("font_color", UiTheme.CAPTURE if won else UiTheme.DANGER)
	_title.text = mission.title.to_upper()
	if won:
		_stars.text = "★".repeat(outcome.stars) + "☆".repeat(maxi(0, max_stars - outcome.stars))
	else:
		_stars.text = outcome.reason
	for child in _body.get_children():
		child.queue_free()
	# A loss has one narrator's sentence rather than dialogue: the generals who
	# would have spoken are the ones it went badly for.
	if won:
		for line: MissionLine in MissionLine.spoken(mission.victory, ledger):
			_body.add_child(MissionSpeech.render(line, _commanders))
	elif mission.defeat != "":
		_body.add_child(MissionSpeech.paragraph(mission.defeat))
	for note: String in recorded:
		_body.add_child(MissionSpeech.paragraph("RECORDED   %s" % note, true))
	_unlocked.text = "NEXT   %s" % next_title.to_upper() if next_title != "" else ""
	_unlocked.visible = next_title != ""
	_continue_button.text = "Continue" if won else "Back to the hub"
	show()
	_continue_button.grab_focus()


func chrome() -> Dictionary[String, Control]:
	return {"the debrief verdict": _verdict, "Continue": _continue_button}


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

	_verdict = Label.new()
	_verdict.add_theme_font_override("font", UiTheme.display(true))
	_verdict.add_theme_font_size_override("font_size", _TITLE_SIZE)
	_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_verdict)

	_title = _micro("")
	main.add_child(_title)

	_stars = Label.new()
	_stars.add_theme_font_override("font", UiTheme.display())
	_stars.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_stars)

	var frame := ScrollContainer.new()
	frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(frame)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(_body)

	_unlocked = _micro("")
	main.add_child(_unlocked)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	UiTheme.apply_button(_continue_button, UiTheme.ButtonVariant.PRIMARY, null, UiTheme.SIZE_BUTTON)
	_continue_button.custom_minimum_size = Vector2(140, 20)
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_button.pressed.connect(_leave)
	main.add_child(_continue_button)


func _micro(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.stat())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	label.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _leave() -> void:
	hide()
	continued.emit()
