class_name CommanderSelectPanel
extends Control
## The commander page (readiness plan G2): picks the general of ONE seat. Shown
## over the main menu without tearing it down, so the map, fog and seat choices
## behind it survive a Back. A seat row's general chip opens it; Confirm hands
## that one pick back and Back hands nothing — the menu's Start launches the
## match, never this page.
##
## One focused CommanderCard carries the full doctrine and power copy; four
## faction tabs and a peer portrait per member let the player browse, and a deliberate
## "No Commander" stays reachable. A roster tile is a *whole bust* at 1x, so a
## general reads here the way they read on the card beside them: the tile is
## `CommanderVisuals.PORTRAIT_SIZE` wide, the row that holds them scrolls
## sideways under the card's reading width, and the cut-off tile plus the thin
## bar under the row are the cue that there is more to walk to. Every widget is a
## focusable Control, so mouse, keyboard and controller all drive it through
## Godot's own focus navigation:
## Left/Right across a row, Up/Down between the tab, portrait, and button rows.
## No information hides behind hover, and none behind colour alone — the emblem
## and faction name back every tint.
##
## Pure presentation: it reads CommanderDB to list the roster and emits the chosen
## id for its seat. It never starts the battle or touches core/.

signal confirmed(picks: Dictionary)
signal cancelled

## A roster tile's face field: the tile without the name band beneath it, and the
## drawing's own size rather than a number chosen here — under
## `CommanderVisuals.WHOLE_BUST_FIELD` on either axis the tile draws the baked
## face chip at a whole rung instead, which is the chunkier general the picker
## used to show while the card, the cut-in and the info sheet all showed the bust
## (COM-280). The tile is the sum of this field and the name band
## (`_mini_height`), and it never stretches — the row scrolls instead.
const MINI_FACE := CommanderVisuals.PORTRAIT_SIZE
## The lines the name band reserves. A name sets at up to 63 pixels at the body
## size and every single word of the roster fits in 38, so two lines carry the
## given name over the surname on a tile of any width, and the band is kept at
## two now the tile is wider than either (COM-271). Reserved on every tile, so
## the faces stay one row.
const _NAME_LINES := 2
## The band's padding over and under those lines.
const _NAME_PAD := 1
## How far back a portrait another seat already commands is faded, over the
## dead button it also becomes. A general commands one army (`CommanderPicks`),
## and the page says so by greying rather than by refusing a press — the same
## answer the seat strip gives a seat it will not close (COM-224).
const _TAKEN_TINT := Color(1.0, 1.0, 1.0, 0.45)
## The private slate/muted palette swaps for the shared UiTheme tokens it already
## sat a shade from, so the select page and the menu speak one grey (plan MN3).
## The selection gold moved the same way and for the same reason (COM-89): it is
## still this page's own signal for "locked", now stated once, in UiTheme.
const _GOLD := UiTheme.SELECT_GOLD
const _INACTIVE := UiTheme.SLATE_800
const _MUTED := UiTheme.NEUTRAL_LIGHT

var _db: CommanderDB
## faction key -> Array[CommanderType], the faction's members in name order.
var _by_faction: Dictionary = {}
var _faction_keys: Array[StringName] = []
## Every non-neutral commander, flat, for the Random pick to draw from.
var _random_pool: Array[CommanderType] = []

## The seat this page is picking for, by its own number (open-seats plan D4).
var _seat := 1
## Whether the computer plays that seat, so the title chip can say CPU.
var _is_cpu := false
## seat -> id for every *other* seat's general: the ones this seat may not take.
var _taken: Dictionary = {}
## The commander currently previewed (not yet confirmed) for the seat.
var _current: CommanderType
var _faction_index := 0

var _card: CommanderCard
var _title: Label
var _chip: PanelContainer
var _chip_label: Label
var _tab_buttons: Array[Button] = []
var _mini_frame: ScrollContainer
var _mini_buttons: Array[Button] = []
var _mini_marks: Array[ColorRect] = []
var _summary_label: Label
var _confirm_button: Button
var _back_button: Button
var _no_co_button: Button
var _random_button: Button


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
	_random_pool.clear()
	for commander in _db.all():
		if commander.id == CommanderType.NEUTRAL_ID:
			continue
		var key := CommanderVisuals.key_for_faction(commander.faction)
		if _by_faction.has(key):
			_by_faction[key].append(commander)
		_random_pool.append(commander)


