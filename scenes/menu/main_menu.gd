class_name MainMenu
extends Control
## Main menu: pick a map and match options, choose commanders on the dedicated
## selection page, then hand off to the battle scene by staging one MatchRequest.
##
## The screen wears the Grid Commander Design System (menu-revamp plan): a header
## with the wordmark, a cream Match Setup panel beside an action stack, all drawn
## from UiTheme's styleboxes and fonts. Built in code rather than a .tscn, like
## CommanderSelectPanel and CommanderCard — the layout is regular and data-driven,
## and code-built styleboxes are the one form this repo can review in a diff (D1).
##
## The flow is untouched. "Start" opens the CommanderSelectPanel (readiness plan
## G2) for the seats the strip has dealt, shown *over* this menu so the map and fog
## choices survive a Back; no request is staged until every seat's commander is
## confirmed there.
## "Continue" bypasses selection — a saved match restores its own commanders. It
## is disabled, not hidden, when there is nothing to resume (plan section 2), and
## it names what it would resume on the micro-line beneath it: "DAY 4 · SCRIMMAGE".
## Disabled rather than hidden is also what keeps the two layouts the same height:
## a save's presence may never change the layout budget (UX-recovery D2), which is
## what `--demo=menu_with_save` / `--demo=menu_no_save` photograph and what
## MenuCaptureDriver refuses to let regress.

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const ICON_PATH := "res://assets/icon.png"
## Faction-silent by faction-identity D5: no "Red vs Blue" reaches a player screen.
const TAGLINE := "TURN-BASED TACTICS · PICK YOUR GROUND"
const _BLINK_SECONDS := 0.7
## Canvas px per cell in the drifting terrain field behind the menu, and how much
## bigger than the canvas the field is drawn so panning never exposes an edge.
const BACKDROP_TILE := 4
const BACKDROP_SPAN := Vector2(680, 400)
## Lines reserved for the selected board's caption. The words change with the
## selection; the height may not (UX-recovery D2), so the panel is as tall on the
## longest description as on the shortest.
const MAP_CAPTION_LINES := 2

## Everything the select page hides behind itself when it opens, so no focus or
## click leaks to the buttons underneath.
var _menu_root: Control

## The map picker: a scrollable two-up grid of live board thumbnails (MN2). The
## selected index drives the header, static facts, tooltip, and match's map_path.
var _map_header: Label  # the panel's header-right "name · size"
var _map_caption: Label
var _map_scroll: ScrollContainer
var _map_cells: Array[Button] = []
var _map_marks: Array[Label] = []
var _selected_map := 0
var _fog_on := false
## The whole centered stack — header, setup panel, action column. Kept because it
## is the one rect that answers "does the menu fit?": the CenterContainer around
## it hands a too-tall column a negative offset, so an overflow runs off *both*
## ends at once and no single child is a reliable witness to it.
var _column: VBoxContainer
var _start_button: Button
## The footer identity chips, one per seat. Rebuilt from the roster rather than
## written out, so a board that seats four shows four.
var _chips: HBoxContainer
## Why Start is refusing, under the button. A greyed control with no reason is the
## affordance this menu was burned by once already (COM-19).
var _seat_refusal: Label
## Who sits where and who stands with whom (plan D6). The one authority on both,
## asked at launch rather than mirrored into menu state.
var _seat_strip: SeatStrip
var _difficulty_buttons: Array[Button] = []
var _setup_help_labels: Array[Label] = []
var _continue_button: Button
## The Silkscreen line under Continue naming what it resumes — "DAY 4 · SCRIMMAGE".
var _continue_caption: Label
## The tip hanging off that line, re-worded with it by `_refresh_continue`.
var _continue_tip: Tooltip
var _campaign_button: Button
var _replay_button: Button
var _quit_button: Button
var _press_start: Label

var _select_panel: CommanderSelectPanel
var _replay_panel: ReplayPickerPanel
## Pick a war, pick a mission, deploy — the menu's campaign navigation, kept
## whole in its own collaborator because it is a different question from the
## board-and-fog setup this page is otherwise about.
var _campaign_flow: MenuCampaignFlow
## The seats the computer will play, taken off the strip when Start was pressed
## and carried across the selection page so `confirmed` stages the same table the
## player set up rather than re-asking a strip they may have walked back to.
var _pending_ai_teams: Array[int] = []

