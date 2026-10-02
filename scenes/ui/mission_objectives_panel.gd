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
## It parks in a corner of the band between the two bars and never leaves it, and
## swallows the pointer so a click on it cannot fall through to a cell rendered
## behind it.
##
## A mission whose terms do not fit that band is printed short — each group's
## first open condition and a count of the rest — and O opens the whole list,
## wider, before it lowers the card (playtest CA-01: eight rows ran over the
## bottom bar and hid the gate they named). And a card with no corner clear of the
## cursor and the goal squares shrinks to its title and a count, because in a band
## that short the corners of a card of even a few rows overlap across the middle.

## The four corners of the band the card may sit in, in the order it prefers
## them. It opens top-left and steps to the first corner that covers neither the
## cursor nor the ground the mission still wants, because the fight being under
## the card is exactly when hiding the card is the wrong answer.
const _DOCK_LEFT := 0
const _DOCK_RIGHT := 1
const _DOCK_BOTTOM_LEFT := 2
const _DOCK_BOTTOM_RIGHT := 3
const _DOCKS: Array[int] = [_DOCK_LEFT, _DOCK_RIGHT, _DOCK_BOTTOM_LEFT, _DOCK_BOTTOM_RIGHT]
## What covering the cursor costs a corner against covering one goal square: the
## cursor is where the player is looking, so it outweighs every goal at once.
const _CURSOR_COST := 100

## How far the card sits from the band's edges, and how far its rows sit inside
## it.
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
## The width of the whole list a long mission opens on O: wide enough that its
## sentences wrap to two lines and the list fits the band.
const _WIDE_WIDTH := 280
## The card's marks, and they mean one thing each: ✓ met, · open, ✗ lost, and ◐
## holding — a condition true now that the board can still take back before the
## verdict, which a tick would read as a star already won (playtest CA-17).
## A failure reads the same way round as a condition: its mark lights when it has
## fired, which is the last thing the panel ever draws before the mission ends.
const _MET := "✓"
const _OPEN := "·"
const _LOST := "✗"
const _ONGOING := "◐"

## What the card prints: every condition at its own width, each group cut to its
## first open condition, every condition at the wide width, or the title and how
## many of the win conditions are met.
enum Form { FULL, SHORT, ALL, COMPACT }

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
## Whether the player asked O for the whole of a long mission's list.
var _expanded := false
## Whether this mission's full list has been measured taller than the band. Kept
## for the mission, because a reveal only ever adds conditions.
var _long := false
## Whether the card is printed compact because no corner of the band holds its
## full or short form clear of the cursor and the goal squares.
var _compact := false
## The full or short form's size when it was last laid out, which is what decides
## `_compact` again as the cursor moves while the compact form is the one shown.
var _natural_size := Vector2.ZERO
## The form currently laid out, so a change of form is measured unseen.
var _shown := Form.FULL
## How many conditions the full list was last measured to fit with; a different
## count is measured again before it is shown.
var _fits_rows := -1
## How wide the whole list is drawn, widened past `_WIDE_WIDTH` only when a list
## does not fit the band even there.
var _all_width := _WIDE_WIDTH
## Which corner the card is currently parked in. Presentation and nothing else:
## not a preference, not remembered across missions, and the player never sets it.
var _dock := _DOCK_LEFT
## The last board geometry the cursor reported, kept so a redraw that changes the
## card's size or the goal squares can choose its corner again without a cursor
## move. A zero cell size means nothing has been reported yet.
var _cursor_cell := Vector2i.ZERO
var _cell_size := 0
var _board_origin := Vector2.ZERO
## The squares the mission still wants, from `BattleCampaign.objective_cells`, the
## collector the board's own marks are painted from.
var _goal_cells: Array[Vector2i] = []
var _game: GameState
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
	_game = game
	var available := CampaignSession.active()
	visible = available and _up
	card_changed.emit(available, _up)
	if not visible:
		return
	_goal_cells = BattleCampaign.objective_cells(game)
	_lay_out(_form())
	_place()


## Whether the player has the card up, for the pause menu's row to say which way
## it will go. The up/down state stays this card's own: the row reads it here and
## sets it through `set_up`, so the key and the row can never disagree.
func is_up() -> bool:
	return _up


## The O key. A card that fits goes down and comes back up; a short or compact
## card opens its whole list first, and that lowers next. It is redrawn on
## the way up rather than merely shown, because the board it describes has been
## played on while it was down — `refresh` does nothing beyond the chip while the
## card is lowered, which is what keeps a card nobody is looking at off every
## command's path.
func toggle(game: GameState) -> void:
	if _up and (_long or _compact) and not _expanded:
		_expanded = true
	else:
		_up = not _up
		_expanded = false
	refresh(game)


