class_name CommanderSelectPanel
extends Control
## The dedicated commander selection page (readiness plan G2). Shown over the
## main menu without tearing it down, so the map, fog, and seat choices behind it
## survive a Back. The player walks the seats the board deals — edit, confirm,
## on to the next — and only when the last one is locked are the picks handed back
## for the match; nothing reaches MatchConfig before that.
##
## One focused CommanderCard carries the full doctrine and power copy; four
## faction tabs and a peer portrait per member let the player browse, and a deliberate
## "No Commander" stays reachable. Every widget is a focusable Control, so mouse,
## keyboard, and controller all drive it through Godot's own focus navigation:
## Left/Right across a row, Up/Down between the tab, portrait, and button rows.
## No information hides behind hover, and none behind colour alone — the emblem
## and faction name back every tint.
##
## Pure presentation: it reads CommanderDB to list the roster and emits the chosen
## ids, one per seat. It never starts the battle or touches core/.

signal confirmed(picks: Dictionary)
signal cancelled

## How many seats a duel deals — the roster every board had before a map could
## seat more, and what `begin` falls back to if it is handed nothing.
const DUEL_SEATS := 2

const _TITLE_SIZE := 15
const _MINI_H := 82
## The selection accent, kept through the alignment pass (menu-revamp D6): gold is
## this page's own signal for "locked", distinct from the faction fills.
const GOLD := Color(0.957, 0.745, 0.196)
## The private slate/muted palette swaps for the shared UiTheme tokens it already
## sat a shade from, so the select page and the menu speak one grey (plan MN3).
const _INACTIVE := UiTheme.SLATE_800
const _MUTED := UiTheme.NEUTRAL_LIGHT

var _db: CommanderDB
## faction key -> Array[CommanderType], the faction's members in name order.
var _by_faction: Dictionary = {}
var _faction_keys: Array[StringName] = []

var _slot := 0
var _picks: Array[StringName] = []
## The seats being walked, in seat order — parallel to `_picks`. The seats that
## *play*, which on a board with one closed is not `1..n`: a commander belongs to
## an army, so a chip, a livery and the confirmed pick all key to the seat's own
## number rather than to its place in the walk (open-seats plan D4).
var _seats: Array[int] = []
## Seats the computer plays, so a chip can say CPU rather than Player N.
var _ai_seats: Array[int] = []
## The commander currently previewed (not yet locked) for the active side.
var _current: CommanderType
var _faction_index := 0

var _card: CommanderCard
var _title: Label
var _chip_bar: HBoxContainer
var _chips: Array[PanelContainer] = []
var _chip_labels: Array[Label] = []
var _tab_buttons: Array[Button] = []
var _mini_buttons: Array[Button] = []
var _mini_marks: Array[ColorRect] = []
var _summary_label: Label
var _confirm_button: Button
var _back_button: Button
var _no_co_button: Button


func _ready() -> void:
	_db = CommanderDB.load_default()
	_group_roster()
	_build()
	hide()


## Groups every non-neutral commander under its faction key, keeping CommanderDB's
## faction-then-name order so the tabs and peer rows are stable.
func _group_roster() -> void:
	for theme: CommanderVisuals.FactionTheme in CommanderVisuals.faction_themes():
		_faction_keys.append(theme.key)
		_by_faction[theme.key] = [] as Array[CommanderType]
	for commander in _db.all():
		if commander.id == CommanderType.NEUTRAL_ID:
			continue
		var key := CommanderVisuals.key_for_faction(commander.faction)
		if _by_faction.has(key):
			_by_faction[key].append(commander)


## Opens the page for a fresh set of picks, one per seat the match fills.
## `ai_seats` only changes how a slot is labelled — CPU rather than Player N —
## because every seat's commander is chosen here whoever ends up playing it.
##
## A caller naming no seats gets the duel every board was before one could be
## closed, which is what keeps this page openable from a fixture or a capture that
## has no strip to ask.
func begin(seats: Array[int], ai_seats: Array[int] = []) -> void:
	_ai_seats = ai_seats.duplicate()
	_seats = seats.duplicate()
	while _seats.size() < DUEL_SEATS:
		_seats.append(_seats.size() + 1)
	_slot = 0
	_picks.clear()
	for _i in _seats.size():
		_picks.append(CommanderType.NEUTRAL_ID)
	_build_chips()
	show()
	_refresh_chips()
	_set_faction(0)
	_grab_first_mini()