## The roster in dropdown order, parsed once at load so the tooltips and header
## quote real numbers off the board rather than a hand-kept table.
var _maps: Array[MapData] = []
## Kept from parsing those boards, because a Continue press reads a saved match's
## own board through it.
var _terrain_db: TerrainDB
## Why the last Continue press could not open the save, or "" while none has
## failed. A save the caption could name may still be one `decode` refuses, and
## the press is the only place that is found out, so the refusal is kept for the
## caption refresh to read back.
var _continue_refusal := ""
## The difficulty tiers in menu order, gentlest first, and the one in hand.
var _difficulties: Array[Difficulty] = []
var _difficulty_index := 0
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
	_maps = MapCatalog.ordered(_terrain_db)
	_difficulties = DifficultyDB.load_default().all()
	_speed_tiers = GameSpeed.ordered()
	_build(shot_path == "")

	_select_panel = CommanderSelectPanel.new()
	add_child(_select_panel)
	_select_panel.confirmed.connect(_on_selection_confirmed)
	_select_panel.cancelled.connect(_on_selection_cancelled)

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

	# Coming back from a mission lands on the hub it was launched from, not on the
	# menu: the campaign is still the thing being played, and the next mission is
	# one row below the one just finished. The session is cleared as it is read, so
	# a later Quit-to-menu cannot reopen a campaign nobody is in.
	if CampaignSession.active():
		_campaign_flow.resume()
	_refresh_continue()
	_start_button.pressed.connect(func() -> void: _open_select(_seat_strip.ai_teams()))
	# The strip is the only writer of who plays what, so the rule that a table with
	# no computer at it has no difficulty to tune follows it rather than a mode
	# flag — and follows it the moment a seat changes, not only once Start is
	# pressed, so the panel can never disagree with the match in hand.
	_seat_strip.changed.connect(_refresh_seats)
	# The map picker chooses a board while it is being built, before the strip and
	# the footer chips exist, so the selection is re-read once everything does —
	# the roster is the board's answer and both of them are downstream of it.
	_refresh_map_facts()
	_continue_button.pressed.connect(_continue)
	_campaign_button.pressed.connect(_campaign_flow.open)
	_replay_button.pressed.connect(_open_replays)
	_quit_button.pressed.connect(get_tree().quit)
	if _capture_driver.poses_setup_context():
		# The frame that photographs the dimmed Difficulty: a table of nothing but
		# people has no computer to tune. Posed by seating everyone rather than by
		# focusing a mode button, because the seats are the rule's subject now.
		for seat in _seat_strip.seat_count():
			_seat_strip.set_human(seat, true)
		_refresh_seats()
	_start_button.grab_focus()

	# Dev captures of the seat strip: `--menu-map=<name>` selects a board by the
	# name MapCatalog knows it by, and `--menu-preset=<n>` applies one of
	# SeatStrip.PRESETS by index. Together they photograph the strip at four seats
	# in each grouping, which is the frame a two-army board cannot show.
	await _pose_seats(CmdArgs.user())

	# The replays page photographs a posed list over a hidden menu, exactly as the
	# selection page below does, so it hands in its own chrome for the same reason:
	# the menu's geometry is not what that picture claims.
	if _capture_driver.poses_replays():
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

	# Dev captures of the selection page — which seat it walks to and which general
	# it browses to are the driver's reading of `--co-select`, like every other
	# capture flag; what that means on screen is this menu's own flow.
	if _capture_driver.poses_selection():
		_open_select([2] as Array[int])
		var seat := _capture_driver.selection_seat()
		if seat > 0:
			_select_panel.debug_advance_to_seat(seat)
		var browsed := _capture_driver.selection_commander()
		if browsed != &"":
			_select_panel.debug_preview(browsed)
	if shot_path != "":
		# The select page measures itself against its own chrome, not the menu's: it
		# is the picture being taken, and the menu behind it is hidden.
		var chrome := _select_panel.chrome if _capture_driver.poses_selection() else _chrome
		await _capture_driver.capture(shot_path, chrome)


## Dev captures only: selects a board and applies a grouping preset, so the seat
## strip can be photographed at more seats than the default board deals. Not on
## any play path — a run with neither flag does nothing here.
##
## A miss on either flag is said out loud rather than posed quietly: the capture
## would then be taken on the default board in the default grouping and look
## exactly like a correct run, which is the failure `debug_preview` and
## `apply_cmdline`'s `--map` both refuse for the same reason — a typo has to be
## visible in the output or the shot proves the wrong thing.
func _pose_seats(args: PackedStringArray) -> void:
	var wanted := CmdArgs.value(args, "--menu-map")
	if wanted != "":
		var path := MapCatalog.resolve(wanted)
		var found := false
		for i in _maps.size():
			if _maps[i].source_path == path:
				_select_map(i)
				found = true
				break
		if not found:
			var shown := _map_at(_selected_map)
			push_error(
				(
					"main menu: no board '%s'; this capture shows %s. Known: %s"
					% [
						wanted,
						"no board" if shown == null else MapCatalog.display_name(shown.source_path),
						", ".join(MapCatalog.resolvable_names()),
					]
				)
			)
		# The picker scrolls the selection into view, which needs a laid-out tree —
		# a capture on the same frame photographs the board it was showing before.
		await get_tree().process_frame
		if _selected_map < _map_cells.size():
			_map_scroll.ensure_control_visible(_map_cells[_selected_map])
		await get_tree().process_frame
	if not CmdArgs.has(args, "--menu-preset"):
		return
	var wanted_preset := CmdArgs.value(args, "--menu-preset")
	if not wanted_preset.is_valid_int():
		push_error(
			(
				"main menu: '%s' is not a grouping preset; this capture shows the grouping in hand"
				% wanted_preset
			)
		)
		return
	var preset := int(wanted_preset)
	if preset < 0 or preset >= SeatStrip.PRESETS.size():
		push_error(
			"main menu: no grouping preset %d; this capture shows the grouping in hand" % preset
		)
		return
	_seat_strip.apply_preset_at(preset)
	_refresh_seats()