## The pause menu's Objectives row, which says On or Off and so only ever raises
## or lowers the card.
func set_up(up: bool, game: GameState) -> void:
	_up = up
	_expanded = false
	refresh(game)


## Steps the card out of the cursor's way, called from `BoardCamera.move_cursor_to`
## — the seam the board cursor already reports through, so nothing polls. The
## common case is a dock that did not change and costs one geometry read.
func follow_cursor(
	cell: Vector2i, cell_size: int, board_origin: Vector2, viewport: Vector2
) -> void:
	_cursor_cell = cell
	_cell_size = cell_size
	_board_origin = board_origin
	if visible:
		_redock(viewport)


## Which corner the card belongs in with the cursor on `cursor_cell` and the
## mission still wanting `goal_cells`. Geometry only: it reads no mission and no
## session, so where the card sits can never depend on how it is worded. Static
## and argument-taking so the rule is checked without a scene, the shape
## `SeatStrip.normalised_sides` and `TransitionInput` are.
##
## Home wins whenever it covers nothing. Otherwise the card stays where it is
## unless another corner covers strictly less — so a cursor still working the
## top-left keeps the card away, one that follows it into the right corner sends
## it home, and a card covered wherever it sits is not handed back and forth.
static func dock_for(
	cursor_cell: Vector2i,
	goal_cells: Array[Vector2i],
	cell_size: int,
	board_origin: Vector2,
	viewport: Vector2,
	card_size: Vector2,
	current_dock: int
) -> int:
	var costs := _dock_costs(cursor_cell, goal_cells, cell_size, board_origin, viewport, card_size)
	if costs[_DOCK_LEFT] == 0:
		return _DOCK_LEFT
	var least: int = costs.min()
	if costs[current_dock] == least:
		return current_dock
	return costs.find(least)


## Whether a card of `card_size` covers the cursor or a goal square in every
## corner, so it has to be printed compact to keep off the ground the mission is
## about. Geometry only, for the reason `dock_for` is.
static func compact_for(
	cursor_cell: Vector2i,
	goal_cells: Array[Vector2i],
	cell_size: int,
	board_origin: Vector2,
	viewport: Vector2,
	card_size: Vector2
) -> bool:
	var costs := _dock_costs(cursor_cell, goal_cells, cell_size, board_origin, viewport, card_size)
	return costs.min() > 0


## What each corner covers, in `_DOCKS` order: `_CURSOR_COST` for the cursor and
## one for each goal square.
static func _dock_costs(
	cursor_cell: Vector2i,
	goal_cells: Array[Vector2i],
	cell_size: int,
	board_origin: Vector2,
	viewport: Vector2,
	card_size: Vector2
) -> Array[int]:
	var costs: Array[int] = []
	for dock in _DOCKS:
		var card := Rect2(_dock_position(dock, viewport, card_size), card_size)
		var cost := 0
		if card.intersects(_cell_rect(cursor_cell, cell_size, board_origin)):
			cost += _CURSOR_COST
		for cell in goal_cells:
			if card.intersects(_cell_rect(cell, cell_size, board_origin)):
				cost += 1
		costs.append(cost)
	return costs


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
	add_theme_stylebox_override("panel", UiTheme.dark_panel_box(UiTheme.SLATE_800, _PAD, _PAD - 1))
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
	head.add_child(UiTheme.hud_label("MISSION", UiTheme.SIZE_STAT, UiTheme.INK_3))
	_title_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.PAPER_2)
	head.add_child(_title_label)

	_where_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.INK_3)
	_where_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_where_label)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_rows)

	hide()
	_built = true


## Which form the card prints in: the whole list when the player asked for it,
## the compact one while no corner is clear, and otherwise the full list until it
## has been measured too tall for the band, then the short one.
func _form() -> Form:
	if _expanded:
		return Form.ALL
	if _compact:
		return Form.COMPACT
	return Form.SHORT if _long else Form.FULL


## Rebuilds the rows in `form` from the last board handed over. A change of form,
## or a full list not yet measured at this many conditions, is laid out unseen, so
## a card in the wrong corner or too tall for the band never shows for the frame
## it takes to find that out.
func _lay_out(form: Form) -> void:
	var mission := CampaignSession.mission
	var changed := form != _shown
	_shown = form
	var compact := form == Form.COMPACT
	custom_minimum_size.x = _all_width if form == Form.ALL else (0 if compact else _WIDTH)
	_title_label.text = mission.title
	_where_label.text = mission.location
	_where_label.visible = mission.location != "" and form != Form.SHORT and not compact
	for child in _rows.get_children():
		child.queue_free()
		_rows.remove_child(child)
	_row_labels.clear()
	if compact:
		_count_row(mission)
	else:
		var short := form == Form.SHORT
		_group("WIN", mission.objectives, short)
		_group("LOSE", mission.failures, short)
		_bonus_group(mission, short)
		if form != Form.FULL:
			var key := ControlHints.ALL_TERMS_CHIP if short else ControlHints.HIDE_TERMS_CHIP
			_rows.add_child(
				UiTheme.hud_label(ControlHints.chip_for(key), UiTheme.SIZE_STAT, UiTheme.INK_3)
			)
	if changed or (form == Form.FULL and _row_labels.size() != _fits_rows):
		modulate.a = 0.0


