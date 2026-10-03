class_name MainMenu
extends Control
## Main menu: pick a map, seat the armies and their generals, set the rules, then
## hand off to the battle scene by staging one MatchRequest.
##
## The screen wears the Grid Commander Design System (menu-revamp plan): a header
## with the wordmark, a cream Match Setup panel beside an action stack, all drawn
## from UiTheme's styleboxes and fonts. Built in code rather than a .tscn, like
## CommanderSelectPanel and CommanderCard — the layout is regular and data-driven,
## and code-built styleboxes are the one form this repo can review in a diff (D1).
##
## One surface: "Start" launches with the strip's picks as they stand. A seat
## row's general chip opens the CommanderSelectPanel for that one seat, shown
## *over* this menu so the setup survives it either way.
## "Continue" bypasses selection — a saved match restores its own commanders. It
## is disabled, not hidden, when there is nothing to resume (plan section 2), and
## it names what it would resume on the line beneath it: "Day 4 · Scrimmage".
## Disabled rather than hidden is also what keeps the two layouts the same height:
## a save's presence may never change the layout budget (UX-recovery D2), which is
## what `--demo=menu_with_save` / `--demo=menu_no_save` photograph and what
## MenuCaptureDriver refuses to let regress.

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const EDITOR_SCENE := "res://scenes/editor/map_editor.tscn"
const ICON_PATH := "res://assets/icon.png"
## Faction-silent by faction-identity D5: no "Red vs Blue" reaches a player screen.
const TAGLINE := "TURN-BASED TACTICS · PICK YOUR GROUND"
## The space between two groups of rows inside the Match Setup panel. Named so a
## row group built elsewhere can match it: the seat strip sets its own separation
## (SeatStrip._rebuild) and is tighter than this, which reads as a grouping the
## panel does not have. 5 until COM-254 grew every caption in it by two pixels.
const PANEL_ROW_GAP := 4
## Air under the rail's last line: the setup panel runs to the frame's foot, and
## Quit pinned flush with it sat on the screen's last pixels (SK-30).
const FOOTER_AIR := 6

## Everything the commander page hides behind itself when it opens, so no focus or
## click leaks to the buttons underneath.
var _menu_root: Control

## The map picker (MN2), the one owner of the roster and of which board is in
## hand: the panel hosts its title-bar label and re-deals the seats when it says
## the selection changed.
var _map_picker: MapPicker
var _fog_on := false
## The whole centered stack — header, setup panel, action column. Kept because it
## is the one rect that answers "does the menu fit?": the CenterContainer around
## it hands a too-tall column a negative offset, so an overflow runs off *both*
## ends at once and no single child is a reliable witness to it.
var _column: VBoxContainer
var _start_button: Button
## Why Start is refusing, under the button. A greyed control with no reason is the
## affordance this menu was burned by once already (COM-19).
var _seat_refusal: Label
## Who sits where and who stands with whom (plan D6). The one authority on both,
## asked at launch rather than mirrored into menu state.
var _seat_strip: SeatStrip
## The Continue row — the button, its caption, its tip and the press that opens
## the save — kept whole in its own collaborator. It is handed what the slot
## holds; where that comes from stays this page's decision.
var _continue: ContinueSlot
var _campaign_button: Button
var _replay_button: Button
var _editor_button: Button
var _quit_button: Button
var _press_start: Label
## The page's scenery — the drifting board and the blinking PRESS START — and the
## one switch that holds it, so the Menu motion row answers without rebuilding
## the screen.
var _motion := MenuMotion.new()
## True while this boot is posing a still frame for a capture, which holds the
## motion whatever the player prefers — see `_apply_menu_motion`.
var _posed := false

var _select_panel: CommanderSelectPanel
## The general chip that opened the commander page, for focus to return to.
var _general_chip: Control
var _replay_panel: ReplayPickerPanel
## Pick a war, pick a mission, deploy — the menu's campaign navigation, kept
## whole in its own collaborator because it is a different question from the
## board-and-fog setup this page is otherwise about.
var _campaign_flow: MenuCampaignFlow