# --- layout ------------------------------------------------------------------


## Draws the whole screen. `animate` is false under a capture so the one moving
## thing on the menu (the blinking PRESS START) is pinned solid — a still frame
## must not depend on when it was taken.
func _build(animate: bool) -> void:
	_paint_backdrop(animate)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_menu_root = center

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
	_column = column

	column.add_child(_build_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UiTheme.GAP)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(body)
	body.add_child(_build_setup_panel())
	body.add_child(_build_action_stack(animate))
	_reserve_map_caption()


## The backdrop the menu sits on: a radial-lit slate floor (a brighter pool at
## top-centre so the header reads against light, the panels against dark) with one
## shipped board baked to a texture and drifting faintly behind everything — the
## boot-screen game feel of the mockup. `animate` is false under a capture: the
## drift and blink pin still so a frame never depends on when it was taken (the
## animator's `capturing` precedent, plan MN2/R3).
func _paint_backdrop(animate: bool) -> void:
	var floor := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, UiTheme.SLATE_800)
	gradient.set_color(1, UiTheme.SLATE_900)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.12)
	tex.fill_to = Vector2(1.05, 1.05)
	tex.width = 128
	tex.height = 72
	floor.texture = tex
	floor.stretch_mode = TextureRect.STRETCH_SCALE
	floor.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(floor)

	if _maps.is_empty():
		return
	# The fullest board in the roster (largest, so last in MapCatalog.ordered()), baked
	# once by the thumbnail renderer and tiled — the field is the thumbnails' own
	# output, so it can never disagree with them (plan R2).
	var board := _maps[_maps.size() - 1]
	var period := Vector2(board.width * BACKDROP_TILE, board.height * BACKDROP_TILE)
	var field := TextureRect.new()
	field.texture = MapThumbnail.bake(
		board, UiTheme.menu_identity(board.player_count()), BACKDROP_TILE
	)
	field.stretch_mode = TextureRect.STRETCH_TILE
	field.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	field.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	field.modulate = Color(1, 1, 1, 0.14)
	# Oversized by one tiling period so the screen stays covered across a full pan;
	# at −period the tiled field is pixel-identical to its start, so the loop is
	# seamless.
	field.size = BACKDROP_SPAN + period
	add_child(field)
	if animate:
		var drift := field.create_tween().set_loops()
		drift.tween_property(field, "position", -period, 40.0).from(Vector2.ZERO)


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
	# IGNORE_SIZE so the 128px launcher icon honours the 32px cell instead of
	# ballooning the header to its own texture size.
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
	tagline.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	tagline.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	titles.add_child(tagline)

	row.add_child(titles)
	return row


func _build_setup_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box())
	panel.custom_minimum_size = Vector2(UiTheme.CONTENT_W, 0)

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
	_map_header = Label.new()
	_map_header.add_theme_font_override("font", UiTheme.stat())
	_map_header.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	_map_header.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	_map_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(_map_header)
	header.add_child(header_row)
	col.add_child(header)

	# --- body ---
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	col.add_child(UiKit.pad(body, 8, 7))

	body.add_child(_build_map_picker())
	body.add_child(UiKit.rule())
	body.add_child(_build_seats_row())
	body.add_child(_build_choices_row())
	body.add_child(UiKit.rule())
	body.add_child(_build_toggles_row())
	return panel


## The map picker: a scrollable two-up grid of live board thumbnails, the whole
## roster with its teaching board first (MapCatalog.ordered) — the dropdown is
## gone (MN2). The selected cell gets the raised cream surface, the meridian
## border and a ✓; scroll follows keyboard focus so every board is reachable
## without a mouse. A static caption beneath the viewport carries the
## decision-critical facts; each cell keeps the richer tooltip as optional detail.
func _build_map_picker() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.add_child(UiKit.micro_label("Map"))

	_map_scroll = ScrollContainer.new()
	# 126 before the seat strip took its lines of the panel's fixed height. The
	# picker is the one control here that scrolls by design, so it is the one that
	# gives ground: a board stays one flick away, where a seat row pushed past the
	# bottom would have been off the frame entirely (`_chrome` refuses that).
	_map_scroll.custom_minimum_size = Vector2(0, 80)
	_map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_map_scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_scroll.add_child(grid)

	if _maps.is_empty():
		push_error("main menu: no maps found in %s" % MapCatalog.MAPS_DIR)
	for i in _maps.size():
		grid.add_child(_make_map_cell(i, _maps[i]))
	_map_caption = UiKit.help_label("")
	_map_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_caption.max_lines_visible = MAP_CAPTION_LINES
	_map_caption.add_theme_constant_override("line_spacing", 1)
	col.add_child(_map_caption)
	_select_map(0)
	return col