## The compact form's one line: how many win conditions are met, and the key
## that opens them all.
func _count_row(mission: MissionDefinition) -> void:
	var live := _live(mission.objectives)
	var met := 0
	for objective: MissionObjective in live:
		if objective.is_met(_game, mission.player_team, CampaignSession.tally):
			met += 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _ROW_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not live.is_empty():
		row.add_child(UiTheme.hud_label("WIN", UiTheme.SIZE_STAT, UiTheme.INK_3))
		row.add_child(
			UiTheme.hud_label("%d/%d" % [met, live.size()], UiTheme.SIZE_STAT, UiTheme.AMMO)
		)
	var words := ControlHints.chip_for(ControlHints.ALL_TERMS_CHIP)
	if not live.is_empty():
		words = "· " + words
	var key := UiTheme.hud_label(words, UiTheme.SIZE_STAT, UiTheme.INK_3)
	_row_labels.append(key)
	row.add_child(key)
	_rows.add_child(row)


## One heading and the conditions under it, or nothing at all when a mission
## names none — a card with an empty BONUS heading advertises a star that does
## not exist. A heading whose every condition is still hidden is that same empty
## heading, so the filter comes first: on a LOSE group especially, naming the
## group alone would tell the player a trap is coming.
##
## The short form keeps the first condition still open and counts the rest.
func _group(heading: String, objectives: Array[MissionObjective], short: bool) -> void:
	var live := _live(objectives)
	if live.is_empty():
		return
	_rows.add_child(UiTheme.hud_label(heading, UiTheme.SIZE_STAT, UiTheme.INK_3))
	var shown := _first_open(live) if short else live
	for objective: MissionObjective in shown:
		_rows.add_child(_condition_row(objective))
	_more_row(live.size() - shown.size())


## The bonus stars, with the par day the runtime is also judging: the one
## condition on the card that is not a `MissionObjective`, printed here because
## the player is racing a clock nothing else on screen names. A clock still
## running is a condition held rather than one won, so it wears `_ONGOING` in the
## amber its readout beside it already uses, and `_LOST` once par has gone by.
func _bonus_group(mission: MissionDefinition, short: bool) -> void:
	var live := _live(mission.bonus_objectives)
	if live.is_empty() and mission.par_day <= 0:
		return
	_rows.add_child(UiTheme.hud_label("BONUS", UiTheme.SIZE_STAT, UiTheme.INK_3))
	var shown := _first_open(live) if short else live
	for objective: MissionObjective in shown:
		_rows.add_child(_condition_row(objective))
	_more_row(live.size() - shown.size())
	if mission.par_day <= 0:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _ROW_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inside := _game.day <= mission.par_day
	row.add_child(
		_first_line(_ONGOING if inside else _LOST, UiTheme.AMMO if inside else UiTheme.INK_3)
	)
	var words := UiTheme.hud_label(
		"Finish by day %d." % mission.par_day, UiTheme.SIZE_STAT, UiTheme.WHITE
	)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_labels.append(words)
	row.add_child(words)
	row.add_child(_first_line("day %d/%d" % [_game.day, mission.par_day], UiTheme.AMMO))
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


## The one condition the short form keeps from a group: the first not yet met,
## or the first of all once every one is.
func _first_open(live: Array[MissionObjective]) -> Array[MissionObjective]:
	var mission := CampaignSession.mission
	for objective: MissionObjective in live:
		if not objective.is_met(_game, mission.player_team, CampaignSession.tally):
			return [objective]
	return live.slice(0, 1)


## How many conditions the short form left out of a group, or nothing.
func _more_row(hidden: int) -> void:
	if hidden > 0:
		_rows.add_child(UiTheme.hud_label("+%d MORE" % hidden, UiTheme.SIZE_STAT, UiTheme.INK_3))