## The database the picker parses its roster with.
var _terrain_db: TerrainDB
## The difficulty tiers in menu order, gentlest first — handed to the seat strip,
## which is where a tier is chosen (COM-225).
var _difficulties: Array[Difficulty] = []
var _speed_tiers: Array[GameSpeed] = []
## Dev-only, built on every boot because it is what reads the command line; it
## poses nothing and gates nothing on an ordinary run.
var _capture_driver: MenuCaptureDriver


func _ready() -> void:
	_capture_driver = MenuCaptureDriver.new(self)
	# Asked of the driver, not ScreenshotUtil: a batched menu scenario
	# (COM-118) carries no --screenshot= of its own.
	var shot_path := _capture_driver.shot_path()
	if shot_path != "":
		# The battle scene's rule, and for the same reason: a capture must not show
		# — or depend on — the preference of the machine that took it. The menu's
		# tier is its own (see GameSpeed.MENU_CAPTURE_ID); the pin's only observable
		# effect here is the Speed segment's highlight and the blinking PRESS START,
		# which is pinned solid below.
		Settings.pin(GameSpeed.MENU_CAPTURE_ID)
	if _capture_driver.rejected():
		get_tree().quit(1)
		return

	Music.play(&"parade")

	_terrain_db = TerrainDB.load_default()
	# Held before the panel's first deal remembers over it; a capture's pin has
	# already emptied it, so a photographed menu leads with the tutorial board.
	var remembered := Settings.match_setup
	# Built and stocked before the page is drawn: the backdrop bakes the fullest
	# board in the roster, and the setup panel's title bar parents its header label.
	_map_picker = MapPicker.new()
	_map_picker.configure(_terrain_db, MenuSetupMemory.map_path(remembered))
	_fog_on = MenuSetupMemory.fog(remembered)
	_difficulties = DifficultyDB.load_default().all()
	_speed_tiers = GameSpeed.ordered()
	_posed = shot_path != ""
	_build()

	_select_panel = CommanderSelectPanel.new()
	add_child(_select_panel)
	_select_panel.confirmed.connect(_on_general_picked)
	_select_panel.cancelled.connect(_on_general_picked.bind({}))

	_replay_panel = ReplayPickerPanel.new()
	add_child(_replay_panel)
	_replay_panel.picked.connect(_on_replay_picked)
	_replay_panel.cancelled.connect(_on_replay_cancelled)
	_campaign_flow = MenuCampaignFlow.new(
		self,
		_menu_root,
		func() -> void: _campaign_button.grab_focus(),
		func() -> void: get_tree().change_scene_to_file(BATTLE_SCENE)
	)

	# The disk, or a posed slot when a capture owns it, so a photographed menu never
	# depends on what this machine has saved.
	if _capture_driver.poses_slot():
		_continue.refresh(_capture_driver.posed_slot(_map_picker.maps()))
	else:
		_continue.refresh_from_disk()
	_start_button.pressed.connect(
		func() -> void:
			_start(_seat_strip.ai_teams(), false, _seat_strip.generals.over(_seat_strip.seats()))
	)
	_seat_strip.general_requested.connect(_open_general)
	Settings.menu_animations_changed.connect(_apply_menu_motion)
	# The strip is the only writer of who plays what, so the rule that a table with
	# no computer at it has no difficulty to tune follows it rather than a mode
	# flag — and follows it the moment a seat changes, not only once Start is
	# pressed, so the panel can never disagree with the match in hand.
	_seat_strip.changed.connect(_refresh_seats)
	_map_picker.map_selected.connect(_on_map_selected)
	# The map picker chooses a board while it is being built, before the strip
	# exists, so the selection is re-read once it does — the roster is the board's
	# answer and the strip is downstream of it.
	_deal_seats_for_map()
	_seat_strip.seat_table(MenuSetupMemory.table(remembered))
	_seat_strip.seat_generals(MenuSetupMemory.generals(remembered, CommanderDB.load_default()))
	_campaign_button.pressed.connect(_campaign_flow.open)
	_replay_button.pressed.connect(_open_replays)
	_editor_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(EDITOR_SCENE))
	if _capture_driver.poses(MenuCaptureDriver.DEMO_SETUP_CONTEXT):
		# The frame that photographs the dimmed Difficulty: a table of nothing but
		# people has no computer to tune. Posed by seating everyone rather than by
		# focusing a mode button, because the seats are the rule's subject now.
		for seat in _seat_strip.seat_count():
			_seat_strip.set_human(seat, true)
		_refresh_seats()
	_start_button.grab_focus()
	# Coming back from a mission lands on the debrief and the hub, not on the menu:
	# the campaign is still the thing being played. The session is cleared as it is
	# read, so a later Quit-to-menu cannot reopen a campaign nobody is in. Last,
	# after the Start button's grab, so the debrief's own button keeps the focus.
	if CampaignSession.active():
		_campaign_flow.resume()

	await _pose_seats()

	# The replays page photographs a posed list over a hidden menu, exactly as the
	# selection page below does, so it hands in its own chrome for the same reason:
	# the menu's geometry is not what that picture claims.
	if _capture_driver.poses(MenuCaptureDriver.DEMO_REPLAYS):
		_open_replays()
		await _capture_driver.capture(shot_path, _replay_panel.chrome)
		return

	# Both campaign pages photograph over a hidden menu for the replays page's
	# reason, and the hub is posed on a *fresh* profile so the picture does not
	# depend on how far the machine that took it happens to have played.
	# All three campaign pages pose the same way, so the flow that owns them owns
	# that too: it answers with the chrome to measure, or nothing when this run is
	# not posing one of its pages.
	var campaign_chrome := _campaign_flow.pose(_capture_driver)
	if campaign_chrome.is_valid():
		await _capture_driver.capture(shot_path, campaign_chrome)
		return

	# Dev captures of the commander page, opened for seat 1 — which general it
	# browses to is the driver's reading of `--co-select`, like every other
	# capture flag; what that means on screen is this menu's own flow.
	if _capture_driver.poses_selection():
		_open_general(1)
		var browsed := _capture_driver.selection_commander()
		if browsed != &"":
			_select_panel.debug_preview(browsed)
	if shot_path != "":
		# The select page measures itself against its own chrome, not the menu's: it
		# is the picture being taken, and the menu behind it is hidden.
		var chrome := _select_panel.chrome if _capture_driver.poses_selection() else _chrome
		await _capture_driver.capture(shot_path, chrome)