## One picker cell: a focusable button holding a live thumbnail and the board's
## name. The thumbnail is a truthful miniature — real terrain, real property
## colours — of the board this cell launches (plan D5).
func _make_map_cell(index: int, map: MapData) -> Button:
	const THUMB := Vector2(132, 60)
	var button := Button.new()
	button.custom_minimum_size = Vector2(THUMB.x, THUMB.y + 14)
	# The cell is a single control describing itself, so it is its own trigger —
	# the micro-label rule guards *group* controls, where hovering to reach a
	# segment would fire an explanation of the group.
	Tooltip.attach(
		button,
		map.description,
		"%d×%d · %d properties" % [map.width, map.height, map.property_cells().size()],
		Tooltip.Side.BOTTOM
	)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(content)

	var thumb := MapThumbnail.new()
	# The board's own roster, never the two-seat default: a four-army board's third
	# and fourth HQs resolve to no theme under a duel's identity and would draw
	# neutral grey, so the picker would show a duel where the match seats four.
	thumb.setup(map, UiTheme.menu_identity(map.player_count()), THUMB)
	thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(thumb)

	var name_label := Label.new()
	name_label.text = _map_cell_name(map, false)
	name_label.add_theme_font_override("font", UiTheme.display())
	name_label.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	name_label.add_theme_color_override("font_color", UiTheme.INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(name_label)
	UiTheme.make_decoration(content)

	button.focus_entered.connect(_select_map.bind(index))
	button.pressed.connect(_select_map.bind(index))
	_map_cells.append(button)
	_map_marks.append(name_label)
	return button


## The seat strip: who plays each army the board deals, and who stands with whom.
## Built with this panel's own segment builder so a seat row is the same control
## the difficulty and speed rows are — see SeatStrip, which owns the state.
func _build_seats_row() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	# No section label: each row already says which seat it is, and the panel's
	# height budget is real (see `_chrome`).
	_seat_strip = SeatStrip.new()
	_seat_strip.configure(UiTheme.menu_identity().theme(1).color)
	col.add_child(_seat_strip)
	# No help line: the grouping buttons name themselves, each segment carries the
	# sentence as a tip, and the panel's height is fixed — a line spent here is a
	# line off the map picker.
	return col


func _build_choices_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	if _difficulties.is_empty():
		push_error("main menu: no difficulty tiers found in %s" % DifficultyDB.DIFFICULTY_DIR)
	var diff_labels := PackedStringArray()
	var diff_selected := 0
	for i in _difficulties.size():
		diff_labels.append(_difficulties[i].display_name)
		if _difficulties[i].id == Difficulty.DEFAULT_ID:
			diff_selected = i
	_difficulty_index = diff_selected
	var meridian := UiTheme.menu_identity().theme(1)
	# Kept shorter than the line it replaced: a help line's own text is its minimum
	# width, so a longer sentence here widens the whole centred column past the
	# 640px frame — which `_chrome` refuses to photograph.
	var diff_detail := "Every CPU seat · judgement; never cheats"
	var difficulty := UiKit.segment(
		"Difficulty",
		diff_labels,
		diff_selected,
		meridian.color,
		"How well the computer plays, at every CPU seat at the table",
		diff_detail,
		_on_difficulty_selected,
		_difficulty_buttons
	)
	difficulty.add_child(_option_help(diff_detail))
	difficulty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(difficulty)

	var speed_labels := PackedStringArray()
	var speed_selected := 0
	for i in _speed_tiers.size():
		speed_labels.append(_speed_tiers[i].display_name)
		if _speed_tiers[i].id == Settings.speed.id:
			speed_selected = i
	var speed_detail := "Pacing only · outcomes never change"
	var speed := UiKit.segment(
		"Speed",
		speed_labels,
		speed_selected,
		meridian.color,
		"How fast moves and battles play out",
		speed_detail,
		_on_speed_selected
	)
	speed.add_child(_option_help(speed_detail))
	speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(speed)
	return row


func _build_toggles_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var fog_col := VBoxContainer.new()
	fog_col.add_theme_constant_override("separation", 2)
	var fog := UiKit.toggle(
		"Fog of war",
		_fog_on,
		"Hide the board beyond your units' sight",
		"Off shows the whole map",
		_on_fog_toggled
	)
	fog_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fog_col.add_child(fog)
	fog_col.add_child(_option_help("Hides tiles beyond your units' sight"))
	row.add_child(fog_col)
	var anim_col := VBoxContainer.new()
	anim_col.add_theme_constant_override("separation", 2)
	var anim := UiKit.toggle(
		"Battle animations",
		Settings.battle_animations,
		"Play the full-screen cut-in when an attack resolves",
		"Any key skips one in progress",
		_on_animations_toggled
	)
	anim_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anim_col.add_child(anim)
	anim_col.add_child(_option_help("Full-screen cut-ins · any key skips"))
	row.add_child(anim_col)
	return row


func _build_action_stack(animate: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.custom_minimum_size = Vector2(UiTheme.ACTION_W, 0)

	var identity := UiTheme.menu_identity()
	# One action where there were two modes: who is playing is the seat strip's to
	# say now, so this button only has to mean "with these seats" (plan D6).
	_start_button = UiKit.action_button(
		"Start", "MATCH", UiTheme.ButtonVariant.PRIMARY, identity.theme(1)
	)
	col.add_child(_start_button)
	_seat_refusal = UiKit.micro_label("")
	_seat_refusal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seat_refusal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_seat_refusal)

	_continue_button = UiKit.action_button("Continue", "", UiTheme.ButtonVariant.SECONDARY, null)
	col.add_child(_continue_button)
	# What Continue resumes, on its own line rather than as the button's inline
	# suffix: "DAY 12 · THE STRAITS" is longer than the 122px action stack can set
	# at button size, and a micro-label under the control is the panel's own idiom.
	#
	# It is also Continue's tip trigger. The button itself is the one control here
	# that can be disabled, and a disabled control is exactly where a tip is the
	# only affordance left — so the explanation hangs off the caption beneath it,
	# which stays hoverable either way. `_refresh_continue` sets the words.
	_continue_caption = UiKit.micro_label("")
	_continue_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue_caption.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_tip = Tooltip.attach(_continue_caption, "", "", Tooltip.Side.BOTTOM)
	# A disabled button takes no focus — the case the hoverable caption covers.
	_continue_tip.follow_focus(_continue_button)
	col.add_child(_continue_caption)

	# Above Replays, below Continue: an authored war is a different offer from the
	# skirmish this page is otherwise about, and it is the one a first-time player
	# is most likely to want.
	_campaign_button = UiKit.action_button("Campaign", "", UiTheme.ButtonVariant.SECONDARY, null)
	col.add_child(_campaign_button)

	# Below Continue, above Quit: it is the third thing you can do with a match, and
	# the only surface that tells a player their matches are being recorded at all.
	_replay_button = UiKit.action_button("Replays", "", UiTheme.ButtonVariant.SECONDARY, null)
	col.add_child(_replay_button)

	_quit_button = UiKit.action_button("Quit", "", UiTheme.ButtonVariant.GHOST, null)
	col.add_child(_quit_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	# One chip per seat the board deals, rebuilt when the map changes — the pair
	# used to be spelled out here, which is why a third army had nowhere to appear.
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 4)
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_chips)

	_press_start = Label.new()
	_press_start.text = "PRESS START"
	_press_start.add_theme_font_override("font", UiTheme.stat())
	_press_start.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	_press_start.add_theme_color_override("font_color", UiTheme.NEUTRAL_DARK)
	_press_start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_press_start)
	if animate:
		_start_blink()
	return col