## A mark, the authored words, and whatever the objective says about its own
## progress. Amber for the readout, which is this design system's "your attention
## here" — the same token the charge meter fills with. A met condition the side
## has to keep until the verdict is marked as held, in that same amber.
func _condition_row(objective: MissionObjective) -> Control:
	var team := CampaignSession.mission.player_team
	var tally := CampaignSession.tally
	var met := objective.is_met(_game, team, tally)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _ROW_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if met and objective.holds_until_verdict():
		row.add_child(_first_line(_ONGOING, UiTheme.AMMO))
	else:
		row.add_child(
			_first_line(_MET if met else _OPEN, UiTheme.CAPTURE if met else UiTheme.INK_3)
		)
	var words := UiTheme.hud_label(objective.text, UiTheme.SIZE_STAT, UiTheme.WHITE)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_labels.append(words)
	row.add_child(words)

	var readout := objective.readout(_game, team, tally)
	if readout != "":
		row.add_child(_first_line(readout, UiTheme.AMMO))
	return row


## A label that stays level with the first line of the wrapping words beside it,
## rather than centring itself against however many lines they took.
func _first_line(text: String, color: Color) -> Label:
	var label := UiTheme.hud_label(text, UiTheme.SIZE_STAT, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return label


## Measures the card a frame late through `UiKit.settled`, which owns that wait,
## and parks it. A card whose rows have not yet been sorted at its own width is
## measured again a frame later, up to `tries` frames.
func _place(tries := 4) -> void:
	if not await UiKit.settled(self):
		return
	if _laid_out() or tries <= 1:
		_fit()
	else:
		_place(tries - 1)


## Whether every condition's words have been given their final width. A row
## sorted before the card was is still as wide as its words on one line, and a
## label not sorted at all stands one pixel wide, a word to a line — either way
## the card measures a height it will not have.
func _laid_out() -> bool:
	var inner := size.x - 2.0 * _PAD
	for label in _row_labels:
		if label.size.x <= 1.0 or label.get_parent_control().size.x > inner + 0.5:
			return false
	return true


## Parks the card if it fits the band between the bars, or prints it in a form
## that will. A full list taller than the band switches the mission to the short
## form for good; a whole list that still does not fit takes the band's width; and
## a full or short card with no corner clear of the cursor and the goals is printed
## compact.
func _fit() -> void:
	if not visible or _game == null or not CampaignSession.active():
		return
	var viewport := get_viewport_rect().size
	var band := MobileDock.board_band(viewport)
	var room := band.size.y - 2.0 * _MARGIN
	var form := _shown
	var natural := form == Form.FULL or form == Form.SHORT
	if form == Form.FULL and size.y > room:
		_long = true
	elif form == Form.ALL and size.y > room and _all_width < band.size.x - 2.0 * _MARGIN:
		_all_width = int(band.size.x) - 2 * _MARGIN
	elif natural and _covered_everywhere(viewport, size):
		_natural_size = size
		_compact = true
	else:
		if natural:
			_natural_size = size
			_compact = false
		if form == Form.FULL:
			_fits_rows = _row_labels.size()
		modulate.a = 1.0
		_redock(viewport)
		return
	_lay_out(_form())
	_place()


## Parks the card in its corner, choosing that corner again first when the cursor
## has reported where it is — and first of all choosing between the compact form
## and the full or short one, which a cursor move can change either way.
func _redock(viewport: Vector2) -> void:
	if not _expanded and _natural_size != Vector2.ZERO:
		var compact := _covered_everywhere(viewport, _natural_size)
		if compact != _compact:
			_compact = compact
			_lay_out(_form())
			_place()
			return
	if _cell_size > 0:
		_dock = dock_for(
			_cursor_cell, _goal_cells, _cell_size, _board_origin, viewport, size, _dock
		)
	position = _dock_position(_dock, viewport, size)


## `compact_for` over the board geometry the cursor last reported; never true
## before it has reported any.
func _covered_everywhere(viewport: Vector2, card_size: Vector2) -> bool:
	if _cell_size <= 0:
		return false
	return compact_for(_cursor_cell, _goal_cells, _cell_size, _board_origin, viewport, card_size)


## Where a card of this size sits in each corner of the band between the bars —
## the one statement of every footprint, so the choice of corner and the placement
## can never disagree about it.
static func _dock_position(dock: int, viewport: Vector2, card_size: Vector2) -> Vector2:
	var band := MobileDock.board_band(viewport).grow(-_MARGIN)
	var right := dock == _DOCK_RIGHT or dock == _DOCK_BOTTOM_RIGHT
	var bottom := dock == _DOCK_BOTTOM_LEFT or dock == _DOCK_BOTTOM_RIGHT
	return Vector2(
		band.end.x - card_size.x if right else band.position.x,
		band.end.y - card_size.y if bottom else band.position.y
	)


## A board square's footprint on screen, in the flat board's geometry.
static func _cell_rect(cell: Vector2i, cell_size: int, board_origin: Vector2) -> Rect2:
	return Rect2(board_origin + Vector2(cell) * float(cell_size), Vector2.ONE * float(cell_size))