## Opens the page for one seat, browsing to the general it holds now. `taken` is
## every other seat's general, seat-keyed, so a portrait another army already has
## greys and names that seat. No Commander opens on the first faction nobody else
## wears, so Enter straight through fields a general rather than nobody.
func begin_seat(seat: int, current: StringName, taken: Dictionary, is_cpu: bool) -> void:
	_seat = seat
	_is_cpu = is_cpu
	_taken = taken.duplicate()
	show()
	if CommanderPicks.is_general(current) and _db.has(current):
		_focus_commander(current)
	else:
		_set_faction(_default_faction())
		_grab_first_mini()


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


## What a capture of this page measures itself against: the title, the seat
## chip, and every action. The setup panel behind this one has had such a gate
## since COM-5 — a page that renders a perfectly good picture with a control off
## the right edge is exactly what a frame check is for.
func chrome() -> Dictionary[String, Control]:
	return {
		"the select page title": _title,
		"seat chip": _chip,
		"No Commander": _no_co_button,
		"Random": _random_button,
		"Back": _back_button,
		"Confirm Pick": _confirm_button,
	}


# --- build -------------------------------------------------------------------


func _build() -> void:
	UiKit.page_veil(self)
	var main := UiKit.page_body(self, 6)

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
	# READING_WIDTH the bar appears for the two longest cards and for nobody else,
	# so the scroll is the roster's exception rather than the page's shape.
	var card_frame := UiKit.vscroll()
	body.add_child(card_frame)

	_card = CommanderCard.new()
	_card.custom_minimum_size.x = CommanderCard.READING_WIDTH
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card_frame.add_child(_card)

	body.add_child(_build_right_column())

	# The control legend in Silkscreen — a key-hint badge is the textbook home for
	# the design system's stat face, and it brings the second font onto the page.
	main.add_child(
		UiKit.key_legend("ARROWS / TAB  BROWSE      ENTER  CONFIRM      ESC  BACK      MOUSE OK")
	)


func _build_topbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)

	_title = UiKit.page_title("SELECT COMMANDER")
	# Read from the left: this one heads a bar it shares with the seat chip
	# rather than standing over the page on its own.
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_title)

	# Which seat is being picked for, in the livery the preview would give it.
	_chip = PanelContainer.new()
	_chip_label = _small_label(UiTheme.SIZE_BODY)
	_chip.add_child(UiKit.pad(_chip_label, 7, 3))
	bar.add_child(_chip)
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
		tab.add_theme_font_size_override("font_size", UiTheme.SIZE_BUTTON)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.focus_entered.connect(_set_faction.bind(i))
		tab.pressed.connect(_focus_faction.bind(i))
		tabs.add_child(tab)
		_tab_buttons.append(tab)
	col.add_child(tabs)

	# The cut-off tile and the always-shown bar are the whole scroll cue, and why
	# there are no arrows is in `.claude/rules/presentation.md` (COM-280).
	_mini_frame = ScrollContainer.new()
	_mini_frame.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_mini_frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_mini_frame.follow_focus = true
	_mini_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_mini_frame)

	var mini_row := HBoxContainer.new()
	mini_row.name = "MiniRow"
	mini_row.add_theme_constant_override("separation", 6)
	_mini_frame.add_child(mini_row)

	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", UiTheme.flat(_INACTIVE))
	summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary_label = _small_label(UiTheme.SIZE_BODY)
	_summary_label.add_theme_color_override("font_color", _MUTED)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_child(UiKit.pad(_summary_label, 8, 6))
	col.add_child(summary)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_no_co_button = _action_button("No Commander")
	# Selects, never locks: No Commander is confirmed like every other pick (COM-7).
	# It acts on the press alone, as the map picker's Random does — Tab crosses it
	# on the way to Confirm Pick, and a pick that changed on that pass was lost.
	_no_co_button.pressed.connect(_preview_neutral)
	actions.add_child(_no_co_button)
	_random_button = _action_button("Random")
	# Same shape: a press rolls, a second press re-rolls, and focus alone does nothing.
	_random_button.pressed.connect(_preview_random)
	actions.add_child(_random_button)
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
	UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY)
	return button


# --- roster navigation -------------------------------------------------------


## Switches the active faction and previews its first member still free. Does not
## move focus, so arrowing Left/Right across the tab row browses factions cleanly.
##
## A faction whose every general is already commanding somebody previews No
## Commander: the card has to show what confirming would lock, and the members
## drawn beside it are all dead.
func _set_faction(index: int) -> void:
	_show_faction(index)
	var free := _free_members()
	if free.is_empty():
		_preview_neutral()
		return
	_preview(free[0])