## Dev captures only: selects the board and applies the grouping the driver read
## off the command line, so the seat strip can be photographed at more seats than
## the default board deals. Not on any play path — a run that asks for none of
## them does nothing here.
func _pose_seats() -> void:
	# `menu_four_seats` asks for a board by mode rather than by name: the picker's
	# `· NP` mark and a strip of more than two rows, which every other menu
	# scenario's tutorial board says neither of.
	if _capture_driver.poses(MenuCaptureDriver.DEMO_FOUR_SEATS):
		await _map_picker.show_map(_capture_driver.four_seat_map(_map_picker.maps()))
	var wanted := _capture_driver.menu_map_index(_map_picker.maps(), _map_picker.selected_map())
	if wanted >= 0:
		await _map_picker.show_map(wanted)
	var preset := _capture_driver.menu_preset()
	if preset >= 0:
		_seat_strip.apply_preset_at(preset)
		_refresh_seats()


# --- layout ------------------------------------------------------------------


## Draws the whole screen. Both moving things on it — the drifting backdrop and
## the blinking PRESS START — are built either way and then held or let go by
## `_apply_menu_motion`, so the Menu motion row takes effect on the press rather
## than on the next boot.
func _build() -> void:
	# The fullest board on the picker's shelf is what drifts behind the page, baked
	# by the thumbnail renderer — so the scenery can never disagree with the picker
	# (plan R2). The picker measures it rather than the menu taking the roster's last
	# entry: a board the player drew is listed after the shipped ones at any size.
	_motion.paint_backdrop(self, MapPicker.fullest(_map_picker.maps()))

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_menu_root = center

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	# The frame's width less a gap each side, stated rather than left to whatever
	# the widest row happens to ask for: the seat rows need every pixel of it.
	column.custom_minimum_size.x = get_viewport_rect().size.x - 2 * UiTheme.GAP
	center.add_child(column)
	_column = column

	column.add_child(_build_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UiTheme.GAP)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(body)
	body.add_child(_build_setup_panel())
	body.add_child(_build_action_stack())
	_map_picker.reserve_caption()
	_apply_menu_motion()


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon_frame := PanelContainer.new()
	var icon_box := UiTheme.bordered(UiTheme.SLATE_800, UiTheme.HARD_BORDER, UiTheme.BORDER, true)
	icon_frame.add_theme_stylebox_override("panel", icon_box)
	var icon := TextureRect.new()
	icon.texture = load(ICON_PATH) if ResourceLoader.exists(ICON_PATH) else null
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(32, 32)
	# IGNORE_SIZE: the 128px launcher icon honours the 32px cell, not its own size.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_frame.add_child(icon)
	row.add_child(icon_frame)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 3)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var wordmark := Label.new()
	wordmark.text = "GRID COMMANDERS"
	wordmark.add_theme_font_override("font", UiTheme.display(true))
	wordmark.add_theme_font_size_override("font_size", UiTheme.SIZE_WORDMARK)
	wordmark.add_theme_color_override("font_color", UiTheme.WHITE)
	# The signature ink offset behind the wordmark (handoff 4px, canvas 2px).
	wordmark.add_theme_color_override("font_shadow_color", UiTheme.HARD_BORDER)
	wordmark.add_theme_constant_override("shadow_offset_x", 2)
	wordmark.add_theme_constant_override("shadow_offset_y", 2)
	titles.add_child(wordmark)

	var tagline := Label.new()
	tagline.text = TAGLINE
	tagline.add_theme_font_override("font", UiTheme.stat())
	tagline.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	tagline.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	titles.add_child(tagline)

	row.add_child(titles)
	row.add_child(ViewChip.for_menu())
	return row


