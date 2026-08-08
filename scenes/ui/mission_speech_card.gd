class_name MissionSpeechCard
extends PanelContainer
## What a scripted mission beat says, on the board it lands on (campaign-depth
## D8).
##
## The words are drawn by `MissionSpeech`, the one drawer the briefing and the
## debrief already share, so a general sounds the same mid-battle as they do
## between missions.
##
## Presentation only, and only the words, exactly as TurnBanner is: how long a
## beat holds, what a press does to it and where it sits are BattleAnimator's. It
## reads no session either — the lines are handed over by the command that fired
## them, the way the power card is handed the commander who fired one.

const _PAD := 10
## Between two speakers' blocks. Wider than the gap inside one, where a name sits
## directly on top of its own words.
const _LINE_GAP := 6

var _rows: VBoxContainer


func _ready() -> void:
	_build()


## The words of one beat, a block per line.
func announce(lines: Array[MissionLine], commanders: CommanderDB) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for line: MissionLine in lines:
		if line != null:
			_rows.add_child(MissionSpeech.render(line, commanders))


## Why the open card is not laid out, or "". The sweep's own bar is a file size,
## so a card whose lines collapsed to nothing photographs perfectly well — the
## same reason `MissionObjectivesPanel.layout_error` exists.
func layout_error() -> String:
	if not visible:
		return "the mission speech card is down with a beat on the board"
	if _rows.get_child_count() == 0:
		return "the mission speech card laid out no lines"
	for row: Control in _rows.get_children():
		if row.size.x <= 0.0 or row.size.y <= 0.0:
			return "a mission speech line measures %s" % row.size
	return ""


func _build() -> void:
	add_theme_stylebox_override("panel", UiTheme.dark_panel_box())
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, _PAD)
	add_child(margin)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", _LINE_GAP)
	margin.add_child(_rows)
