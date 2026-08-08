class_name MissionObjectivesPanel
extends PanelContainer
## The mission's terms, kept on the board while it is being fought: what wins,
## what loses with the deadline counting down, and how the bonus stars stand
## (campaign-depth D8).
##
## Down entirely outside a campaign mission, which is the whole of its gate —
## `CampaignSession` is the one thing it reads, and a skirmish is pixel-identical
## to before this file existed. That is also what keeps `make smoke` and `make
## screenshot` byte-stable: no capture stages a mission except the one scenario
## that exists to photograph this panel.
##
## **It decides nothing.** Whether a condition holds is the objective's answer
## (`is_met`) and how far along it is is the objective's answer too (`readout`) —
## this asks, marks and prints. A panel that counted cities its own way would be
## a second opinion about a mission the runtime has already ruled on.
##
## Floats over the board rather than docking, like the teaching strip and unlike
## the two bars: the bars' heights are what the board's viewport is computed
## against and must not move, while this card comes and goes with the campaign.
## It sits in the top-left corner under the top bar, out of the middle of the
## board it describes, and swallows the pointer so a click on it cannot fall
## through to a cell rendered behind it.

## How far the card sits from the top bar and the left edge, and how far its rows
## sit inside it.
const _MARGIN := 4
const _PAD := 5
## The gap between a row's mark, its words and its readout.
const _ROW_GAP := 4
## The card's width, fixed so its words wrap rather than its edge moving. A
## mission states its conditions in a sentence each, and a card that sized itself
## to the longest one would cover a quarter of the board on one mission and half
## of it on the next — chrome that jumps between boards is chrome the player
## stops reading past.
const _WIDTH := 168
## What a satisfied condition wears, and what one still open does. A failure
## reads the same way round: its mark lights when it has fired, which is the last
## thing the panel ever draws before the mission ends.
const _MET := "✓"
const _OPEN := "·"

var _built := false
var _title_label: Label
var _rows: VBoxContainer
## The words of each condition currently on the card, so `layout_error` measures
## what was actually laid out rather than what was asked for.
var _row_labels: Array[Label] = []


func _ready() -> void:
	_build()


## Redraws the card from the session and the board a command has just been
## applied to. Called from `BattleView.refresh_hud`, which already runs after
## every command and every turn change; safe at any time, since it is a pure read
## of the mission and the state.
func refresh(game: GameState) -> void:
	if not _built:
		return
	visible = CampaignSession.active()
	if not visible:
		return
	var mission := CampaignSession.mission
	_title_label.text = mission.title
	for child in _rows.get_children():
		child.queue_free()
		_rows.remove_child(child)
	_row_labels.clear()
	_group("WIN", mission.objectives, game)
	_group("LOSE", mission.failures, game)
	_group("BONUS", mission.bonus_objectives, game)
	_place()


## Why the open card is not laid out, or "". The sweep's own bar is a file size,
## so a card whose rows collapsed to nothing photographs perfectly well — the same
## reason `CommanderInfoSheet.layout_error` and `SeatStrip.layout_error` exist.
func layout_error() -> String:
	if not visible:
		return "the objective panel is down inside a campaign mission"
	if _row_labels.is_empty():
		return "the objective panel laid out no conditions"
	for label in _row_labels:
		if label.size.x <= 0.0 or label.size.y <= 0.0:
			return "the objective panel's '%s' row measures %s" % [label.text, label.size]
	return ""


# --- the card itself ----------------------------------------------------------


func _build() -> void:
	custom_minimum_size = Vector2(_WIDTH, 0)
	add_theme_stylebox_override("panel", _card_box())
	# The card sits on the board, so it stops the pointer for the reason the docked
	# bars do: the board renders behind it, and an event falling through would walk
	# the game cursor onto a cell hidden under opaque paint.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _ROW_GAP)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	head.add_child(UiTheme.hud_label("MISSION", UiTheme.SIZE_MICRO, UiTheme.INK_3))
	_title_label = UiTheme.hud_label("", UiTheme.SIZE_MICRO, UiTheme.PAPER_2)
	head.add_child(_title_label)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_rows)

	hide()
	_built = true


## One heading and the conditions under it, or nothing at all when a mission
## names none — a card with an empty BONUS heading advertises a star that does
## not exist.
func _group(heading: String, objectives: Array[MissionObjective], game: GameState) -> void:
	if objectives.is_empty():
		return
	_rows.add_child(UiTheme.hud_label(heading, UiTheme.SIZE_MICRO, UiTheme.INK_3))
	for objective: MissionObjective in objectives:
		if objective != null:
			_rows.add_child(_condition_row(objective, game))


## A mark, the authored words, and whatever the objective says about its own
## progress. Amber for the readout, which is this design system's "your attention
## here" — the same token the charge meter fills with.
func _condition_row(objective: MissionObjective, game: GameState) -> Control:
	var team := CampaignSession.mission.player_team
	var tally := CampaignSession.tally
	var met := objective.is_met(game, team, tally)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _ROW_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mark := _MET if met else _OPEN
	row.add_child(_first_line(mark, UiTheme.CAPTURE if met else UiTheme.INK_3))
	var words := UiTheme.hud_label(objective.text, UiTheme.SIZE_MICRO, UiTheme.WHITE)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_labels.append(words)
	row.add_child(words)

	var readout := objective.readout(game, team, tally)
	if readout != "":
		row.add_child(_first_line(readout, UiTheme.AMMO))
	return row


## A label that stays level with the first line of the wrapping words beside it,
## rather than centring itself against however many lines they took.
func _first_line(text: String, color: Color) -> Label:
	var label := UiTheme.hud_label(text, UiTheme.SIZE_MICRO, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return label


## Parks the card under the top bar in the left corner. Measured a frame late for
## the reason MissionStrip measures itself: a PanelContainer's size is only valid
## once its labels have been laid out, and these change with every command.
func _place() -> void:
	await get_tree().process_frame
	if not visible:
		return
	reset_size()
	position = Vector2(_MARGIN, UiTheme.HUD_TOP_H + _MARGIN)


## The docked bars' slate with the ink outline and hard shadow every floating
## surface in this design system carries — a card on the board, and it reads as
## one.
func _card_box() -> StyleBoxFlat:
	var box := UiTheme.dark_panel_box()
	box.content_margin_left = _PAD
	box.content_margin_right = _PAD
	box.content_margin_top = _PAD - 1
	box.content_margin_bottom = _PAD - 1
	return box