## Dev capture only: locks each seat's current preview until `seat` is the one in
## hand, so a screenshot can prove the confirm → next seat transition and the
## chip/summary update. Seat-indexed rather than "Blue" because the walk is as
## long as the board's roster now, and the widest chip bar is the *last* seat —
## the state the top bar has to be photographed in to prove it fits.
## Drives the same _confirm the Confirm button does. Not on any play path.
func debug_advance_to_seat(seat: int) -> void:
	if seat < 1 or seat > _picks.size():
		push_error("No seat %d: this capture shows seat %d, not that one." % [seat, _slot + 1])
		return
	while _slot + 1 < seat:
		var before := _slot
		_confirm()
		if _slot == before:
			return


## Dev capture only: browses to one commander by id, through the same tab-and-focus
## path a player's arrow keys take. It exists so a capture can photograph a *named*
## card rather than only whichever the first tab opens on — the roster's tallest
## copy is the one worth looking at, and it is not the first. Not on any play path.
##
## An unknown id is reported rather than resolved quietly: CommanderDB.by_id falls
## back to neutral by design, which here would photograph the first card and look
## exactly like a capture that named nobody — a typo has to be visible in the output
## or the shot proves the wrong thing.
func debug_preview(id: StringName) -> void:
	if not _db.has(id):
		push_error("No commander '%s': this capture shows the first card, not that one." % id)
	_focus_commander(id)


## What a capture of this page measures itself against: the title, every seat
## chip, and all three actions. The setup panel behind this one has had such a
## gate since COM-5 — a page that renders a perfectly good picture with a control
## off the right edge is exactly what a frame check is for — and this page had
## none, which is how a top bar that grew from a fixed pair of chips to one per
## seat shipped without anyone walking it at four.
func chrome() -> Dictionary[String, Control]:
	var named: Dictionary[String, Control] = {
		"the select page title": _title,
		"No Commander": _no_co_button,
		"Back": _back_button,
		"Confirm Pick": _confirm_button,
	}
	for i in _chips.size():
		named["seat chip %d" % (i + 1)] = _chips[i]
	return named


# --- build -------------------------------------------------------------------


func _build() -> void:
	# Anchors *and* offsets: set_anchors_preset alone rewrites the offsets to
	# preserve the rect the control already has, which for a page built in code and
	# added to an already-sized menu is 0x0. That is what left this whole page laid
	# out at its content's minimum size in the top-left corner, with nothing bounded
	# by the viewport — the ground COM-31's missing Confirm button grew from.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(UiTheme.SLATE_900.r, UiTheme.SLATE_900.g, UiTheme.SLATE_900.b, 0.985)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	add_child(margin)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	margin.add_child(main)

	main.add_child(_build_topbar())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(body)

	# The card is bounded, never free-standing. Its height is content-driven, and a
	# long doctrine used to stretch the body row past the bottom of the viewport,
	# carrying the Confirm button off-screen with it (COM-31). A ScrollContainer
	# stops the card's minimum height propagating up, so the actions row and the
	# footer legend hold their place whatever a general's copy says. At
	# READING_WIDTH the whole shipped roster fits, so the bar never appears — the
	# scroll is the guarantee, not the mechanism.
	var card_frame := ScrollContainer.new()
	card_frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(card_frame)

	_card = CommanderCard.new()
	_card.custom_minimum_size.x = CommanderCard.READING_WIDTH
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card_frame.add_child(_card)

	body.add_child(_build_right_column())

	# The control legend in Silkscreen — a key-hint badge is the textbook home for
	# the design system's stat face, and it brings the second font onto the page.
	var footer := Label.new()
	footer.add_theme_font_override("font", UiTheme.stat())
	footer.add_theme_font_size_override("font_size", 8)
	footer.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	footer.text = "ARROWS / TAB  BROWSE      ENTER  CONFIRM      ESC  BACK      MOUSE OK"
	main.add_child(footer)


func _build_topbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)

	_title = Label.new()
	_title.text = "SELECT COMMANDER"
	_title.add_theme_font_override("font", UiTheme.display(true))
	_title.add_theme_font_size_override("font_size", _TITLE_SIZE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_title)

	# One chip per seat, built when the page opens: how many there are is the
	# board's answer, not this page's.
	_chip_bar = HBoxContainer.new()
	_chip_bar.add_theme_constant_override("separation", 4)
	bar.add_child(_chip_bar)
	return bar