## Re-deals the footer chips for a board that seats `count` armies. Every seat
## gets its colour and its P-number, so the strip above and the chips below name
## the same table.
## One chip per army at the table — the seats that play, not the seats the board
## deals, so closing one takes its livery off the footer as it takes it off the
## board. Resolved over that same roster, which is what the battle resolves over.
func _refresh_chips(seats: Array[int]) -> void:
	if _chips == null:
		return
	for child in _chips.get_children():
		_chips.remove_child(child)
		child.queue_free()
	var identity := UiTheme.menu_identity_of(seats)
	for seat in seats:
		_chips.add_child(UiKit.identity_chip(identity, seat, "P%d" % seat))


# --- small helpers -----------------------------------------------------------


## One option's help line, registered so the capture gate measures every one of
## them and refuses an empty one. The map caption is not one of these: its words
## follow the selection, so it answers to its own reserved budget instead.
func _option_help(text: String) -> Label:
	var label := UiKit.help_label(text)
	_setup_help_labels.append(label)
	return label


## Pins the caption's height to its reserved lines, asked of the label itself
## rather than typed in as a pixel count, so a font or spacing change carries the
## reservation with it. Called once the whole menu is in the tree: a Control
## resolves its fonts through the tree, so measured before that the label answers
## with the default theme's line height instead of its own.
func _reserve_map_caption() -> void:
	var words := _map_caption.text
	_map_caption.text = "X\n".repeat(MAP_CAPTION_LINES - 1) + "X"
	_map_caption.custom_minimum_size = Vector2(0, _map_caption.get_combined_minimum_size().y)
	_map_caption.text = words