func _build_setup_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box())
	panel.custom_minimum_size = Vector2(UiTheme.CONTENT_W, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	# --- title bar: "Match Setup" + the selected map's name and size ---
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiTheme.header_box())
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "MATCH SETUP"
	title.add_theme_font_override("font", UiTheme.display(true))
	title.add_theme_font_size_override("font_size", UiTheme.SIZE_TITLE)
	title.add_theme_color_override("font_color", UiTheme.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	# The picker's words, in the panel's title bar: the board's name and size are
	# the selection speaking, so the label that sets them is the picker's.
	header_row.add_child(_map_picker.header_label())
	header.add_child(header_row)
	col.add_child(header)

	# --- body ---
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", PANEL_ROW_GAP)
	col.add_child(UiKit.pad(body, 8, 7))

	# The picker takes the panel's slack: choosing a board is what this page is
	# for, and every other row here says its piece in a fixed number of lines.
	_map_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_map_picker)
	body.add_child(_build_seats_row())
	body.add_child(_build_options_row())
	return panel


## The seat strip: who plays each army the board deals, how well the computer
## plays it, who stands with whom and who commands it. Built with this panel's own segment builder
## so a seat row is the same control the speed row is — see SeatStrip, which owns
## the state.
func _build_seats_row() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.add_child(UiKit.section_header("Seats"))
	if _difficulties.is_empty():
		push_error("main menu: no difficulty tiers found in %s" % DifficultyDB.DIFFICULTY_DIR)
	_seat_strip = SeatStrip.new()
	_seat_strip.configure(_difficulties)
	col.add_child(_seat_strip)
	return col


