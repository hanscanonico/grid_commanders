class_name MainMenu
extends Control
## The title screen and everything reached from it: Continue, a skirmish, the
## campaign, recordings, the map editor and the settings. A skirmish is set up on
## its own two steps (`SkirmishSetup`) and handed off by staging one MatchRequest.
##
## The screen wears the Grid Commander Design System (menu-revamp plan), built in
## code rather than a .tscn, like CommanderSelectPanel and CommanderCard — the layout
## is regular and data-driven, and code-built styleboxes are the one form this repo
## can review in a diff (D1).
##
## "Continue" bypasses setup — a saved match restores its own commanders. It is
## disabled, not hidden, when there is nothing to resume (plan section 2), and it
## names what it would resume on the line beneath it: "Day 4 · Scrimmage". Disabled
## rather than hidden is also what keeps the two layouts the same height: a save's
## presence may never change the layout budget (UX-recovery D2), which is what
## `--demo=menu_with_save` / `--demo=menu_no_save` photograph and what
## MenuCaptureDriver refuses to let regress.

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const EDITOR_SCENE := "res://scenes/editor/map_editor.tscn"
const ICON_PATH := "res://assets/icon.png"
## Faction-silent by faction-identity D5: no "Red vs Blue" reaches a player screen.
const TAGLINE := "TURN-BASED TACTICS · PICK YOUR GROUND"
## The title's button stack: wide enough for the longest thing Continue names.
const STACK_W := 180

## Everything the commander page hides behind itself when it opens, so no focus or
## click leaks to the buttons underneath.
var _menu_root: Control

## The title screen, and the skirmish steps that replace it.
var _title: Control
var _setup: SkirmishSetup
## The map picker (MN2), the one owner of the roster and of which board is in hand.
var _map_picker: MapPicker
## Who sits where and who stands with whom (plan D6). The one authority on both,
## asked at launch rather than mirrored into menu state.
var _seat_strip: SeatStrip
## The whole centered stack — wordmark and buttons. Kept because it
## is the one rect that answers "does the menu fit?": the CenterContainer around
## it hands a too-tall column a negative offset, so an overflow runs off *both*
## ends at once and no single child is a reliable witness to it.
var _column: VBoxContainer
var _skirmish_button: Button
## The Continue row — the button, its caption, its tip and the press that opens
## the save — kept whole in its own collaborator. It is handed what the slot
## holds; where that comes from stays this page's decision.
var _continue: ContinueSlot
var _campaign_button: Button
var _replay_button: Button
var _editor_button: Button
var _quit_button: Button
## The page's scenery and the one switch that holds it, so the Menu motion row
## answers without rebuilding the screen.
var _motion := MenuMotion.new()
## True while this boot is posing a still frame for a capture, which holds the
## motion whatever the player prefers — see `_apply_menu_motion`.
var _posed := false

var _select_panel: CommanderSelectPanel
## The general chip that opened the commander page, for focus to return to.
var _general_chip: Control
var _replay_panel: ReplayPickerPanel
## Pick a war, pick a mission, deploy — the menu's campaign navigation, kept
## whole in its own collaborator.
var _campaign_flow: MenuCampaignFlow

## The database the picker parses its roster with.
var _terrain_db: TerrainDB
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
		# effect here is the Speed segment's highlight.
		Settings.pin(GameSpeed.MENU_CAPTURE_ID)
	if _capture_driver.rejected():
		get_tree().quit(1)
		return

	Music.play(&"parade")

	_terrain_db = TerrainDB.load_default()
	# Held before the setup's first deal remembers over it; a capture's pin has
	# already emptied it, so a photographed menu leads with the tutorial board.
	var remembered := Settings.match_setup
	# Built and stocked before the page is drawn: the backdrop bakes the fullest
	# board in the roster.
	_map_picker = MapPicker.new()
	_map_picker.configure(_terrain_db, MenuSetupMemory.map_path(remembered))
	_posed = shot_path != ""
	_build(remembered)

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
	_setup.start_requested.connect(
		func() -> void:
			_start(_seat_strip.ai_teams(), false, _seat_strip.generals.over(_seat_strip.seats()))
	)
	_setup.general_requested.connect(_open_general)
	_setup.closed.connect(_close_setup)
	_skirmish_button.pressed.connect(_open_setup.bind(SkirmishSetup.Step.MAP))
	Settings.menu_animations_changed.connect(_apply_menu_motion)
	_campaign_button.pressed.connect(_campaign_flow.open)
	_replay_button.pressed.connect(_open_replays)
	_editor_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(EDITOR_SCENE))
	if _capture_driver.poses(MenuCaptureDriver.DEMO_SETUP_CONTEXT):
		# A table of nothing but people, which the capture's rule walk starts from.
		for seat in _seat_strip.seat_count():
			_seat_strip.set_human(seat, true)
	_focus_title()
	# A board just saved in the editor was drawn to be played, so the player lands on
	# it rather than on the title.
	if _map_picker.opened_on_new_board():
		_open_setup(SkirmishSetup.Step.MAP)
	# Coming back from a mission lands on the debrief and the hub, not on the menu:
	# the campaign is still the thing being played. The session is cleared as it is
	# read, so a later Quit-to-menu cannot reopen a campaign nobody is in. Last, so
	# the debrief's own button keeps the focus.
	if CampaignSession.active():
		_campaign_flow.resume()

	await _pose_setup()

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
func _pose_setup() -> void:
	# These ask for a board by mode rather than by name: the picker's `· NP` mark and
	# a strip of more than two rows, which the tutorial board says neither of.
	if _capture_driver.poses_many_seats():
		await _map_picker.show_map(_capture_driver.four_seat_map(_map_picker.maps()))
	var wanted := _capture_driver.menu_map_index(_map_picker.maps(), _map_picker.selected_map())
	if wanted >= 0:
		await _map_picker.show_map(wanted)
	# Opened after the board is chosen: the Players step deals the seats as it opens.
	var step := _capture_driver.posed_step()
	if step >= 0:
		_open_setup(step)
	if _capture_driver.poses(MenuCaptureDriver.DEMO_CUSTOM_SIDES):
		_seat_strip.choose_custom()
	var preset := _capture_driver.menu_preset(_seat_strip.seat_count())
	if preset >= 0:
		_seat_strip.apply_preset_at(preset)