func _start_blink() -> void:
	var timer := Timer.new()
	timer.wait_time = _BLINK_SECONDS
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(func() -> void: _press_start.visible = not _press_start.visible)


# --- match option state ------------------------------------------------------


## Picks a board: repaints the cells (the selected one raised, red-bordered and
## ✓-marked), updates the header-right name·size, and scrolls the choice into
## view so keyboard focus never lands on an off-screen cell.
func _select_map(index: int) -> void:
	if index < 0 or index >= _maps.size():
		return
	_selected_map = index
	for i in _map_cells.size():
		_style_map_cell(_map_cells[i], _map_marks[i], i, i == index)
	if index < _map_cells.size():
		_map_scroll.ensure_control_visible(_map_cells[index])
	_refresh_map_facts()


func _style_map_cell(cell: Button, name_label: Label, index: int, selected: bool) -> void:
	var meridian := UiTheme.menu_identity().theme(1)
	var box := _map_cell_box(UiTheme.PAPER_RAISED if selected else Color(0, 0, 0, 0))
	if selected:
		box.border_color = meridian.color
		box.set_border_width_all(UiTheme.PANEL_BORDER)
		UiTheme.hard_shadow(box)
	cell.add_theme_stylebox_override("normal", box)
	cell.add_theme_stylebox_override("hover", box if selected else _cell_hover_box())
	cell.add_theme_stylebox_override("pressed", box)
	cell.add_theme_stylebox_override("focus", UiTheme.focus_box())
	name_label.text = (_map_cell_name(_maps[index], selected))
	name_label.add_theme_color_override("font_color", UiTheme.INK if selected else UiTheme.NEUTRAL)


func _cell_hover_box() -> StyleBoxFlat:
	return _map_cell_box(UiTheme.HOVER_WASH)


## The map picker cell's shared frame: a flat fill, a whisker of rounding and the
## grid's even inset. `_style_map_cell` layers a border and shadow on top when the
## cell is selected; the hover wash and the unselected rest state need neither.
func _map_cell_box(fill: Color) -> StyleBoxFlat:
	var box := UiTheme.flat(fill)
	box.set_corner_radius_all(UiTheme.RADIUS)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


func _map_cell_name(map: MapData, selected: bool) -> String:
	var cell_name := MapCatalog.display_name(map.source_path)
	if MapCatalog.teaches(map.source_path):
		cell_name += " · Tutorial"
	if map.player_count() > 2:
		cell_name += " · %dP" % map.player_count()
	if selected:
		cell_name += " ✓"
	return cell_name


## The caption `_refresh_map_facts` shows for `map`, factored out so the budget
## check can measure every board without touching `_selected_map`.
func _map_caption_text(map: MapData) -> String:
	var parts := [
		map.width,
		map.height,
		_armies_label(map.player_count()),
		map.property_cells().size(),
		map.description,
	]
	return ("%d×%d · %s · %d properties · %s" % parts).to_upper()


## Header and persistent caption, read off the board itself so no hand-kept table
## can drift from it. Tooltips repeat the facts but are never required to choose.
func _refresh_map_facts() -> void:
	var map := _map_at(_selected_map)
	if map == null:
		_map_header.text = ""
		_map_caption.text = ""
		return
	_map_header.text = (
		"%s · %d×%d" % [MapCatalog.display_name(map.source_path), map.width, map.height]
	)
	_map_caption.text = _map_caption_text(map)
	# How many seats there are is the board's answer (plan D1), so the strip is
	# re-dealt from the selection rather than from anything the player set.
	if _seat_strip != null:
		_seat_strip.set_roster(map.player_count())
		_refresh_seats()


## "4 armies" for a board whose seats all have to be filled, "2–4 armies" for one
## where some may close (open-seats plan D4). A range rather than a count because a
## count is what the board deals and the shelf's widest capability is what a player
## scrolling the list is choosing between.
func _armies_label(seats: int) -> String:
	if seats <= SeatStrip.MIN_FILLED:
		return "%d armies" % seats
	return "%d–%d armies" % [SeatStrip.MIN_FILLED, seats]


func _map_at(index: int) -> MapData:
	if index < 0 or index >= _maps.size():
		return null
	return _maps[index]


func _on_difficulty_selected(index: int) -> void:
	if index >= 0 and index < _difficulties.size():
		_difficulty_index = index


## Speed is the odd one out: a device preference, not a match option, so a tap
## writes Settings.set_speed immediately and never rides MatchConfig (game-speed
## plan D1). The same setting applies to the next match and to a resumed save.
func _on_speed_selected(index: int) -> void:
	if index >= 0 and index < _speed_tiers.size():
		Settings.set_speed(_speed_tiers[index].id)


