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
## Between body and banner: the stars are the payoff, so they read bigger than
## the verdict's supporting copy.
const _STAR_SIZE := 12
const _STAR_STAGGER := 0.18
const _STAR_FADE := 0.25

var _verdict: Label
var _title: Label
var _stars: HBoxContainer
var _body: VBoxContainer
var _unlocked: Label
var _continue_button: Button
var _commanders := CommanderDB.load_default()
var _star_tween: Tween


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
	recorded: Array[String] = [],
	animate: bool = true
) -> void:
	var won := outcome.status == MissionRuntime.Status.SUCCESS
	_verdict.text = "MISSION COMPLETE" if won else "MISSION FAILED"
	_verdict.add_theme_color_override("font_color", UiTheme.CAPTURE if won else UiTheme.DANGER)
	_title.text = mission.title.to_upper()
	_fill_stars(outcome.stars if won else 0, max_stars, won and animate)
	_stars.visible = won
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	# A loss has one narrator's sentence rather than dialogue: the generals who
	# would have spoken are the ones it went badly for. The condition that ended
	# it leads, in its own words, where a long reason can wrap instead of running
	# off the canvas.
	if won:
		for line: MissionLine in MissionLine.spoken(mission.victory, ledger):
			_body.add_child(MissionSpeech.render(line, _commanders))
	else:
		if outcome.reason != "":
			_body.add_child(MissionSpeech.paragraph(outcome.reason, true))
		if mission.defeat != "":
			_body.add_child(MissionSpeech.paragraph(mission.defeat))
	for note: String in recorded:
		_body.add_child(MissionSpeech.paragraph("RECORDED   %s" % note, true))
	_unlocked.text = "NEXT   %s" % next_title.to_upper() if next_title != "" else ""
	_unlocked.visible = next_title != ""
	_continue_button.text = "Continue" if won else "Back to the hub"
	show()
	_continue_button.grab_focus()


## One label per star, the earned ones revealed one at a time — the payoff beat.
## A posed capture takes the finished frame instead: a mid-fade star is a frame
## the sweep cannot reproduce.
func _fill_stars(earned: int, max_stars: int, animate: bool) -> void:
	if _star_tween != null and _star_tween.is_valid():
		_star_tween.kill()
	_star_tween = null
	for child in _stars.get_children():
		_stars.remove_child(child)
		child.queue_free()
	for slot in maxi(max_stars, earned):
		var star := Label.new()
		var lit := slot < earned
		star.text = "★" if lit else "☆"
		star.add_theme_font_override("font", UiTheme.display())
		star.add_theme_font_size_override("font_size", _STAR_SIZE)
		star.add_theme_color_override("font_color", UiTheme.SELECT_GOLD if lit else UiTheme.INK_3)
		_stars.add_child(star)
		if lit and animate:
			star.modulate.a = 0.0
	if not animate:
		return
	_star_tween = create_tween()
	for slot in earned:
		var star: Label = _stars.get_child(slot)
		_star_tween.tween_interval(_STAR_STAGGER)
		_star_tween.tween_property(star, "modulate:a", 1.0, _STAR_FADE)


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

	_stars = HBoxContainer.new()
	_stars.add_theme_constant_override("separation", 3)
	_stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