## The match's rules on one line: pacing, then fog. Each control's tooltip carries
## its explanation, so the line gives the map picker its height. Battle
## animations and Menu motion are the device's, not the match's, so they are rows
## of the Settings page (`Settings.menu_page_actions`) rather than options here.
func _build_options_row() -> Control:
	var row := HBoxContainer.new()
	# Wider than the gap inside a toggle: each ON/OFF belongs to the label it follows.
	row.add_theme_constant_override("separation", 2 * UiKit.TOGGLE_GAP)
	row.add_child(_build_speed_col())
	var fog := UiKit.toggle(
		"Fog of war",
		_fog_on,
		"Hide the board beyond your units' sight",
		"Off shows the whole map",
		_on_fog_toggled
	)
	fog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Level with the speed segment's buttons rather than its label above them.
	fog.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(fog)
	return row


func _build_speed_col() -> Control:
	# No Difficulty segment: how well the computer plays is per seat now (COM-225)
	# and the seat strip is the one control that says it. Two controls writing one
	# fact is the drift a single authority exists to prevent.
	var speed_labels := PackedStringArray()
	var speed_selected := 0
	for i in _speed_tiers.size():
		speed_labels.append(_speed_tiers[i].display_name)
		if _speed_tiers[i].id == Settings.speed.id:
			speed_selected = i
	var speed := UiKit.segment(
		"Speed",
		speed_labels,
		speed_selected,
		UiTheme.CONTROL_ACCENT,
		"How fast moves and battles play out",
		"Pacing only · outcomes never change",
		_on_speed_selected
	)
	speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A segment clips rather than sizing to its label, so the tier run states the
	# width it must stand at: an even share of this row set "Instant" as "Instan".
	speed.custom_minimum_size = Vector2(UiKit.segment_min_width(speed_labels), 0)
	return speed


## The rail, read top to bottom: the primary action, the card that resumes a
## match, the quiet ways off this page, then a footer — the blink, and Quit
## pinned last. Grouped rather than evenly spaced, because a
## column of equally-separated rows says nothing about which of them matters.
func _build_action_stack() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.custom_minimum_size = Vector2(UiTheme.ACTION_W, 0)

	var identity := UiTheme.menu_identity()
	# One action where there were two modes: who is playing is the seat strip's to
	# say now, so this button only has to mean "with these seats" (plan D6).
	_start_button = UiKit.action_button(
		"Start", "Match", UiTheme.ButtonVariant.PRIMARY, identity.theme(1)
	)
	col.add_child(_start_button)
	_seat_refusal = UiKit.help_label("")
	_seat_refusal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seat_refusal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_seat_refusal)

	_continue = ContinueSlot.new(
		col,
		func() -> void: _start([] as Array[int], true, {}),
		func(campaign_id: StringName) -> bool: return _campaign_flow.resume_saved(campaign_id)
	)
	col.add_child(_build_secondary_group())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	_press_start = Label.new()
	_press_start.text = ControlHints.chip_for(ControlHints.START_PROMPT)
	_press_start.add_theme_font_override("font", UiTheme.stat())
	_press_start.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	_press_start.add_theme_color_override("font_color", UiTheme.NEUTRAL_DARK)
	_press_start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_press_start)
	_motion.blink(self, _press_start)

	# Pinned last: leaving is not what this page offers; a browser tab cannot leave.
	if not OS.has_feature("web"):
		_quit_button = UiKit.text_link("Quit")
		# A step lighter than a link on the cream panel: this one sits on the backdrop.
		_quit_button.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
		_quit_button.add_theme_color_override("font_hover_color", UiTheme.WHITE)
		col.add_child(_quit_button)
		_quit_button.pressed.connect(get_tree().quit)
	var air := Control.new()
	air.custom_minimum_size = Vector2(0, FOOTER_AIR)
	col.add_child(air)
	return col