func _on_fog_toggled(pressed: bool) -> void:
	_fog_on = pressed


## Battle animations, like speed, is a standing device preference: it writes
## through the moment it is toggled rather than waiting for a match to start.
func _on_animations_toggled(pressed: bool) -> void:
	Settings.set_battle_animations(pressed)


func _selected_difficulty() -> StringName:
	if _difficulty_index < 0 or _difficulty_index >= _difficulties.size():
		return Difficulty.DEFAULT_ID
	return _difficulties[_difficulty_index].id


## Re-dresses the panel for the seats now at the table. Difficulty tunes the
## computer, so a table with nobody but people at it has none to tune and the
## tiers go inert — the same rule the two mode buttons carried, asked of the
## seats instead of of a mode flag (COM-19, generalised by plan D6).
##
## The one writer of both, so the tiers can never be left stranded behind a table
## nobody is sitting at any more, and Start can never offer a match the sim would
## resolve before anyone moved.
func _refresh_seats() -> void:
	var all_human := _seat_strip.ai_teams().is_empty()
	for button in _difficulty_buttons:
		button.disabled = all_human
	_start_button.disabled = not _seat_strip.valid()
	_seat_refusal.text = _seat_strip.refusal().to_upper()
	_seat_refusal.add_theme_color_override("font_color", UiTheme.NEUTRAL_DARK)
	# The chips are dressed from the table too, not from the board: a seat closed
	# here is an army that will not be on the map, so its livery leaves the footer
	# in the same tap (open-seats plan D4).
	_refresh_chips(_seat_strip.seats())


# --- flow (unchanged) --------------------------------------------------------


## Opens the selection page for the chosen mode, hiding the menu behind it so no
## focus or click leaks through to the buttons underneath.
func _open_select(ai_teams: Array[int]) -> void:
	_pending_ai_teams = ai_teams
	_menu_root.hide()
	# The filled seats, not the board's: a commander belongs to an army that plays,
	# so a closed seat is not a slot to walk (open-seats plan D4).
	_select_panel.begin(_seat_strip.seats(), ai_teams)


func _on_selection_confirmed(picks: Dictionary) -> void:
	_start(_pending_ai_teams, false, picks)


## Back from selection returns to the setup exactly as it was left: the strip
## still holds the table that opened the page, Start takes focus back, and the
## panel re-reads the seats rather than assuming what they say.
func _on_selection_cancelled() -> void:
	_menu_root.show()
	_refresh_seats()  # the strip is unchanged, but the panel re-reads it either way
	_start_button.grab_focus()


func _open_replays() -> void:
	_menu_root.hide()
	_replay_panel.begin(
		_capture_driver.posed_replays() if _capture_driver.poses_replays() else ReplayFile.list()
	)


## A recording states its own board, seating, commanders and fog, so watching one
## is the shortest launch this menu makes: name the file and go.
func _on_replay_picked(path: String) -> void:
	MatchConfig.stage(MatchRequest.from_replay(path))
	get_tree().change_scene_to_file(BATTLE_SCENE)


## Back lands on the setup exactly as it was left, like the select page's Back.
func _on_replay_cancelled() -> void:
	_menu_root.show()
	_replay_button.grab_focus()


## Names the saved match under the Continue button, so the menu alone answers
## "is this the match I meant?" — the whole point of labelling the slot. The day
## and board are read off the save envelope's own keys (SaveGame.status); nothing
## is rebuilt, and the save format is untouched.
##
## Three captions, because the slot has three answers: a player told "no saved
## match" about a save the disk truncated is told they never had one (COM-121).
## A damaged save disables Continue like an empty slot does, and says why in the
## codec's own words rather than in the codec's log.
func _refresh_continue() -> void:
	var slot := (
		_capture_driver.posed_slot(_maps) if _capture_driver.poses_slot() else SaveGame.status()
	)
	if slot.state == SaveGame.Slot.State.ABSENT:
		_refuse_continue("NO SAVED MATCH", "Nothing saved yet", "Save in battle from the map menu")
		return
	# The codec's words when the slot itself will not read, the press's when the save
	# was nameable and would not open.
	var refusal := (
		slot.reason if slot.state == SaveGame.Slot.State.UNREADABLE else _continue_refusal
	)
	if refusal != "":
		_refuse_continue("SAVED MATCH UNREADABLE", "That save cannot be opened", refusal)
		return
	_continue_button.disabled = false
	_continue_caption.text = slot.summary.label().to_upper()
	# The tagline's tone, which is what a micro-label needs to carry a fact rather
	# than a hint on the dark backdrop — NEUTRAL_DARK is barely legible out here.
	_continue_caption.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	# The caption already names the day and board, so the tip does not repeat them.
	_continue_tip.set_copy("Resume the saved match", "Its own board and commanders apply")


