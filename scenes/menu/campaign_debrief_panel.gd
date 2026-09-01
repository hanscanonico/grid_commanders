class_name CampaignDebriefPanel
extends Control
## What is said after a mission — the scene between battles.
##
## The briefing's mirror, and it exists because a campaign that only speaks
## *before* a fight has no way to land what the fight cost or changed: the
## victory and defeat dialogue were authored per mission and had nowhere to be
## read. It plays on the way back from the battle, before the hub,
## so the story sits between the missions rather than only in front of them.
##
## Presentation only. It decides no outcome — `MissionRuntime` did that and
## `CampaignSession` recorded it — and it shows what happened rather than
## working it out. That holds for the ledger too: which facts the mission wrote
## and what they are called are handed over already settled.

signal continued

## Between body and banner: the stars are the payoff, so they read bigger than
## the verdict's supporting copy.
const _STAR_SIZE := 12
const _STAR_STAGGER := 0.18
const _STAR_FADE := 0.25

var _verdict: Label
var _title: Label
var _stars: VBoxContainer
var _scoreboard: Label
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
## `ledger` is the war as it now reads, for the debrief lines that are only said
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
	losses: int = 0,
	animate: bool = true
) -> void:
	var won := outcome.status == MissionRuntime.Status.SUCCESS
	_verdict.text = "MISSION COMPLETE" if won else "MISSION FAILED"
	_verdict.add_theme_color_override("font_color", UiTheme.CAPTURE if won else UiTheme.DANGER)
	_title.text = mission.title.to_upper()
	_fill_stars(
		outcome.awards if won else ([] as Array[MissionRuntime.Award]), max_stars, won and animate
	)
	_stars.visible = won
	_scoreboard.text = _scoreboard_text(mission, outcome, ledger, losses)
	_scoreboard.visible = won
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	# On a loss the condition that ended it leads, in its own words, where a long
	# reason can wrap instead of running off the canvas; the dialogue follows.
	if not won and outcome.reason != "":
		_body.add_child(MissionSpeech.paragraph(outcome.reason, true))
	for line: MissionLine in MissionLine.spoken(mission.victory if won else mission.defeat, ledger):
		_body.add_child(MissionSpeech.render(line, _commanders))
	for note: String in recorded:
		_body.add_child(MissionSpeech.paragraph("RECORDED   %s" % note, true))
	_unlocked.text = "NEXT   %s" % next_title.to_upper() if next_title != "" else ""
	_unlocked.visible = next_title != ""
	_continue_button.text = "Continue" if won else "Back to the hub"
	show()
	_continue_button.grab_focus()


## One row per star, each naming what it was for, the earned ones revealed one at
## a time — the payoff beat. A posed capture takes the finished frame instead: a
## mid-fade star is a frame the sweep cannot reproduce.
##
## The awards are handed over already judged; padding with anonymous rows is a
## guard against a caller that knows fewer stars than the mission offers.
func _fill_stars(awards: Array[MissionRuntime.Award], max_stars: int, animate: bool) -> void:
	if _star_tween != null and _star_tween.is_valid():
		_star_tween.kill()
	_star_tween = null
	for child in _stars.get_children():
		_stars.remove_child(child)
		child.queue_free()
	var earned: Array[Control] = []
	for award: MissionRuntime.Award in awards:
		var row := _star_row(award.text, award.earned)
		_stars.add_child(row)
		if award.earned:
			earned.append(row)
	for _slot in maxi(0, max_stars - awards.size()):
		_stars.add_child(_star_row("", false))
	if not animate:
		return
	for row: Control in earned:
		row.modulate.a = 0.0
	_star_tween = create_tween()
	for row: Control in earned:
		_star_tween.tween_interval(_STAR_STAGGER)
		_star_tween.tween_property(row, "modulate:a", 1.0, _STAR_FADE)


func _star_row(text: String, lit: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var glyph := Label.new()
	glyph.text = "★" if lit else "☆"
	glyph.add_theme_font_override("font", UiTheme.display())
	glyph.add_theme_font_size_override("font_size", _STAR_SIZE)
	glyph.add_theme_color_override("font_color", UiTheme.SELECT_GOLD if lit else UiTheme.INK_3)
	row.add_child(glyph)
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.stat())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	label.add_theme_color_override("font_color", UiTheme.SELECT_GOLD if lit else UiTheme.INK_3)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


## The one line of numbers: how long it took against par, what it cost, and what
## it hands the next mission. Read off the ledger the caller handed over, which
## `CampaignSession.record` has already written the banked roster onto.
func _scoreboard_text(
	mission: MissionDefinition, outcome: MissionRuntime.Outcome, ledger: CampaignState, losses: int
) -> String:
	var parts: Array[String] = []
	if mission.par_day > 0:
		parts.append("DAY %d / PAR %d" % [outcome.day, mission.par_day])
	else:
		parts.append("DAY %d" % outcome.day)
	parts.append("LOST %d" % losses)
	var veterans := ledger.roster.size() if ledger != null else 0
	if veterans > 0:
		parts.append("VETERANS %d" % veterans)
	return "   ·   ".join(parts)


func chrome() -> Dictionary[String, Control]:
	return {"the debrief verdict": _verdict, "Continue": _continue_button}


func _unhandled_input(event: InputEvent) -> void:
	if TransitionInput.dismissed_by_press(self, event):
		_leave()


func _build() -> void:
	UiKit.page_veil(self)
	var main := UiKit.page_body(self, 5, UiTheme.PAGE_BUTTON_MARGIN)

	_verdict = UiKit.page_title()
	main.add_child(_verdict)

	_title = _micro("")
	main.add_child(_title)

	_stars = VBoxContainer.new()
	_stars.add_theme_constant_override("separation", 2)
	_stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.add_child(_stars)

	_scoreboard = _micro("")
	main.add_child(_scoreboard)

	var frame := UiKit.vscroll()
	main.add_child(frame)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(_body)

	_unlocked = _micro("")
	main.add_child(_unlocked)

	_continue_button = UiKit.action_button("Continue", "", UiTheme.ButtonVariant.PRIMARY, null, 140)
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_button.pressed.connect(_leave)
	main.add_child(_continue_button)


## The debrief's quiet lines, centred over the page. The ink is the panel's own:
## these sit on the dark veil rather than on a row's plate.
func _micro(text: String) -> Label:
	var label := ListRow.detail(text, UiTheme.NEUTRAL_LIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _leave() -> void:
	hide()
	continued.emit()