## The four ways off this page, tight against one another so they read as one
## group a step below Continue: an authored war, the recordings of matches
## already played, authoring a board — which is the one thing here that is not
## playing the game (COM-263) — and the device's settings (SK-14). Chrome-less,
## because none of them starts the match this page sets up.
func _build_secondary_group() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	_campaign_button = UiKit.action_button("Campaign", "", UiTheme.ButtonVariant.GHOST, null)
	col.add_child(_campaign_button)
	_replay_button = UiKit.action_button("Replays", "", UiTheme.ButtonVariant.GHOST, null)
	col.add_child(_replay_button)
	_editor_button = UiKit.action_button("Map Editor", "", UiTheme.ButtonVariant.GHOST, null)
	col.add_child(_editor_button)
	var settings := UiKit.action_button("Settings", "", UiTheme.ButtonVariant.GHOST, null)
	col.add_child(settings)
	MenuSettingsPage.attach(self, _menu_root, settings)
	return col


# --- small helpers -----------------------------------------------------------


## Whether the page's scenery moves: this boot's capture pose outranks the
## preference, a still frame not being allowed to depend on which machine took it.
func _apply_menu_motion() -> void:
	_motion.set_moving(not _posed and Settings.menu_animations)


# --- match option state ------------------------------------------------------


## Speed is the odd one out: a device preference, not a match option, so a tap
## writes Settings.set_speed immediately and never rides MatchConfig (game-speed
## plan D1). The same setting applies to the next match and to a resumed save.
func _on_speed_selected(index: int) -> void:
	if index >= 0 and index < _speed_tiers.size():
		Settings.set_speed(_speed_tiers[index].id)


func _on_fog_toggled(pressed: bool) -> void:
	_fog_on = pressed
	MenuSetupMemory.remember(_map_picker.selected_map(), _fog_on, _seat_strip)


## Re-dresses the panel for the seats now at the table. Which tier and general
## each seat has is the strip's own, so what is left here is Start.
func _refresh_seats() -> void:
	_start_button.disabled = not _seat_strip.valid()
	_seat_refusal.text = _seat_strip.refusal()
	MenuSetupMemory.remember(_map_picker.selected_map(), _fog_on, _seat_strip)


func _on_map_selected(_index: int) -> void:
	_deal_seats_for_map()


## How many seats there are is the board's answer (four-players D1), so the strip
## is re-dealt from the picker's selection rather than from anything the player
## set. Silent while the strip is still being built: the picker chooses a board on
## its way up, before there is a strip to deal to.
func _deal_seats_for_map() -> void:
	var map := _map_picker.selected_map()
	if map == null or _seat_strip == null:
		return
	_seat_strip.set_roster(map.player_count())
	_refresh_seats()


# --- flow --------------------------------------------------------------------


## Opens the commander page for one seat, hiding the menu behind it so no focus
## or click leaks through to the buttons underneath. `chip` is where focus lands
## when the page closes.
func _open_general(seat: int, chip: Control = null) -> void:
	_general_chip = chip
	_menu_root.hide()
	var generals := _seat_strip.generals
	_select_panel.begin_seat(
		seat, generals.of(seat), generals.besides(seat), _seat_strip.ai_teams().has(seat)
	)


## Back from the commander page, with its one pick or none (`{}`, a Back): the
## setup is as it was left, and focus returns to the chip that opened the page.
func _on_general_picked(picks: Dictionary) -> void:
	_menu_root.show()
	_seat_strip.seat_generals(picks)
	if _general_chip != null:
		_general_chip.grab_focus.call_deferred()


