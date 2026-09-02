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
## A lost mission, asked for again from this page rather than through the hub.
signal retried

## Between body and banner: the stars are the payoff, so they read bigger than
## the verdict's supporting copy.
const _STAR_SIZE := 12
const _STAR_STAGGER := 0.18
const _STAR_FADE := 0.25
const _DOT := "   ·   "


## Everything the page says, handed over settled. `next_title` is the mission
## this one unlocked, or "" at the end of a campaign or after a loss — the one
## forward-looking thing a debrief can say, and the reason to press on.
##
## `ledger` is the war as it now reads, for the debrief lines that are only said
## on one kind of run and for the war's standing; `recorded` is what this mission
## wrote to it in its own beats' words; `previous` is the mission's record before
## this run, null on a first clear, for what the clear was worth. All are handed
## over rather than read off `CampaignSession`, which the caller is about to
## clear.
class Report:
	extends RefCounted

	var mission: MissionDefinition
	var outcome: MissionRuntime.Outcome
	var next_title: String = ""
	var ledger: CampaignState
	var recorded: Array[String] = []
	var losses: int = 0
	var previous: CampaignState.MissionRecord
	var campaign: CampaignDefinition

	func _init(p_mission: MissionDefinition, p_outcome: MissionRuntime.Outcome) -> void:
		mission = p_mission
		outcome = p_outcome

	func won() -> bool:
		return outcome.status == MissionRuntime.Status.SUCCESS


var _verdict: Label
var _title: Label
var _stars: VBoxContainer
var _scoreboard: Label
var _body: VBoxContainer
var _unlocked: Label
var _retry_button: Button
var _continue_button: Button
var _commanders := CommanderDB.load_default()
var _star_tween: Tween


func _ready() -> void:
	_build()
	hide()


## Opens on a finished mission.
func begin(report: Report, animate: bool = true) -> void:
	var won := report.won()
	var mission := report.mission
	var outcome := report.outcome
	_verdict.text = "MISSION COMPLETE" if won else "MISSION FAILED"
	_verdict.add_theme_color_override("font_color", UiTheme.CAPTURE if won else UiTheme.DANGER)
	_title.text = mission.title.to_upper()
	_fill_stars(outcome.awards if won else ([] as Array[MissionRuntime.Award]), won and animate)
	_stars.visible = won
	_scoreboard.text = _scoreboard_text(report)
	_scoreboard.visible = won
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	# On a loss the condition that ended it leads, in its own words, where a long
	# reason can wrap instead of running off the canvas; the dialogue follows.
	if not won and outcome.reason != "":
		_body.add_child(MissionSpeech.paragraph(outcome.reason, true))
	var lines := MissionLine.spoken(mission.victory if won else mission.defeat, report.ledger)
	for line: MissionLine in lines:
		_body.add_child(MissionSpeech.render(line, _commanders))
	for note: String in report.recorded:
		_body.add_child(MissionSpeech.paragraph("RECORDED   %s" % note, true))
	var next := report.next_title
	_unlocked.text = "NEXT   %s" % next.to_upper() if next != "" else ""
	_unlocked.visible = next != ""
	# A loss leads with the retry: the hub is one step back, another go is the
	# thing a player who just lost wants, and it is offered here rather than
	# three pages away.
	_retry_button.visible = not won
	_continue_button.text = "Continue" if won else "Back to the hub"
	UiTheme.apply_button(
		_continue_button,
		UiTheme.ButtonVariant.PRIMARY if won else UiTheme.ButtonVariant.GHOST,
		null,
		UiTheme.SIZE_BUTTON
	)
	show()
	if won:
		_continue_button.grab_focus()
	else:
		_retry_button.grab_focus()


## One row per star, each naming what it was for, the earned ones revealed one at
## a time — the payoff beat. A posed capture takes the finished frame instead: a
## mid-fade star is a frame the sweep cannot reproduce.
##
## The awards are handed over already judged, missed stars named among them.
func _fill_stars(awards: Array[MissionRuntime.Award], animate: bool) -> void:
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


## The numbers, three lines: how long it took against par, what it cost and what
## it hands the next mission; what the clear was worth against the record it
## beat; and where the war now stands. Read off the ledger the caller handed
## over, which `CampaignSession.record` has already written the banked roster onto.
func _scoreboard_text(report: Report) -> String:
	var parts: Array[String] = []
	if report.mission.par_day > 0:
		parts.append("DAY %d / PAR %d" % [report.outcome.day, report.mission.par_day])
	else:
		parts.append("DAY %d" % report.outcome.day)
	parts.append("LOST %d" % report.losses)
	var veterans := report.ledger.roster.size() if report.ledger != null else 0
	if veterans > 0:
		parts.append("VETERANS %d" % veterans)
	var lines: Array[String] = [_DOT.join(parts), worth_line(report.outcome, report.previous)]
	if report.campaign != null and report.ledger != null:
		lines.append(standing_line(report.campaign, report.ledger))
	return "\n".join(lines)


## What this run did to the mission's record: a first clear, a better day, more
## stars — both when both improved — or nothing. Static and pure so the wording
## is pinned without the page; `previous` is the record *before* the run, which
## is why the caller copies it before `CampaignState.complete` improves it.
static func worth_line(
	outcome: MissionRuntime.Outcome, previous: CampaignState.MissionRecord
) -> String:
	if previous == null:
		return "FIRST CLEAR"
	var gains: Array[String] = []
	if previous.best_day > 0 and outcome.day < previous.best_day:
		gains.append("BEST DAY %d → %d" % [previous.best_day, outcome.day])
	if outcome.stars > previous.stars:
		gains.append("★ %d → %d" % [previous.stars, outcome.stars])
	return _DOT.join(gains) if not gains.is_empty() else "NO CHANGE"


## The war as it now stands, from the same three reads the hub's headline makes:
## cleared out of what the route still offers, never the authored count.
static func standing_line(campaign: CampaignDefinition, ledger: CampaignState) -> String:
	return (
		"%s   %d / %d · %d ★"
		% [
			campaign.title.to_upper(),
			ledger.records.size(),
			ledger.offered_count(campaign),
			ledger.total_stars(),
		]
	)


func chrome() -> Dictionary[String, Control]:
	var named: Dictionary[String, Control] = {
		"the debrief verdict": _verdict, "Continue": _continue_button
	}
	if _retry_button.visible:
		named["Retry"] = _retry_button
	return named


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

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UiTheme.PAGE_BUTTON_MARGIN)
	actions.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.add_child(actions)

	_retry_button = UiKit.action_button("Retry", "", UiTheme.ButtonVariant.PRIMARY, null, 140)
	_retry_button.pressed.connect(_retry)
	actions.add_child(_retry_button)

	_continue_button = UiKit.action_button("Continue", "", UiTheme.ButtonVariant.PRIMARY, null, 140)
	_continue_button.pressed.connect(_leave)
	actions.add_child(_continue_button)


## The debrief's quiet lines, centred over the page. The ink is the panel's own:
## these sit on the dark veil rather than on a row's plate.
func _micro(text: String) -> Label:
	var label := ListRow.detail(text, UiTheme.NEUTRAL_LIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _leave() -> void:
	hide()
	continued.emit()


func _retry() -> void:
	hide()
	retried.emit()
