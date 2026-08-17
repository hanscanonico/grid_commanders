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
## (`is_met`), how far along it is is the objective's answer too (`readout`), and
## whether it is being judged at all is `is_live` — the same authority
## `MissionRuntime` asks before it walks a list. This card prints exactly the
## conditions the verdict is being reached on, so a held-back objective stays off
## it until a beat reveals it and the two can never disagree about which ones
## count.
##
## Floats over the board rather than docking, like the teaching strip and unlike
## the two bars: the bars' heights are what the board's viewport is computed
## against and must not move, while this card comes and goes with the campaign.
## It sits in the top-left corner under the top bar, out of the middle of the
## board it describes, and swallows the pointer so a click on it cannot fall
## through to a cell rendered behind it.

## The two corners under the top bar the card may sit in. It opens in the left one
## and steps aside to the right one while the cursor is under it, because the fight
## being in the top-left is exactly when hiding the card is the wrong answer.
const _DOCK_LEFT := 0
const _DOCK_RIGHT := 1

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
## The card's three marks, and they mean one thing each: ✓ met, · open, ✗ lost.
## A failure reads the same way round as a condition: its mark lights when it has
## fired, which is the last thing the panel ever draws before the mission ends.
const _MET := "✓"
const _OPEN := "·"
const _LOST := "✗"

## Whether there is a mission to describe, and whether the player has its card up.
## The top bar's chip is the one listener: the card covers board a player may need
## to look at, so O lowers it, and a key with nothing on screen naming it is a key
## nobody finds.
signal card_changed(available: bool, up: bool)

var _built := false
var _where_label: Label
## Whether the player has the card up. Not a device preference and not remembered
## across missions: a mission's terms are the first thing a new board has to say, so
## every one of them opens with the card up and the player lowers it when it is in
## the way.
var _up := true
## Which corner the card is currently parked in. Presentation and nothing else:
## not a preference, not remembered across missions, and the player never sets it.
var _dock := _DOCK_LEFT
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
	var available := CampaignSession.active()
	visible = available and _up
	card_changed.emit(available, _up)
	if not visible:
		return
	var mission := CampaignSession.mission
	_title_label.text = mission.title
	_where_label.text = mission.location
	_where_label.visible = mission.location != ""
	for child in _rows.get_children():
		child.queue_free()
		_rows.remove_child(child)
	_row_labels.clear()
	_group("WIN", mission.objectives, game)
	_group("LOSE", mission.failures, game)
	_bonus_group(mission, game)
	_place()


## Whether the player has the card up, for the pause menu's row to say which way
## it will go. The up/down state stays this card's own: the row reads it here and
## flips it through `toggle`, the same call O makes, so the key and the row can
## never disagree.
func is_up() -> bool:
	return _up


## O and the pause menu's Objectives row raise and lower the card. It is redrawn
## on the way up rather than merely shown, because the board it describes has been
## played on while it was down — `refresh` does nothing beyond the chip while the
## card is lowered, which is what keeps a card nobody is looking at off every
## command's path.
func toggle(game: GameState) -> void:
	_up = not _up
	refresh(game)


## Steps the card out of the cursor's way, called from `BattleView.move_cursor_to`
## — the seam the board cursor already reports through, so nothing polls. The
## common case is a dock that did not change and costs one geometry read.
func follow_cursor(
	cell: Vector2i, cell_size: int, board_origin: Vector2, viewport: Vector2
) -> void:
	if not visible:
		return
	var dock := dock_for(cell, cell_size, board_origin, viewport, size, _dock)
	if dock == _dock:
		return
	_dock = dock
	_place()