func _build_right_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for i in _faction_keys.size():
		var theme := CommanderVisuals.theme_for_key(_faction_keys[i])
		var tab := Button.new()
		tab.text = String(theme.key).capitalize()
		tab.add_theme_font_override("font", UiTheme.display())
		tab.add_theme_font_size_override("font_size", 10)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.focus_entered.connect(_set_faction.bind(i))
		tab.pressed.connect(_focus_faction.bind(i))
		tabs.add_child(tab)
		_tab_buttons.append(tab)
	col.add_child(tabs)

	var mini_row := HBoxContainer.new()
	mini_row.name = "MiniRow"
	mini_row.add_theme_constant_override("separation", 6)
	mini_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(mini_row)

	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", _flat(Color(0.145, 0.165, 0.180)))
	summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary_label = _small_label(10)
	_summary_label.add_theme_color_override("font_color", Color(0.741, 0.765, 0.780))
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_child(_pad(_summary_label, 8, 6))
	col.add_child(summary)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_no_co_button = _action_button("No Commander")
	# Selects, never locks: "No Commander" is one more thing to browse to, and it is
	# confirmed like every other pick (COM-7). Locking on the press made it the one
	# control on the page that took a side in a single step, and left Enter meaning
	# two different things depending on where focus happened to be.
	_no_co_button.focus_entered.connect(_preview_neutral)
	_no_co_button.pressed.connect(_preview_neutral)
	actions.add_child(_no_co_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_back_button = _action_button("Back")
	_back_button.pressed.connect(_back)
	actions.add_child(_back_button)
	_confirm_button = _action_button("Confirm Pick")
	_confirm_button.pressed.connect(_confirm)
	actions.add_child(_confirm_button)
	col.add_child(actions)
	return col


## The three footer actions wear the shared cream button — hard shadow, press-down,
## hover brighten, all from UiTheme's one implementation, so a press feels the same
## here as on the menu (plan MN3).
func _action_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY, null, 10)
	return button


# --- roster navigation -------------------------------------------------------


## Switches the active faction and previews its first member. Does not move focus,
## so arrowing Left/Right across the tab row browses factions cleanly.
func _set_faction(index: int) -> void:
	_faction_index = index
	for i in _tab_buttons.size():
		_style_tab(_tab_buttons[i], i == index)
	_rebuild_minis()
	if not _members().is_empty():
		_preview(_members()[0])


## A mouse click on a tab switches faction and drops focus onto the first peer,
## so the click lands somewhere sensible for the keyboard to continue from.
func _focus_faction(index: int) -> void:
	_set_faction(index)
	_grab_first_mini()


func _members() -> Array[CommanderType]:
	return _by_faction.get(_faction_keys[_faction_index], [] as Array[CommanderType])


## Deferred: freshly-created buttons are not in the focus system until the frame
## settles, so an immediate grab_focus is a no-op and the viewport falls back to
## focusing the first tab. Deferring lands focus on the portrait, as intended.
func _grab(button: Control) -> void:
	if button != null:
		button.grab_focus.call_deferred()


func _grab_first_mini() -> void:
	if not _mini_buttons.is_empty():
		_grab(_mini_buttons[0])


func _rebuild_minis() -> void:
	var row := _mini_buttons[0].get_parent() if not _mini_buttons.is_empty() else _find_mini_row()
	for button in _mini_buttons:
		button.free()  # immediate, never called from a mini's own callback
	_mini_buttons.clear()
	_mini_marks.clear()
	for commander: CommanderType in _members():
		var mini := _make_mini(commander, row)
		_mini_buttons.append(mini)


func _find_mini_row() -> HBoxContainer:
	return find_child("MiniRow", true, false) as HBoxContainer