## Continue with nothing to offer: the dim NEUTRAL_DARK of PRESS START, because it
## explains a disabled button and must not read as loudly as a match waiting to be
## resumed.
func _refuse_continue(caption: String, tip: String, detail: String) -> void:
	_continue_button.disabled = true
	_continue_caption.text = caption
	_continue_caption.add_theme_color_override("font_color", UiTheme.NEUTRAL_DARK)
	_continue_tip.set_copy(tip, detail)


## The saved match applies its own map, commanders and AI sides — and is opened
## here, on the press, rather than on every boot: naming a save opens no board, so
## one the caption named can still be one `decode` refuses. Staging that anyway
## boots the battle scene onto the fresh match the request also states, on
## whatever board the picker is showing, with nothing said (COM-121).
func _continue() -> void:
	var chart: DamageChart = load(DamageChart.DEFAULT_PATH)
	var loaded := SaveGame.load_game(
		_terrain_db, UnitDB.load_default(), chart, SaveGame.SAVE_PATH, CommanderDB.load_default()
	)
	if loaded == null:
		# Which of the two it is the log says; a player can act on either.
		_continue_refusal = "Its board may have changed, or the file is damaged"
		_refresh_continue()
		return
	_start([] as Array[int], true, {})


## `load_save` resumes the saved match (its own map, commanders, AI sides and
## difficulty apply, so the choices above are ignored).
func _start(ai_teams: Array[int], load_save: bool, commanders: Dictionary) -> void:
	var map := _map_at(_selected_map)
	var request := MatchRequest.from_menu(
		map.source_path if map != null else MatchRequest.DEFAULT_MAP_PATH,
		ai_teams,
		_fog_on,
		_selected_difficulty(),
		commanders,
		load_save,
		_seat_strip.sides(),
		_seat_strip.seats()
	)
	MatchConfig.stage(request)
	get_tree().change_scene_to_file(BATTLE_SCENE)


# --- dev captures ------------------------------------------------------------


## What a capture measures itself against: the whole centered stack, plus every
## primary action by name. See MenuCaptureDriver._fits for why it is both.
func _chrome() -> Dictionary[String, Control]:
	var chrome: Dictionary[String, Control] = {
		"the menu column": _column,
		"selected map facts": _map_caption,
		"Start": _start_button,
		"Continue": _continue_button,
		"Replays": _replay_button,
		"Quit": _quit_button,
	}
	for i in _setup_help_labels.size():
		chrome["option help %d" % (i + 1)] = _setup_help_labels[i]
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
## the selection page over a hidden menu, and a control the picture does not show
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
	var map := _map_at(_selected_map)
	if map == null or not MapCatalog.teaches(map.source_path):
		push_error("main menu setup context: tutorial board is not the default")
		passed = false
	elif not _map_caption.text.contains(map.description.to_upper()):
		push_error("main menu setup context: selected map description is not visible")
		passed = false
	for label in _setup_help_labels:
		if label.text.strip_edges() == "":
			push_error("main menu setup context: an option-help line is empty")
			passed = false
	# Deliberately not short-circuiting, like the driver's own frame check: one
	# failed run should name every promise that broke, not just the first.
	passed = _difficulty_follows_mode() and passed
	passed = _caption_budget_holds() and passed
	return passed


## Who is at the table is state, so the gate walks it rather than photographing
## one side of it: a table of nothing but people has no computer to tune and its
## Difficulty goes inert, and seating one computer brings the tiers back. The
## posed all-human table is restored before the frame is written.
func _difficulty_follows_mode() -> bool:
	var passed := true
	if not _seat_strip.ai_teams().is_empty():
		push_error("main menu setup context: the all-human table is not the posed state")
		passed = false
	_seat_strip.set_human(_seat_strip.seat_count() - 1, false)
	_refresh_seats()
	for button in _difficulty_buttons:
		if button.disabled:
			push_error("main menu setup context: difficulty stays disabled with a CPU seated")
			passed = false
	_seat_strip.set_human(_seat_strip.seat_count() - 1, true)
	_refresh_seats()
	for button in _difficulty_buttons:
		if not button.disabled:
			push_error("main menu setup context: difficulty remains operable with nobody to tune")
			passed = false
	return passed


## No board may cost the panel a line the reserved caption does not have — the
## COM-5 class again, where the layout budget quietly depended on the selection.
## Measured on the live label's text alone; `_selected_map` and the seat strip
## it would otherwise re-deal per board (COM-48's capture workaround) stay put.
func _caption_budget_holds() -> bool:
	var passed := true
	var words := _map_caption.text
	for i in _maps.size():
		_map_caption.text = _map_caption_text(_maps[i])
		if _map_caption.get_line_count() > MAP_CAPTION_LINES:
			push_error(
				(
					"main menu setup context: %s wraps its caption to %d lines"
					% [MapCatalog.display_name(_maps[i].source_path), _map_caption.get_line_count()]
				)
			)
			passed = false
	_map_caption.text = words
	return passed