## The tab a seat with no general opens on: the first faction, in listing order,
## that no other seat already commands, so confirming straight through fields
## different armies rather than every seat on the first tab. Every faction holds
## more generals than a board has seats, so a faction nobody wears has one free.
func _default_faction() -> int:
	var worn: Dictionary[StringName, bool] = {}
	for seat: int in _taken:
		if CommanderPicks.is_general(_taken[seat]):
			worn[CommanderVisuals.key_for_faction(_db.by_id(_taken[seat]).faction)] = true
	for i in _faction_keys.size():
		if not worn.has(_faction_keys[i]):
			return i
	return 0


## The faction's members no other seat is already commanding, in roster order.
func _free_members() -> Array[CommanderType]:
	var free: Array[CommanderType] = []
	for commander in _members():
		if _free_to_take(commander.id):
			free.append(commander)
	return free


## Whether the seat may command `id` — the one rule, asked of `CommanderPicks`
## rather than restated here.
func _free_to_take(id: StringName) -> bool:
	return CommanderPicks.available(_taken, _seat, id)


## Opens a faction's tab and roster without choosing anybody from it — the half of
## `_set_faction` a caller that already knows which member it wants needs, so the
## drawn card is previewed once instead of after the first member flashes in it.
func _show_faction(index: int) -> void:
	_faction_index = index
	for i in _tab_buttons.size():
		_style_tab(_tab_buttons[i], i == index)
	_rebuild_minis()


## A mouse click on a tab switches faction and drops focus onto the first peer,
## so the click lands somewhere sensible for the keyboard to continue from.
func _focus_faction(index: int) -> void:
	_set_faction(index)
	_grab_first_mini()


func _members() -> Array[CommanderType]:
	return _by_faction.get(_faction_keys[_faction_index], [] as Array[CommanderType])


## Where a general stands in the row on show, or -1 when this faction's row does
## not hold them — neutral never does, and nor does a general of another faction.
## The walk stops at the shorter of the two, so a row asked for before it is
## built answers -1 rather than reaching past its buttons.
func _tile_index_for(id: StringName) -> int:
	var members := _members()
	for i in mini(members.size(), _mini_buttons.size()):
		if members[i].id == id:
			return i
	return -1


## Puts the gold mark on one tile and takes it off the rest; -1 clears the row,
## which is what previewing No Commander leaves behind.
func _mark_tile(index: int) -> void:
	for i in _mini_marks.size():
		_mini_marks[i].visible = i == index


## Deferred: freshly-created buttons are not in the focus system until the frame
## settles, so an immediate grab_focus is a no-op and the viewport falls back to
## focusing the first tab. Deferring lands focus on the portrait, as intended.
func _grab(button: Control) -> void:
	if button != null:
		button.grab_focus.call_deferred()


## Lands focus on the first portrait this seat may still take. A faction with
## none left hands focus to No Commander instead of to a dead button, so the
## keyboard always has somewhere to be.
func _grab_first_mini() -> void:
	for button in _mini_buttons:
		if not button.disabled:
			_grab(button)
			return
	_grab(_no_co_button)


func _rebuild_minis() -> void:
	var row := _mini_buttons[0].get_parent() if not _mini_buttons.is_empty() else _find_mini_row()
	for button in _mini_buttons:
		# Deferred: a mini can be the viewport's focus owner when a tab or a
		# Random press rebuilds the row. remove_child leaves the tree
		# synchronously (so the row's children below never see a corpse), but
		# freeing itself is deferred so the focus owner outlives the handler.
		row.remove_child(button)
		button.queue_free()
	_mini_buttons.clear()
	_mini_marks.clear()
	for commander: CommanderType in _members():
		var mini := _make_mini(commander, row)
		_mini_buttons.append(mini)
	_reveal_previewed.call_deferred()


## The row itself, inside the frame that scrolls it — one child, so the cast is
## the whole of the question.
func _find_mini_row() -> HBoxContainer:
	return _mini_frame.get_child(0) as HBoxContainer


## The height the name band reserves: its lines at the body size, solid — the
## caption zeroes `line_spacing`, so a name two words tall reads as one block and
## a tile's height is known before any label has been laid out.
func _name_text_height() -> float:
	return _NAME_LINES * UiTheme.display().get_height(UiTheme.SIZE_BODY)


## A roster tile: its face field and the name band under it.
func _mini_height() -> float:
	return MINI_FACE.y + _name_text_height() + 2 * _NAME_PAD