func _make_mini(commander: CommanderType, row: HBoxContainer) -> Button:
	var theme := CommanderVisuals.theme_for(commander)
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, _MINI_H)
	button.clip_contents = true
	button.add_theme_stylebox_override("normal", _hard(theme.color_dark, 2))
	button.add_theme_stylebox_override("hover", _hard(theme.color, 2))
	button.add_theme_stylebox_override("focus", _hard(GOLD, 2))
	button.add_theme_stylebox_override("pressed", _hard(GOLD, 2))
	row.add_child(button)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 0)
	button.add_child(content)

	var stage := Panel.new()
	stage.add_theme_stylebox_override("panel", _flat(theme.color))
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	content.add_child(stage)
	var portrait := TextureRect.new()
	portrait.texture = CommanderVisuals.portrait_for(commander)
	portrait.texture_filter = CommanderVisuals.ART_FILTER
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(portrait)

	var name_label := _small_label(8)
	name_label.text = commander.display_name
	name_label.add_theme_color_override("font_color", theme.ink)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var name_wrap := PanelContainer.new()
	name_wrap.add_theme_stylebox_override("panel", _flat(theme.color_dark))
	name_wrap.add_child(_pad(name_label, 2, 1))
	content.add_child(name_wrap)
	UiTheme.make_decoration(content)

	var mark := ColorRect.new()
	mark.color = GOLD
	mark.anchor_left = 1.0
	mark.anchor_right = 1.0
	mark.offset_left = -13.0
	mark.offset_top = 3.0
	mark.offset_right = -3.0
	mark.offset_bottom = 13.0
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = false
	button.add_child(mark)
	_mini_marks.append(mark)

	button.focus_entered.connect(_preview.bind(commander))
	button.pressed.connect(_preview.bind(commander))
	return button


func _preview(commander: CommanderType) -> void:
	_current = commander
	_card.bind(commander)
	for i in _mini_buttons.size():
		_mini_marks[i].visible = _members()[i].id == commander.id
	_refresh_summary()
	_refresh_chips()  # the active side's chip tracks the browse, mirror fallback and all


func _preview_neutral() -> void:
	_preview(CommanderType.neutral())


# --- confirm / back ----------------------------------------------------------


func _confirm() -> void:
	if _current == null:
		return
	_picks[_slot] = _current.id
	if _slot + 1 < _picks.size():
		_slot += 1
		_refresh_chips()
		_set_faction(0)
		_grab_first_mini()
		return
	var chosen: Dictionary = {}
	for i in _picks.size():
		chosen[_seats[i]] = _picks[i]
	confirmed.emit(chosen)


func _back() -> void:
	if _slot > 0:
		_slot -= 1  # back to the seat before, restoring the pick it locked
		_refresh_chips()
		_focus_commander(_picks[_slot])
		return
	hide()
	cancelled.emit()


## The page's two global keys, and the footer has always promised both: Esc backs
## out from anywhere, Enter confirms the browsed pick from anywhere (COM-7).
##
## Enter is read here rather than left to the focused control because browsing
## already *is* selecting — every tab and portrait previews on focus_entered, so
## whatever the player is looking at is the pick, and the focused control's own
## ui_accept would merely re-run what focus already did. Back is the one
## exception: it is a destination, not a selection, so Enter on it goes back.
##
## `_input`, not `_shortcut_input`, and the release is swallowed with the press.
## Both halves are load-bearing: shortcuts are walked after the GUI, and a Button
## activates on the *release*, so a press-only handler sitting behind the GUI
## confirms and then lets the focused button fire too — on Confirm Pick that
## locked Side 1 and Side 2 with one keystroke.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_back()
		accept_event()
	elif event.is_action("ui_accept") and _focus_owner() != _back_button:
		if event.is_action_pressed("ui_accept"):
			_confirm()
		accept_event()


func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner()


## Moves the tab/preview/focus to a specific commander id (used when Back restores
## the Red pick). Neutral falls through to the first faction's first member.
func _focus_commander(id: StringName) -> void:
	var commander := _db.by_id(id)
	if commander.id == CommanderType.NEUTRAL_ID:
		_set_faction(0)
		_grab_first_mini()
		return
	var key := CommanderVisuals.key_for_faction(commander.faction)
	var index := _faction_keys.find(key)
	_set_faction(index if index >= 0 else 0)
	for i in _members().size():
		if _members()[i].id == id and i < _mini_buttons.size():
			_grab(_mini_buttons[i])
			return
	_grab_first_mini()


# --- chrome refresh ----------------------------------------------------------


## The seat chips, live from the picks as they stand. A seat already walked past
## or in hand stays filled and shows its livery; the seats after it are named but
## uncoloured, and the moment two land on one faction the later one shows the
## borrowed classic (D3), not a day-1 surprise.
##
## A roster past a duel takes the terse form — "1 · Meridian — P1" rather than
## "1 · Meridian Coalition — Player 1" — because by the last seat every chip
## carries the long one, and four of those run off the right of a 640px frame.
## A duel keeps the long form, so a two-seat page is unchanged.
func _refresh_chips() -> void:
	var identity := _preview_identity()
	var terse := _chips.size() > DUEL_SEATS
	for i in _chips.size():
		var seat: int = _seats[i]
		var who := _seat_role(seat, terse)
		if i > _slot:
			# Not reached yet: named but uncoloured, so the walk's remaining length
			# is visible without claiming a livery nothing has chosen.
			_paint_chip(_chips[i], _chip_labels[i], "%d · %s" % [seat, who], null)
			continue
		_paint_chip(
			_chips[i],
			_chip_labels[i],
			"%d · %s — %s" % [seat, _seat_name(identity, seat, terse), who],
			identity.theme(seat)
		)


