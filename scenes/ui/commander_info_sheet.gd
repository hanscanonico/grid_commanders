class_name CommanderInfoSheet
extends Control
## The in-battle commander reference: every army's full card, opened from the
## battle menu rather than a hover tooltip (readiness plan G3). Showing them all
## is deliberate and safe — a commander's identity and doctrine are match
## metadata, not a fog-hidden unit position, so nothing here leaks what the viewer
## cannot see on the board.
##
## One card per seat the board dealt, laid out two to a row and ordered so allies
## sit together (four-players plan D5): a duel is the single row it always was, a
## 2v2 is a pair over a pair.
##
## Reuses the same CommanderCard the selection page does; the only thing new is a
## faction header over each, named and tinted by the resolved side identity (a
## mirror shows the borrowed classic). Pure presentation — it reads the match's
## CommanderTypes and closes itself; Battle owns when it opens and blocks board
## input while it is up.

signal closed

## Scrolling the cards is the sheet's own, exactly as the end-turn guard's list is
## its own: a direction reaches here as the board's action or as Godot's built-in
## one, so both are answered and DirectionalInput collapses the pair one gesture
## fires into a single line.
const SCROLL_ACTIONS: Dictionary = {
	&"cursor_up": -1,
	&"ui_up": -1,
	&"cursor_down": 1,
	&"ui_down": 1,
}

var _built := false
## The card grid; columns are rebuilt per match, because how many there are is the
## board's answer and not this scene's.
var _cards: GridContainer
## One scroll frame per open card, in layout order — each holds exactly its card,
## which is what `layout_error` measures the shown slice against.
var _frames: Array[ScrollContainer] = []
var _close_button: Button
## One scroll line per directional gesture; see DirectionalInput.
var _dirs := DirectionalInput.new()


func _ready() -> void:
	_build()
	hide()


## Shows one card per army and takes focus, so a controller or keyboard can close
## it without reaching for the mouse.
##
## `commanders_by_team` is the match's picks and `sides` its grouping — both taken
## whole rather than as a pair, because how many armies play is the board's answer
## (four-players plan D1) and how they group is the match's.
func open(commanders_by_team: Dictionary, sides: Dictionary = {}) -> void:
	if not _built:
		_build()
	# The same resolver the board uses, so a mirror match shows the borrowed
	# classic here too: two Iron doctrines read "IRON DOMINION" over slate and blue.
	var identity := SideIdentity.resolve(commanders_by_team)
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	_frames.clear()
	for team: int in _seat_order(commanders_by_team, sides):
		_titled_card(_cards, identity, team).bind(commanders_by_team.get(team))
	show()
	_close_button.grab_focus.call_deferred()


## The seats to lay out, allies adjacent: sides ordered by their lowest seat, and
## each side's members in seat order. A free-for-all is therefore plain seat
## order, which is what a duel has always shown.
static func _seat_order(commanders_by_team: Dictionary, sides: Dictionary) -> Array[int]:
	var seats: Array[int] = []
	for team: int in commanders_by_team:
		seats.append(team)
	seats.sort()
	var grouped: Array[int] = []
	for team in seats:
		if grouped.has(team):
			continue
		grouped.append(team)
		for other in seats:
			if other != team and sides.has(team) and sides.get(other) == sides[team]:
				if not grouped.has(other):
					grouped.append(other)
	return grouped


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	# Near-solid, not the 0.97 written here before: open() used to re-run this build
	# and stack a second veil over the first, so what the screen actually showed was
	# the pair (~0.999). With the duplicate build gone, 0.97 alone let the board ghost
	# through. This keeps the authored "veil over the board" reading without the bleed.
	bg.color = UiTheme.veil(0.995)
	# set_anchors_preset alone rewrites the offsets to preserve the rect a control
	# already has, so it only bites a node that is *already* parented to a sized
	# parent — the sheet's own call above, added to a full-size battle scene. bg and
	# the margin below are freshly created and still parentless when their preset
	# runs: the parent rect is empty, the offsets stay 0, and either form covers.
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# A bounded margin, not a CenterContainer: centring a column taller than the
	# screen pushes both its ends off, which is how the Close button used to leave
	# the viewport (COM-31, the same overflow the select page had). Here the cards
	# row absorbs the slack and the title and button keep their edges.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, UiTheme.PAGE_MARGIN)
	add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)

	# No page title: the faction headers below already name what this is, and on
	# a 360px-tall screen the row it would cost is the difference between the cards
	# fitting and the Close button being crowded.
	# Two to a row: a duel is one row of two exactly as it always was, and four
	# armies are a 2x2 rather than a strip too wide for the screen. Columns are
	# built per match by open(), because how many there are is the board's answer.
	_cards = GridContainer.new()
	_cards.columns = 2
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 6)
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rows.add_child(_cards)

	# The meter's number is a funds-valued damage total, but the exact accounting
	# is less important here than the missing player-facing answer to "what makes
	# this rise?" Keep it on the reference sheet rather than duplicating charge
	# rules inside every commander card.
	var charge_help := Label.new()
	charge_help.text = "Command Power charges as your armies take and deal damage."
	charge_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	charge_help.add_theme_font_override("font", UiTheme.display())
	charge_help.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	charge_help.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	rows.add_child(charge_help)

	_close_button = Button.new()
	_close_button.text = "Close"
	UiTheme.apply_button(_close_button, UiTheme.ButtonVariant.SECONDARY)
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_button.pressed.connect(_emit_close)
	rows.add_child(_close_button)

	# The sheet's veil covers the top bar, so the board's key legend is not on
	# screen while it is up — which is why the other full-screen pages carry a
	# footer of their own, in this same recipe.
	var footer := Label.new()
	footer.text = "UP/DOWN  SCROLL      ESC  CLOSE      MOUSE OK"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_override("font", UiTheme.stat())
	footer.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	footer.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	rows.add_child(footer)

	_built = true