func _open_replays() -> void:
	_menu_root.hide()
	_replay_panel.begin(
		(
			_capture_driver.posed_replays()
			if _capture_driver.poses(MenuCaptureDriver.DEMO_REPLAYS)
			else ReplayFile.list()
		)
	)


## A recording states its own board, seating, commanders and fog, so watching one
## is the shortest launch this menu makes: name the file and go.
func _on_replay_picked(path: String) -> void:
	MatchConfig.stage(MatchRequest.from_replay(path))
	get_tree().change_scene_to_file(BATTLE_SCENE)


## Back lands on the setup exactly as it was left, like the commander page's Back.
func _on_replay_cancelled() -> void:
	_menu_root.show()
	_replay_button.grab_focus()


## `load_save` resumes the saved match (its own map, commanders, AI sides and
## difficulty apply, so the choices above are ignored).
func _start(ai_teams: Array[int], load_save: bool, commanders: Dictionary) -> void:
	var map := _map_picker.selected_map()
	var request := MatchRequest.from_menu(
		map.source_path if map != null else MatchRequest.DEFAULT_MAP_PATH,
		ai_teams,
		_fog_on,
		Difficulty.DEFAULT_ID,
		commanders,
		load_save,
		_seat_strip.sides(),
		_seat_strip.seats(),
		_seat_strip.seat_difficulty()
	)
	MatchConfig.stage(request)
	get_tree().change_scene_to_file(BATTLE_SCENE)


# --- dev captures ------------------------------------------------------------


## What a capture measures itself against: the whole centered stack, plus every
## primary action by name. See MenuCaptureDriver._fits for why it is both.
func _chrome() -> Dictionary[String, Control]:
	var chrome: Dictionary[String, Control] = {
		"the menu column": _column,
		"selected map facts": _map_picker.caption(),
		"Start": _start_button,
		"Continue": _continue.button(),
		"Replays": _replay_button,
		"Quit": _quit_button,
	}
	# Every seat by name, the way the select page names its chips: a control the
	# gate does not name is a control that can silently vanish, which is how the
	# strip came to be photographed as bare panel.
	var seats := _seat_strip.rows()
	for i in seats.size():
		chrome["seat %d" % (i + 1)] = seats[i]
	return chrome


## The other half of naming the seat strip in a capture: the rows are in `_chrome`
## so one off the frame refuses the picture, and this is how a *blank* one does.
## An unsorted row is inside every frame (see SeatStrip.layout_error), so the frame
## check alone would have photographed the empty band again.
##
## Claimed only while the strip is on screen: a `--co-select` capture photographs
## the commander page over a hidden menu, and a control the picture does not show
## is not one this frame promises anything about. Read back by
## MenuCaptureDriver's capture gate; a capture-driver seam.
func seats_laid_out() -> bool:
	if not _seat_strip.is_visible_in_tree():
		return true
	var error := _seat_strip.layout_error()
	if error == "":
		return true
	push_error("main menu: %s" % error)
	return false


## Semantic half of the COM-19 capture gate: layout alone cannot prove that the
## tutorial board leads, that a hot-seat setup has no operable AI difficulty, or
## that the caption's budget holds for a board this frame does not show. Read
## back by MenuCaptureDriver's capture gate; a capture-driver seam.
func setup_context_ready() -> bool:
	var passed := true
	var map := _map_picker.selected_map()
	if map == null or not MapCatalog.teaches(map.source_path):
		push_error("main menu setup context: tutorial board is not the default")
		passed = false
	elif not _map_picker.caption().text.contains(map.description):
		push_error("main menu setup context: selected map description is not visible")
		passed = false
	# Deliberately not short-circuiting, like the driver's own frame check: one
	# failed run should name every promise that broke, not just the first.
	# Who is at the table is state, so the strip walks it rather than the frame
	# photographing one side of it.
	passed = _seat_strip.tier_rule_holds() and passed
	passed = _map_picker.caption_budget_holds() and passed
	return passed
