class_name SkirmishSetup
extends Control
## Setting up a skirmish, in two steps: which map, then who plays and on what rules.
## Start on the second step starts the match; nothing comes after it. Back keeps
## every choice, and a choice is remembered as it is made (`MenuSetupMemory`).
##
## The seats are dealt as Players opens rather than as a board is pressed: a seat a
## smaller board has no room for is dropped, so merely browsing the shelf would cost
## the table in hand.
##
## Two steps rather than one surface because the seats and the map could not share a
## 640x360 frame: under a four-seat strip the shelf had 104px of height. Speed and
## fog ride on Players because two controls do not earn a screen of their own.
##
## A step's Esc is heard here, ahead of `MenuSettingsPage`, which is the menu's first
## child and so hears unhandled input last; a page opened over a step hides the menu
## root, which silences this.

## Back on the map step: the player left the skirmish for the title screen.
signal closed
signal start_requested
signal general_requested(seat: int, chip: Control)

enum Step { MAP, PLAYERS }

const _NAV_W := 92
const _STEP_WORDS := "STEP %d OF 2"
const _COLUMN_GAP := 10
const _SPEED_TIP := "How fast moves and battles play out"
const _SPEED_HELP := "Pacing only. Outcomes never change."
const _FOG_HELP := "Hide the board beyond your units' sight."

var map_picker: MapPicker
var seat_strip := SeatStrip.new()
var fog_on := false

var _difficulties: Array[Difficulty] = []
var _remembered: Dictionary = {}
var _speed_tiers: Array[GameSpeed] = GameSpeed.ordered()
var _step := Step.MAP
var _map_page: Control
var _players_page: Control
var _next: Button
var _start: Button
var _change_map: Button
## Why Start is refusing, beside the button. A greyed control with no reason is the
## affordance this menu was burned by once already (COM-19).
var _refusal: Label
var _board := MapPreview.new()


func _init(picker: MapPicker, difficulties: Array[Difficulty], remembered: Dictionary) -> void:
	map_picker = picker
	_difficulties = difficulties
	_remembered = remembered
	fog_on = MenuSetupMemory.fog(remembered)
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	if _difficulties.is_empty():
		push_error("skirmish setup: no difficulty tiers found in %s" % DifficultyDB.DIFFICULTY_DIR)
	seat_strip.configure(_difficulties)
	_map_page = _build_map_page()
	_players_page = _build_players_page()
	add_child(_map_page)
	add_child(_players_page)
	map_picker.reserve_caption()
	map_picker.map_selected.connect(func(_index: int) -> void: _remember())
	map_picker.map_chosen.connect(func() -> void: _next.grab_focus())
	seat_strip.changed.connect(_refresh_table)
	seat_strip.general_requested.connect(general_requested.emit)
	_deal_seats()
	seat_strip.seat_table(MenuSetupMemory.table(_remembered))
	seat_strip.seat_generals(MenuSetupMemory.generals(_remembered, CommanderDB.load_default()))


## Shows a step and hands focus to the way forward, so Enter walks the whole setup.
func open_step(step: Step) -> void:
	_step = step
	_map_page.visible = step == Step.MAP
	_players_page.visible = step == Step.PLAYERS
	if step == Step.PLAYERS:
		_deal_seats()
		# A dead Start is nothing to press Enter at (SK-23); its reason is beside it.
		(_change_map if _start.disabled else _start).grab_focus()
	else:
		_next.grab_focus()
		await map_picker.reveal_selection()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"cancel"):
		get_viewport().set_input_as_handled()
		_back()


func _back() -> void:
	if _step == Step.PLAYERS:
		open_step(Step.MAP)
	else:
		closed.emit()


## What a capture measures itself against on the step in hand.
func chrome() -> Dictionary[String, Control]:
	if _step == Step.MAP:
		return {
			"the map step": _map_page,
			"selected map facts": map_picker.caption(),
			"Next": _next,
		}
	var named: Dictionary[String, Control] = {
		"the players step": _players_page,
		"Start": _start,
	}
	# Every seat by name: a control the gate does not name can silently vanish, which
	# is how the strip came to be photographed as bare panel.
	var seats := seat_strip.rows()
	for i in seats.size():
		named["seat %d" % (i + 1)] = seats[i]
	return named


# --- the two pages -----------------------------------------------------------