## What a chip calls a seat, asked of the identity that owns the answer and
## shortened to its first word for the terse form — never re-derived from the
## theme key, because a mirror side keeps its faction's name while its colour is
## borrowed (faction-identity D3), and a chip reading the key would then
## contradict the commander card beside it.
func _seat_name(identity: SideIdentity, seat: int, terse: bool) -> String:
	var full := identity.display_name(seat)
	return full.get_slice(" ", 0) if terse else full


func _seat_role(seat: int, terse: bool) -> String:
	if _ai_seats.has(seat):
		return "CPU"
	return "P%d" % seat if terse else "Player %d" % seat


## The identity the current picks would produce: every seat already locked, plus
## the one being previewed in hand. Resolving the whole thing rather than each
## chip alone is what lets the mirror fallback show live.
func _preview_identity() -> SideIdentity:
	var picks: Dictionary = {}
	for i in _picks.size():
		if i < _slot:
			picks[_seats[i]] = _db.by_id(_picks[i])
		elif i == _slot:
			picks[_seats[i]] = _current
		else:
			picks[_seats[i]] = null
	return SideIdentity.resolve(picks)


## Deals one chip per seat. Rebuilt on every `begin`, because how many seats
## there are is the board's answer and the page is opened per match.
func _build_chips() -> void:
	for child in _chip_bar.get_children():
		_chip_bar.remove_child(child)
		child.queue_free()
	_chips.clear()
	_chip_labels.clear()
	for _i in _picks.size():
		var chip := PanelContainer.new()
		var label := _small_label(9)
		chip.add_child(_pad(label, 7, 3))
		_chip_bar.add_child(chip)
		_chips.append(chip)
		_chip_labels.append(label)


## Fills a chip in a side's theme, or greys it (theme null) when the side is not
## yet in hand.
func _paint_chip(
	chip: PanelContainer, label: Label, text: String, theme: CommanderVisuals.FactionTheme
) -> void:
	chip.add_theme_stylebox_override("panel", _flat(theme.color if theme != null else _INACTIVE))
	label.add_theme_color_override("font_color", theme.ink if theme != null else _MUTED)
	label.text = text


func _refresh_summary() -> void:
	var slot := "Side %d of %d" % [_slot + 1, _picks.size()]
	var text := "%s — browse a faction, then Confirm." % slot
	if _current != null:
		var theme := CommanderVisuals.theme_for(_current)
		text = "%s · %s\nSelected: %s." % [slot, theme.display, _current.display_name]
	if _slot > 0:
		var locked := PackedStringArray()
		for i in _slot:
			locked.append("Side %d is %s" % [i + 1, _db.by_id(_picks[i]).display_name])
		text += "  %s." % ", ".join(locked)
	_summary_label.text = text


func _style_tab(tab: Button, active: bool) -> void:
	var theme := CommanderVisuals.theme_for_key(_faction_keys[_tab_buttons.find(tab)])
	tab.add_theme_stylebox_override("normal", _hard(theme.color if active else _INACTIVE, 2))
	tab.add_theme_stylebox_override("hover", _hard(theme.color_light if active else theme.color, 2))
	tab.add_theme_stylebox_override("focus", _hard(GOLD, 2))
	tab.add_theme_stylebox_override("pressed", _hard(theme.color, 2))
	tab.add_theme_color_override(
		"font_color", Color.WHITE if active else Color(0.753, 0.776, 0.792)
	)


# --- style helpers -----------------------------------------------------------


func _small_label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UiTheme.display())
	label.add_theme_font_size_override("font_size", size)
	return label


func _pad(child: Control, h: int, v: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", h)
	margin.add_theme_constant_override("margin_right", h)
	margin.add_theme_constant_override("margin_top", v)
	margin.add_theme_constant_override("margin_bottom", v)
	margin.add_child(child)
	return margin


func _flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


func _hard(border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = _INACTIVE
	box.border_color = border
	box.set_border_width_all(width)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	# The signature hard offset shadow, from the one authority (plan MN3).
	return UiTheme.hard_shadow(box)