# --- layout ------------------------------------------------------------------


## Draws the whole screen: the backdrop, the title, and the skirmish steps hidden
## behind it.
func _build(remembered: Dictionary) -> void:
	# The fullest board on the picker's shelf is what drifts behind the page, baked
	# by the thumbnail renderer — so the scenery can never disagree with the picker
	# (plan R2). The picker measures it rather than the menu taking the roster's last
	# entry: a board the player drew is listed after the shipped ones at any size.
	_motion.paint_backdrop(self, MapPicker.fullest(_map_picker.maps()))

	_menu_root = Control.new()
	_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_root)

	_title = Control.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_root.add_child(_title)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.add_child(center)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	center.add_child(_column)
	_column.add_child(_build_header())
	_column.add_child(_build_action_stack())
	var view := ViewChip.for_menu()
	view.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, UiTheme.GAP
	)
	view.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_title.add_child(view)

	_setup = SkirmishSetup.new(_map_picker, DifficultyDB.load_default().all(), remembered)
	_seat_strip = _setup.seat_strip
	_setup.hide()
	_menu_root.add_child(_setup)
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
	return row


## The stack, read top to bottom: the card that resumes a match, the two ways to
## play a new one, the quiet ways off this page, and Quit. Grouped rather than evenly
## spaced, because a column of equally-separated rows says nothing about which of
## them matters.
func _build_action_stack() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.custom_minimum_size = Vector2(STACK_W, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	_continue = ContinueSlot.new(
		col,
		func() -> void: _start([] as Array[int], true, {}),
		func(campaign_id: StringName) -> bool: return _campaign_flow.resume_saved(campaign_id)
	)
	_skirmish_button = UiKit.action_button(
		"Skirmish", "", UiTheme.ButtonVariant.PRIMARY, UiTheme.menu_identity().theme(1)
	)
	col.add_child(UiKit.touchable(_skirmish_button))
	_campaign_button = UiKit.action_button("Campaign", "", UiTheme.ButtonVariant.SECONDARY, null)
	col.add_child(UiKit.touchable(_campaign_button))
	col.add_child(_build_secondary_group())

	# Leaving is not what this page offers; a browser tab cannot leave.
	if not OS.has_feature("web"):
		_quit_button = UiKit.text_link("Quit")
		# A step lighter than a link on the cream panel: this one sits on the backdrop.
		_quit_button.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
		_quit_button.add_theme_color_override("font_hover_color", UiTheme.WHITE)
		col.add_child(UiKit.touchable(_quit_button))
		_quit_button.pressed.connect(get_tree().quit)
	return col


## The recordings of matches already played, authoring a board — the one thing here
## that is not playing the game (COM-263) — and the device's settings (SK-14).
## Chrome-less, because none of them starts a match.
func _build_secondary_group() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	_replay_button = UiKit.action_button("Replays", "", UiTheme.ButtonVariant.GHOST, null)
	col.add_child(UiKit.touchable(_replay_button))
	_editor_button = UiKit.action_button("Map Editor", "", UiTheme.ButtonVariant.GHOST, null)
	col.add_child(UiKit.touchable(_editor_button))
	var settings := UiKit.action_button("Settings", "", UiTheme.ButtonVariant.GHOST, null)
	col.add_child(UiKit.touchable(settings))
	MenuSettingsPage.attach(self, _menu_root, settings)
	return col


# --- small helpers -----------------------------------------------------------


## Whether the page's scenery moves: this boot's capture pose outranks the
## preference, a still frame not being allowed to depend on which machine took it.
func _apply_menu_motion() -> void:
	_motion.set_moving(not _posed and Settings.menu_animations)


# --- flow --------------------------------------------------------------------


## Where focus rests on the title: the match waiting to be resumed, else a new one.
func _focus_title() -> void:
	if _continue.button().disabled:
		_skirmish_button.grab_focus()
	else:
		_continue.button().grab_focus()


func _open_setup(step: SkirmishSetup.Step) -> void:
	_title.hide()
	_setup.show()
	_setup.open_step(step)


func _close_setup() -> void:
	_setup.hide()
	_title.show()
	_skirmish_button.grab_focus()


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


## Back lands where it was pressed, like the commander page's Back.
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
		_setup.fog_on,
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


## What a capture measures itself against: the step on screen, or the whole centered
## stack plus every action by name. See MenuCaptureDriver._fits for why it is both.
func _chrome() -> Dictionary[String, Control]:
	if _setup.visible:
		return _setup.chrome()
	return {
		"the menu column": _column,
		"Skirmish": _skirmish_button,
		"Campaign": _campaign_button,
		"Continue": _continue.button(),
		"Replays": _replay_button,
		"Map Editor": _editor_button,
		"Quit": _quit_button,
	}


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
## tutorial board leads, that a seat names a tier only while the computer plays it, or
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