func _build_map_page() -> Control:
	map_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_next = UiKit.action_button("Next ▸", "", UiTheme.ButtonVariant.PRIMARY, _primary(), _NAV_W)
	_next.pressed.connect(func() -> void: open_step(Step.PLAYERS))
	return _page("Choose a map", Step.MAP, map_picker, "Back", _next)


func _build_players_page() -> Control:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", _COLUMN_GAP)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_build_rules_column())
	seat_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(seat_strip)

	_start = UiKit.action_button(
		"Start Match", "", UiTheme.ButtonVariant.PRIMARY, _primary(), _NAV_W
	)
	_start.pressed.connect(start_requested.emit)
	return _page("Players", Step.PLAYERS, body, "Change map", _start)


## The board this match is on, then the match's two rules. Their help is printed
## rather than hover-only (U-15): a touch build has no hover.
func _build_rules_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size.x = MapPreview.WIDTH
	col.add_child(_board)
	col.add_child(UiKit.rule())
	col.add_child(_build_speed())
	col.add_child(_help(_SPEED_HELP))
	col.add_child(
		UiKit.toggle("Fog of war", fog_on, _FOG_HELP, "Off shows the whole map", _on_fog_toggled)
	)
	col.add_child(_help(_FOG_HELP))
	return col


## No Difficulty segment: how well the computer plays is per seat (COM-225), and two
## controls writing one fact is the drift a single authority exists to prevent.
func _build_speed() -> Control:
	var labels := PackedStringArray()
	var selected := 0
	for i in _speed_tiers.size():
		labels.append(_speed_tiers[i].display_name)
		if _speed_tiers[i].id == Settings.speed.id:
			selected = i
	var speed := UiKit.segment(
		"Speed",
		labels,
		selected,
		UiTheme.CONTROL_ACCENT,
		_SPEED_TIP,
		_SPEED_HELP,
		_on_speed_selected
	)
	# A segment clips rather than sizing to its label, so the run states its width.
	speed.custom_minimum_size = Vector2(UiKit.segment_min_width(labels), 0)
	return speed


func _help(words: String) -> Label:
	var label := UiKit.help_label(words)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A step's frame: its title and place in the walk, its body, and the two ways out.
func _page(title: String, step: Step, body: Control, back_text: String, forward: Button) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box())
	panel.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, UiTheme.GAP
	)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	col.add_child(_title_bar(title, step))

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var padded := UiKit.pad(inner, 8, 7)
	padded.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(padded)
	inner.add_child(body)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", UiTheme.GAP)
	var back := UiKit.action_button(back_text, "", UiTheme.ButtonVariant.SECONDARY, null, _NAV_W)
	back.pressed.connect(_back)
	footer.add_child(UiKit.touchable(back))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	if step == Step.PLAYERS:
		_change_map = back
		_refusal = UiKit.help_label("")
		_refusal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		footer.add_child(_refusal)
	footer.add_child(UiKit.touchable(forward))
	inner.add_child(footer)
	return panel


func _title_bar(title: String, step: Step) -> Control:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiTheme.header_box())
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title.to_upper()
	label.add_theme_font_override("font", UiTheme.display(true))
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_TITLE)
	label.add_theme_color_override("font_color", UiTheme.WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var place := Label.new()
	place.text = _STEP_WORDS % (step + 1)
	place.add_theme_font_override("font", UiTheme.stat())
	place.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	place.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	place.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(place)
	header.add_child(row)
	return header


func _primary() -> CommanderVisuals.FactionTheme:
	return UiTheme.menu_identity().theme(1)


# --- state -------------------------------------------------------------------


## How many seats there are is the board's answer (four-players D1), so the strip is
## re-dealt from the picker's selection rather than from anything the player set.
func _deal_seats() -> void:
	var map := map_picker.selected_map()
	if map == null:
		return
	seat_strip.set_roster(map.player_count())
	_board.show_board(map)
	_refresh_table()


func _refresh_table() -> void:
	_start.disabled = not seat_strip.valid()
	_refusal.text = seat_strip.refusal()
	_remember()


## Speed is the odd one out: a device preference, not a match option, so a tap writes
## Settings.set_speed immediately and never rides MatchConfig (game-speed plan D1).
func _on_speed_selected(index: int) -> void:
	if index >= 0 and index < _speed_tiers.size():
		Settings.set_speed(_speed_tiers[index].id)


func _on_fog_toggled(pressed: bool) -> void:
	fog_on = pressed
	_remember()


func _remember() -> void:
	MenuSetupMemory.remember(map_picker.selected_map(), fog_on, seat_strip)