## Which corner the card belongs in with the cursor on `cell`. Geometry only: it
## reads no mission and no session, so where the card sits can never depend on what
## it says. Static and argument-taking so the rule is checked without a scene, the
## shape `SeatStrip.normalised_sides` and `TransitionInput` are.
##
## The card dodges to the right corner while the cursor is under its left one, and
## comes home once the cursor is under neither — so a cursor still working the
## top-left keeps the card away, and one that follows it into the right corner
## sends it home rather than being covered there.
static func dock_for(
	cursor_cell: Vector2i,
	cell_size: int,
	board_origin: Vector2,
	viewport: Vector2,
	card_size: Vector2,
	current_dock: int
) -> int:
	var cursor := Rect2(
		board_origin + Vector2(cursor_cell) * float(cell_size), Vector2.ONE * float(cell_size)
	)
	var covers_left := cursor.intersects(
		Rect2(_dock_position(_DOCK_LEFT, viewport, card_size), card_size)
	)
	var covers_right := cursor.intersects(
		Rect2(_dock_position(_DOCK_RIGHT, viewport, card_size), card_size)
	)
	if current_dock == _DOCK_LEFT:
		return _DOCK_RIGHT if covers_left and not covers_right else _DOCK_LEFT
	return _DOCK_LEFT if not covers_left else _DOCK_RIGHT


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

	_where_label = UiTheme.hud_label("", UiTheme.SIZE_MICRO, UiTheme.INK_3)
	_where_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_where_label)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_rows)

	hide()
	_built = true


## One heading and the conditions under it, or nothing at all when a mission
## names none — a card with an empty BONUS heading advertises a star that does
## not exist. A heading whose every condition is still hidden is that same empty
## heading, so the filter comes first: on a LOSE group especially, naming the
## group alone would tell the player a trap is coming.
func _group(heading: String, objectives: Array[MissionObjective], game: GameState) -> void:
	var live := _live(objectives)
	if live.is_empty():
		return
	_rows.add_child(UiTheme.hud_label(heading, UiTheme.SIZE_MICRO, UiTheme.INK_3))
	for objective: MissionObjective in live:
		_rows.add_child(_condition_row(objective, game))


## The bonus stars, with the par day the runtime is also judging: the one
## condition on the card that is not a `MissionObjective`, printed here because
## the player is racing a clock nothing else on screen names. A clock still
## running is open rather than satisfied, so it wears `_OPEN` in the amber its
## readout beside it already uses, and `_LOST` once par has gone by.
func _bonus_group(mission: MissionDefinition, game: GameState) -> void:
	var live := _live(mission.bonus_objectives)
	if live.is_empty() and mission.par_day <= 0:
		return
	_rows.add_child(UiTheme.hud_label("BONUS", UiTheme.SIZE_MICRO, UiTheme.INK_3))
	for objective: MissionObjective in live:
		_rows.add_child(_condition_row(objective, game))
	if mission.par_day <= 0:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _ROW_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inside := game.day <= mission.par_day
	row.add_child(
		_first_line(_OPEN if inside else _LOST, UiTheme.AMMO if inside else UiTheme.INK_3)
	)
	var words := UiTheme.hud_label(
		"Finish by day %d." % mission.par_day, UiTheme.SIZE_MICRO, UiTheme.WHITE
	)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_labels.append(words)
	row.add_child(words)
	row.add_child(_first_line("day %d/%d" % [game.day, mission.par_day], UiTheme.AMMO))
	_rows.add_child(row)


## The conditions this card may print: the ones the runtime is judging. An empty
## slot is not one, and neither is a hidden objective no event has revealed —
## printing that would hand the player the surprise the mission is holding back
## and put the card at odds with the verdict.
func _live(objectives: Array[MissionObjective]) -> Array[MissionObjective]:
	var live: Array[MissionObjective] = []
	for objective: MissionObjective in objectives:
		if objective != null and objective.is_live(CampaignSession.tally):
			live.append(objective)
	return live


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


## Parks the card under the top bar, in whichever corner `_dock` names. Measured a
## frame late for the reason MissionStrip measures itself: a PanelContainer's size
## is only valid once its labels have been laid out, and these change with every
## command.
func _place() -> void:
	await get_tree().process_frame
	if not visible:
		return
	reset_size()
	position = _dock_position(_dock, get_viewport_rect().size, size)


## Where a card of this size sits in either corner — the one statement of both,
## so the dodge decision and the placement can never disagree about the footprint.
static func _dock_position(dock: int, viewport: Vector2, card_size: Vector2) -> Vector2:
	var x := viewport.x - card_size.x - _MARGIN if dock == _DOCK_RIGHT else float(_MARGIN)
	return Vector2(x, UiTheme.HUD_TOP_H + _MARGIN)


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