func _make_mini(commander: CommanderType, row: HBoxContainer) -> Button:
	var theme := CommanderVisuals.theme_for(commander)
	var button := Button.new()
	button.custom_minimum_size = Vector2(MINI_FACE.x, _mini_height())
	button.clip_contents = true
	button.add_theme_stylebox_override("normal", _hard(theme.color_dark, 2))
	button.add_theme_stylebox_override("hover", _hard(theme.color, 2))
	button.add_theme_stylebox_override("focus", _hard(_GOLD, 2))
	button.add_theme_stylebox_override("pressed", _hard(_GOLD, 2))
	row.add_child(button)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 0)
	button.add_child(content)

	# The stage states no size of its own — it is the tile's width, and what is
	# left over under the name band — so the kit measures the field it is handed a
	# frame late. That field holds a whole bust, which is what the tile's fixed
	# width is for.
	var stage := UiKit.commander_bust(commander, Vector2.ZERO, theme.color)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(stage)

	var name_label := _small_label(UiTheme.SIZE_BODY)
	name_label.text = commander.display_name
	name_label.add_theme_color_override("font_color", theme.ink)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_constant_override("line_spacing", 0)
	name_label.custom_minimum_size.y = _name_text_height()
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var name_wrap := PanelContainer.new()
	name_wrap.add_theme_stylebox_override("panel", UiTheme.flat(theme.color_dark))
	name_wrap.add_child(UiKit.pad(name_label, 2, _NAME_PAD))
	content.add_child(name_wrap)
	UiTheme.make_decoration(content)

	var mark := ColorRect.new()
	mark.color = _GOLD
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
	_mark_taken(button, commander)
	return button


## Scrolls the row until the previewed general's tile is whole. Called once per
## rebuild — opening the page, a tab and Random all rebuild the row — so the row
## opens on the seat's pick rather than on wherever the previous faction left it.
## Random is why the rebuild owns it rather than the focus: the draw previews a
## general nothing focused, and may be the sixth of a faction the row shows three
## of. A tile the player *does* focus, by key or by
## click, is `follow_focus`'s to bring into view.
##
## Queued rather than run, because a rebuilt row has no sizes until the frame
## settles and `ensure_control_visible` on an unplaced tile scrolls to nothing.
## Which tile is resolved when the call runs rather than when it was queued: the
## preview that names it lands after the rebuild, and two rebuilds can share one
## frame, so the tile named at queue time may be out of the row by then, which
## `ensure_control_visible` refuses out loud.
func _reveal_previewed() -> void:
	if _current == null:
		return
	var index := _tile_index_for(_current.id)
	if index >= 0:
		_mini_frame.ensure_control_visible(_mini_buttons[index])


## Greys the portrait of a general another seat already commands, and says which
## seat holds them: a dead control with no reason is the affordance this menu has
## been burned by once (COM-13). Disabled rather than absent, so the roster row is
## the same row at the same widths for every seat.
func _mark_taken(button: Button, commander: CommanderType) -> void:
	var seat := CommanderPicks.holder(_taken, commander.id, _seat)
	if seat == 0:
		return
	button.disabled = true
	button.modulate = _TAKEN_TINT
	Tooltip.attach(
		button, commander.display_name, "Already commanding seat %d" % seat, Tooltip.Side.BOTTOM
	)


func _preview(commander: CommanderType) -> void:
	_current = commander
	_card.bind(commander)
	_mark_tile(_tile_index_for(commander.id))
	_refresh_summary()
	_refresh_chip()


func _preview_neutral() -> void:
	_preview(CommanderType.neutral())


## Draws one commander from the full roster, any faction, and presents it: the
## tab, the roster row and the marked card all land on the draw, so the page says
## the same thing the card and the summary do (COM-227). The draw itself is
## unchanged — uniform over every faction, and a second press re-rolls.
##
## Focus stays on Random rather than following the draw onto its portrait, which
## is what keeps that re-roll one keystroke away.
##
## The draw is without replacement: a general another seat commands is out of
## the pool, so the roll can never hand this seat somebody already on the field.
func _preview_random() -> void:
	var pool := _free_pool()
	if pool.is_empty():
		_preview_neutral()
		return
	var drawn: CommanderType = pool[randi() % pool.size()]
	var index := _faction_keys.find(CommanderVisuals.key_for_faction(drawn.faction))
	if index >= 0:
		_show_faction(index)
	_preview(drawn)


## Every general still free for the seat in hand, flat, for Random to draw from.
func _free_pool() -> Array[CommanderType]:
	var free: Array[CommanderType] = []
	for commander in _random_pool:
		if _free_to_take(commander.id):
			free.append(commander)
	return free