## Builds one column — a header band over a CommanderCard — named and tinted from
## the side's resolved identity, so this scene never hardcodes a name or a colour
## and a mirror shows the classic it borrowed.
func _titled_card(parent: Node, identity: SideIdentity, team: int) -> CommanderCard:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# A grid row is only as tall as its shortest-demanding child asks to be, so a
	# column that does not expand ends at the header band and leaves the scroll
	# frame below it zero pixels high — the card renders, into nothing. When these
	# columns were direct children of an HBox that filled the sheet the height came
	# for free; under the grid it has to be asked for.
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(column)

	# The design system's title band, tinted to the side — the same recipe the
	# menu's "MATCH SETUP" header wears. Dressed with the card under it, or the
	# faction name would be the one line on this sheet still set in the OS font.
	var side := identity.theme(team)
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiTheme.header_box(side.color))
	var label := Label.new()
	label.text = identity.display_name(team).to_upper()
	label.add_theme_font_override("font", UiTheme.display(true))
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_TITLE)
	label.add_theme_color_override("font_color", side.ink)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(label)
	column.add_child(header)

	# Same bounded frame the select page gives its card: the card's height is
	# content-driven, so it is the one child allowed to run out of room, and the
	# scroll keeps that from reaching the Close button.
	var frame := ScrollContainer.new()
	frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Neither the frame nor its bar may take focus, or an arrow key is spent on
	# focus navigation before _unhandled_input ever sees it and the cards never
	# move — the same pairing the end-turn guard's list needs.
	frame.focus_mode = Control.FOCUS_NONE
	frame.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	column.add_child(frame)

	# READING_WIDTH, the width the select page asks for, and not a pixel more: it is
	# the width every line of shipped copy needs to stop wrapping, and pinning it
	# here is what makes this sheet and the select page frame a general identically.
	# Stretched to fill this column instead, the same card reads as a second design.
	var card := CommanderCard.new()
	card.custom_minimum_size.x = CommanderCard.READING_WIDTH
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.add_child(card)
	_frames.append(frame)
	return card


## Why the open sheet is not showing what it was opened with, or "" when it is.
##
## A read off the live controls rather than a look at the frame, the way the
## cut-in scenarios read their atlas rows back off the posed art: the smoke
## sweep's bar is a file size, so a sheet that drew its faction headers over
## collapsed columns wrote a perfectly healthy PNG and passed (COM-47 review).
## The slice each card is *shown* through is the measure — a card sized normally
## inside a zero-tall scroll frame renders into nothing — and one that cannot even
## show its portrait band is showing nothing worth photographing.
func layout_error(expected_cards: int) -> String:
	if _frames.size() != expected_cards:
		return (
			"the commander sheet laid out %d cards for %d armies" % [_frames.size(), expected_cards]
		)
	for frame in _frames:
		var card: Control = frame.get_child(0)
		var shown := card.get_global_rect().intersection(frame.get_global_rect()).size.y
		if shown < CommanderCard.PORTRAIT_H:
			return (
				"a commander card is shown %.0fpx tall, less than its %dpx portrait band"
				% [shown, CommanderCard.PORTRAIT_H]
			)
	return ""


## How far down the cards are scrolled, in pixels — one number for the sheet,
## because every card steps together. The scenario driver's read that a key
## really reached here.
func scroll_offset() -> int:
	return 0 if _frames.is_empty() else _frames[0].scroll_vertical


func _unhandled_input(event: InputEvent) -> void:
	var scrolled := _dirs.step(event, SCROLL_ACTIONS.keys())
	if not visible or scrolled.is_empty():
		return
	get_viewport().set_input_as_handled()
	_scroll_cards(SCROLL_ACTIONS[scrolled])


## Steps every card a line at a time, so the doctrine and Command Power copy
## below the fold is reachable without a mouse. The line is measured off the very
## font that copy is set in — as the end-turn guard steps by its list's line
## height — rather than spelled as a number that would drift when the card is
## redressed. Cards are read side by side, so they step together and one offset
## describes the whole sheet. ScrollContainer clamps the value, so a card that
## already fits — or an edge — simply does not move.
func _scroll_cards(delta: int) -> void:
	var step := maxi(int(UiTheme.display().get_height(UiTheme.SIZE_BODY)), 1)
	for frame in _frames:
		frame.scroll_vertical += delta * step


func _shortcut_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_emit_close()
		accept_event()


func _emit_close() -> void:
	hide()
	closed.emit()