# --- confirm / back ----------------------------------------------------------


## Hands the seat's one pick back, `{seat: id}`, and closes.
func _confirm() -> void:
	if _current == null or not _free_to_take(_current.id):
		return
	hide()
	confirmed.emit({_seat: _current.id})


func _back() -> void:
	hide()
	cancelled.emit()


## The page's two global keys, and the footer has always promised both: Esc backs
## out from anywhere, Enter confirms the browsed pick from anywhere (COM-7).
##
## Enter is read here rather than left to the focused control because browsing
## already *is* selecting — every tab and portrait previews on focus_entered, so
## whatever the player is looking at is the pick, and the focused control's own
## ui_accept would merely re-run what focus already did. The three action buttons
## other than Confirm are the exception: they act only when pressed, so Enter on
## one presses it — Back goes back, No Commander and Random change the pick.
##
## `_input`, not `_shortcut_input`, and the release is swallowed with the press.
## Both halves are load-bearing: shortcuts are walked after the GUI, and a Button
## activates on the *release*, so a press-only handler sitting behind the GUI
## confirms and then lets the focused button fire too — on Confirm Pick that
## once locked two seats with one keystroke.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_back()
		accept_event()
	elif event.is_action("ui_accept") and _focus_owner() not in _pressed_only():
		if event.is_action_pressed("ui_accept"):
			_confirm()
		accept_event()


func _pressed_only() -> Array[Control]:
	return [_back_button, _no_co_button, _random_button]


func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner()


## Moves the tab/preview/focus to a specific commander id — the seat's general as
## the page opens. Neutral falls through to the first faction's first member.
func _focus_commander(id: StringName) -> void:
	var commander := _db.by_id(id)
	if commander.id == CommanderType.NEUTRAL_ID:
		_set_faction(0)
		_grab_first_mini()
		return
	var key := CommanderVisuals.key_for_faction(commander.faction)
	var index := _faction_keys.find(key)
	_set_faction(index if index >= 0 else 0)
	var tile := _tile_index_for(id)
	if tile >= 0 and not _mini_buttons[tile].disabled:
		_grab(_mini_buttons[tile])
		return
	_grab_first_mini()


# --- chrome refresh ----------------------------------------------------------


## The title chip: which seat this is and who plays it, filled in the livery the
## previewed general would give it, grey under No Commander.
func _refresh_chip() -> void:
	var who := "CPU" if _is_cpu else "Human"
	var general := _current != null and CommanderPicks.is_general(_current.id)
	var theme := CommanderVisuals.theme_for(_current) if general else null
	_chip.add_theme_stylebox_override(
		"panel", UiTheme.flat(theme.color if theme != null else _INACTIVE)
	)
	_chip_label.add_theme_color_override("font_color", theme.ink if theme != null else _MUTED)
	_chip_label.text = "P%d · %s" % [_seat, who]


func _refresh_summary() -> void:
	var text := "Seat %d — browse a faction, then Confirm." % _seat
	if _current != null:
		var theme := CommanderVisuals.theme_for(_current)
		text = "Seat %d · %s\nSelected: %s." % [_seat, theme.display, _current.display_name]
	_summary_label.text = text


func _style_tab(tab: Button, active: bool) -> void:
	var theme := CommanderVisuals.theme_for_key(_faction_keys[_tab_buttons.find(tab)])
	tab.add_theme_stylebox_override("normal", _hard(theme.color if active else _INACTIVE, 2))
	tab.add_theme_stylebox_override("hover", _hard(theme.color_light if active else theme.color, 2))
	tab.add_theme_stylebox_override("focus", _hard(_GOLD, 2))
	tab.add_theme_stylebox_override("pressed", _hard(theme.color, 2))
	tab.add_theme_color_override("font_color", Color.WHITE if active else _MUTED)


# --- style helpers -----------------------------------------------------------


## Every caller sets text and colour itself right after, so the placeholders
## below never reach a frame; only font and size are this builder's own.
## Reset to top alignment because `hud_label` centres, and the summary box
## (unlike a mini or the chip) is taller than its text.
func _small_label(size: int) -> Label:
	var label := UiTheme.hud_label("", size, UiTheme.INK, true)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return label


func _hard(border: Color, width: int) -> StyleBoxFlat:
	# The signature hard offset shadow, from the one authority (plan MN3).
	var box := UiTheme.bordered(_INACTIVE, border, width, true)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box
