extends Control
## Main menu: pick a map and match options, choose commanders on the dedicated
## selection page, then hand off to the battle scene through MatchConfig.
##
## The screen wears the Grid Commander Design System (menu-revamp plan): a header
## with the wordmark, a cream Match Setup panel beside an action stack, all drawn
## from UiTheme's styleboxes and fonts. Built in code rather than a .tscn, like
## CommanderSelectPanel and CommanderCard — the layout is regular and data-driven,
## and code-built styleboxes are the one form this repo can review in a diff (D1).
##
## The flow is untouched. "1 Player" and "2 Player" open the CommanderSelectPanel
## (readiness plan G2), shown *over* this menu so the map and fog choices survive a
## Back; nothing reaches MatchConfig until both commanders are confirmed there.
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

## Everything the select page hides behind itself when it opens, so no focus or
## click leaks to the buttons underneath.
var _menu_root: Control

## The map picker: a scrollable two-up grid of live board thumbnails (MN2). The
## selected index drives the header, the tooltip, and the match's map_path.
var _map_header: Label  # the panel's header-right "name · size"
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
var _one_player_button: Button
var _two_player_button: Button
var _continue_button: Button
## The Silkscreen line under Continue naming what it resumes — "DAY 4 · SCRIMMAGE".
var _continue_caption: Label
## The tip hanging off that line, re-worded with it by `_refresh_continue`.
var _continue_tip: Tooltip
var _quit_button: Button
var _press_start: Label

var _select_panel: CommanderSelectPanel
## The AI sides the chosen mode will play; carried across the selection page so
## `confirmed` knows whether it was a one-player or hot-seat start.
var _pending_ai_teams: Array[int] = []

## The roster in dropdown order, parsed once at load so the tooltips and header
## quote real numbers off the board rather than a hand-kept table.
var _maps: Array[MapData] = []
## The difficulty tiers in menu order, gentlest first, and the one in hand.
var _difficulties: Array[Difficulty] = []
var _difficulty_index := 0
var _speed_tiers: Array[GameSpeed] = []
## Dev-only, built on every boot because it is what reads the command line; it
## poses nothing and gates nothing on an ordinary run.
var _capture_driver: MenuCaptureDriver


func _ready() -> void:
	var shot_path := ScreenshotUtil.requested()
	if shot_path != "":
		# The battle scene's rule, and for the same reason: a capture must not
		# show — or depend on — the preference of the machine that took it. Here
		# the pin's only observable effect is the Speed segment's highlight and the
		# blinking PRESS START, which is pinned solid below.
		Settings.pin(GameSpeed.DEFAULT_ID)
	_capture_driver = MenuCaptureDriver.new(self)
	if _capture_driver.rejected():
		get_tree().quit(1)
		return

	_maps = MapCatalog.ordered(TerrainDB.load_default())
	_difficulties = DifficultyDB.load_default().all()
	_speed_tiers = GameSpeed.ordered()
	_build(shot_path == "")

	_select_panel = CommanderSelectPanel.new()
	add_child(_select_panel)
	_select_panel.confirmed.connect(_on_selection_confirmed)
	_select_panel.cancelled.connect(_on_selection_cancelled)

	_refresh_continue()
	_one_player_button.pressed.connect(_open_select.bind([2] as Array[int]))
	_two_player_button.pressed.connect(_open_select.bind([] as Array[int]))
	_continue_button.pressed.connect(_continue)
	_quit_button.pressed.connect(get_tree().quit)
	_one_player_button.grab_focus()

	# Dev captures of the selection page: `--co-select` opens it on the Red slot,
	# `--co-select=blue` advances to the Blue slot, and `--co-select=<commander_id>`
	# browses to one named general — the roster's copy is not all one length, so a
	# capture that only ever photographs the first card proves nothing about the
	# longest. An ordinary capture (no such flag) photographs the menu itself.
	var select_mode := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--co-select" or arg.begins_with("--co-select="):
			select_mode = arg.get_slice("=", 1) if arg.contains("=") else "red"
	if select_mode != "":
		_open_select([2] as Array[int])
		if select_mode == "blue":
			_select_panel.debug_advance_to_blue()
		elif select_mode != "red":
			_select_panel.debug_preview(StringName(select_mode))
	if shot_path != "":
		await _capture_driver.capture(shot_path, _chrome() if select_mode == "" else {})


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
	# The fullest board in the roster (largest, so last after smallest-first), baked
	# once by the thumbnail renderer and tiled — the field is the thumbnails' own
	# output, so it can never disagree with them (plan R2).
	var board := _maps[_maps.size() - 1]
	var period := Vector2(board.width * BACKDROP_TILE, board.height * BACKDROP_TILE)
	var field := TextureRect.new()
	field.texture = MapThumbnail.bake(board, UiTheme.menu_identity(), BACKDROP_TILE)
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
	var icon_box := UiTheme.flat(UiTheme.SLATE_800)
	icon_box.border_color = UiTheme.HARD_BORDER
	icon_box.set_border_width_all(UiTheme.BORDER)
	UiTheme.hard_shadow(icon_box)
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
	body.add_theme_constant_override("separation", 7)
	col.add_child(_pad(body, 8, 7))

	body.add_child(_build_map_picker())
	body.add_child(_rule())
	body.add_child(_build_choices_row())
	body.add_child(_rule())
	body.add_child(_build_toggles_row())
	return panel


## The map picker: a scrollable two-up grid of live board thumbnails, the whole
## roster smallest first (MapCatalog.ordered) — the dropdown is gone (MN2). The
## selected cell gets the raised cream surface, the meridian border and a ✓; scroll
## follows keyboard focus so every board is reachable without a mouse. Each cell
## carries the old dropdown's tooltip facts, so nothing is lost in the trade.
func _build_map_picker() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.add_child(_micro_label("Map"))

	_map_scroll = ScrollContainer.new()
	_map_scroll.custom_minimum_size = Vector2(0, 148)
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
	thumb.setup(map, UiTheme.menu_identity(), THUMB)
	thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(thumb)

	var name_label := Label.new()
	name_label.text = MapCatalog.display_name(map.source_path)
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
	var difficulty := _build_segment(
		"Difficulty",
		diff_labels,
		diff_selected,
		meridian.color,
		"How well the computer plays in a 1-Player match",
		"Never cheats — only its judgement changes",
		_on_difficulty_selected
	)
	difficulty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(difficulty)

	var speed_labels := PackedStringArray()
	var speed_selected := 0
	for i in _speed_tiers.size():
		speed_labels.append(_speed_tiers[i].display_name)
		if _speed_tiers[i].id == Settings.speed.id:
			speed_selected = i
	var speed := _build_segment(
		"Speed",
		speed_labels,
		speed_selected,
		meridian.color,
		"How fast moves and battles play out",
		"Pacing only — never changes an outcome",
		_on_speed_selected
	)
	speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(speed)
	return row


func _build_toggles_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var fog := _build_toggle(
		"Fog of war",
		_fog_on,
		"Hide the board beyond your units' sight",
		"Off shows the whole map",
		_on_fog_toggled
	)
	fog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fog)
	var anim := _build_toggle(
		"Battle animations",
		Settings.battle_animations,
		"Play the full-screen cut-in when an attack resolves",
		"Any key skips one in progress",
		_on_animations_toggled
	)
	anim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(anim)
	return row


func _build_action_stack(animate: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.custom_minimum_size = Vector2(UiTheme.ACTION_W, 0)

	var identity := UiTheme.menu_identity()
	_one_player_button = _action_button(
		"1 Player", "VS AI", UiTheme.ButtonVariant.PRIMARY, identity.theme(1)
	)
	_two_player_button = _action_button(
		"2 Player", "HOT-SEAT", UiTheme.ButtonVariant.PRIMARY, identity.theme(2)
	)
	col.add_child(_one_player_button)
	col.add_child(_two_player_button)

	_continue_button = _action_button("Continue", "", UiTheme.ButtonVariant.SECONDARY, null)
	col.add_child(_continue_button)
	# What Continue resumes, on its own line rather than as the button's inline
	# suffix: "DAY 12 · THE STRAITS" is longer than the 122px action stack can set
	# at button size, and a micro-label under the control is the panel's own idiom.
	#
	# It is also Continue's tip trigger. The button itself is the one control here
	# that can be disabled, and a disabled control is exactly where a tip is the
	# only affordance left — so the explanation hangs off the caption beneath it,
	# which stays hoverable either way. `_refresh_continue` sets the words.
	_continue_caption = _micro_label("")
	_continue_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue_caption.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_tip = Tooltip.attach(_continue_caption, "", "", Tooltip.Side.BOTTOM)
	# A disabled button takes no focus — the case the hoverable caption covers.
	_continue_tip.follow_focus(_continue_button)
	col.add_child(_continue_caption)

	_quit_button = _action_button("Quit", "", UiTheme.ButtonVariant.GHOST, null)
	col.add_child(_quit_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_child(_identity_chip(identity, 1, "P1"))
	chips.add_child(_identity_chip(identity, 2, "P2"))
	col.add_child(chips)

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


# --- widget builders ---------------------------------------------------------


## A faction-tinted or cream action button with an optional Silkscreen suffix
## ("VS AI", "HOT-SEAT") set a size down and dimmed, per the handoff.
func _action_button(
	text: String,
	suffix: String,
	variant: UiTheme.ButtonVariant,
	theme: CommanderVisuals.FactionTheme
) -> Button:
	var button := Button.new()
	button.text = text if suffix.is_empty() else "%s  %s" % [text, suffix]
	UiTheme.apply_button(button, variant, theme, UiTheme.SIZE_BUTTON)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 20)
	return button


## A segmented control: a Silkscreen micro-label over a bordered row of toggle
## buttons, the active one carrying the faction fill. Labels come straight from
## the authority that owns them (GameSpeed / DifficultyDB), never typed in, so the
## control can never disagree with the tiers it drives (plan section 2).
##
## The group's explanation hangs off the micro-label, not off the column or the
## segments: reaching for "Quick" is not asking what Speed means.
func _build_segment(
	micro: String,
	labels: PackedStringArray,
	selected: int,
	accent: Color,
	tip: String,
	tip_detail: String,
	on_select: Callable
) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	var group_tip := _tip_label(col, micro, tip, tip_detail)

	var frame := PanelContainer.new()
	var frame_box := UiTheme.flat(UiTheme.PAPER)
	frame_box.border_color = UiTheme.HARD_BORDER
	frame_box.set_border_width_all(UiTheme.BORDER)
	UiTheme.hard_shadow(frame_box)
	frame.add_theme_stylebox_override("panel", frame_box)
	col.add_child(frame)

	var seg_row := HBoxContainer.new()
	seg_row.add_theme_constant_override("separation", 0)
	frame.add_child(seg_row)

	var buttons: Array[Button] = []
	for i in labels.size():
		var seg := Button.new()
		seg.text = labels[i]
		seg.toggle_mode = true
		seg.clip_text = true
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.custom_minimum_size = Vector2(0, 18)
		seg.add_theme_font_override("font", UiTheme.display())
		seg.add_theme_font_size_override("font_size", UiTheme.SIZE_SEGMENT)
		group_tip.follow_focus(seg)  # focus lands here, never on the micro-label
		seg_row.add_child(seg)
		buttons.append(seg)

	var restyle := func(index: int) -> void:
		for i in buttons.size():
			_style_segment(buttons[i], i == index, i > 0, accent)
	restyle.call(selected)
	for i in labels.size():
		buttons[i].pressed.connect(
			func() -> void:
				restyle.call(i)
				on_select.call(i)
		)
	return col


func _style_segment(seg: Button, active: bool, divided: bool, accent: Color) -> void:
	var normal := UiTheme.segment_box(active, accent)
	if divided:
		normal.border_color = UiTheme.HARD_BORDER
		normal.border_width_left = UiTheme.BORDER
	seg.add_theme_stylebox_override("normal", normal)
	seg.add_theme_stylebox_override("hover", normal)
	seg.add_theme_stylebox_override("pressed", normal)
	seg.add_theme_stylebox_override("focus", UiTheme.focus_box())
	var fg := UiTheme.WHITE if active else UiTheme.INK
	seg.add_theme_color_override("font_color", fg)
	seg.add_theme_color_override("font_hover_color", fg)
	seg.add_theme_color_override("font_pressed_color", fg)
	seg.add_theme_color_override("font_focus_color", fg)


## A toggle row: a ✓-box (capture green on, grey off), a label, and a Silkscreen
## ON/OFF status. The whole row is one focusable button (handoff Toggle), so mouse,
## keyboard and controller all flip it — and, like a segmented group, its
## explanation hangs off the words rather than off the whole row.
func _build_toggle(
	text: String, is_on: bool, tip: String, tip_detail: String, on_change: Callable
) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = is_on
	button.custom_minimum_size = Vector2(0, 16)
	var ghost := UiTheme.flat(Color(0, 0, 0, 0))
	button.add_theme_stylebox_override("normal", ghost)
	button.add_theme_stylebox_override("hover", ghost)
	button.add_theme_stylebox_override("pressed", ghost)
	button.add_theme_stylebox_override("focus", UiTheme.focus_box())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(row)

	var check := Panel.new()
	check.custom_minimum_size = Vector2(12, 12)
	var mark := Label.new()
	mark.text = "✓"
	mark.add_theme_font_override("font", UiTheme.stat(true))
	mark.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	mark.add_theme_color_override("font_color", UiTheme.SLATE_900)
	mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check.add_child(mark)
	row.add_child(check)

	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.display())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	label.add_theme_color_override("font_color", UiTheme.INK)
	# Shrunk to its own string, so the underlined words and the hover target are
	# the same rect; the spacer below keeps ON/OFF hard right where FILL had it.
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The row is one focusable button, so that is where the tip's focus half goes.
	Tooltip.attach(label, tip, tip_detail, Tooltip.Side.BOTTOM).follow_focus(button)
	row.add_child(label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	var status := Label.new()
	status.add_theme_font_override("font", UiTheme.stat())
	status.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status)
	UiTheme.make_decoration(row)

	var repaint := func(on: bool) -> void:
		_paint_check(check, mark, on)
		status.text = "ON" if on else "OFF"
		status.add_theme_color_override("font_color", UiTheme.CAPTURE if on else UiTheme.NEUTRAL)
	repaint.call(is_on)
	button.toggled.connect(
		func(pressed: bool) -> void:
			repaint.call(pressed)
			on_change.call(pressed)
	)
	return button


func _paint_check(check: Panel, mark: Label, on: bool) -> void:
	var box := UiTheme.flat(UiTheme.CAPTURE if on else UiTheme.PAPER_2)
	box.border_color = UiTheme.HARD_BORDER
	box.set_border_width_all(UiTheme.BORDER)
	UiTheme.hard_shadow(box)
	check.add_theme_stylebox_override("panel", box)
	mark.visible = on


## A faction identity chip — a coloured dot and the default side's faction name,
## the classic meridian/aurora identities a commander-less match plays as. Speaks
## faction, never "Red"/"Blue" (faction-identity D5): the words are the theme's,
## the hue is CommanderVisuals', resolved through the default identity (plan D4).
func _identity_chip(identity: SideIdentity, team: int, role: String) -> Control:
	var theme := identity.theme(team)
	var chip := PanelContainer.new()
	var box := UiTheme.flat(UiTheme.PAPER)
	box.border_color = UiTheme.HARD_BORDER
	box.set_border_width_all(UiTheme.BORDER)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	UiTheme.hard_shadow(box)
	chip.add_theme_stylebox_override("panel", box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(6, 6)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_box := UiTheme.flat(theme.color)
	dot_box.border_color = UiTheme.HARD_BORDER
	dot_box.set_border_width_all(1)
	dot.add_theme_stylebox_override("panel", dot_box)
	row.add_child(dot)

	var label := Label.new()
	label.text = "%s · %s" % [String(theme.key).capitalize(), role]
	label.add_theme_font_override("font", UiTheme.stat())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	label.add_theme_color_override("font_color", UiTheme.INK)
	row.add_child(label)
	chip.add_child(row)
	return chip


# --- small helpers -----------------------------------------------------------


## A micro-label carrying its group's explanation, added to `into` in place: shrunk
## to its own string so the dotted underline, the hover target and the words are one
## rect, and opening downward so the tip lands inside the Match Setup panel rather
## than over the board behind it (handoff integration note 3). The tip comes back so
## the caller can mirror its focus half onto the group's own focusable control.
func _tip_label(into: Container, text: String, tip: String, tip_detail: String) -> Tooltip:
	var label := _micro_label(text)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	into.add_child(label)
	return Tooltip.attach(label, tip, tip_detail, Tooltip.Side.BOTTOM)


func _micro_label(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UiTheme.stat())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	label.add_theme_color_override("font_color", UiTheme.NEUTRAL_DARK)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## A thin ink divider between the panel's rows (handoff --border-soft).
func _rule() -> Control:
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.45)
	rule.custom_minimum_size = Vector2(0, UiTheme.BORDER)
	return rule


func _pad(child: Control, h: int, v: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", h)
	margin.add_theme_constant_override("margin_right", h)
	margin.add_theme_constant_override("margin_top", v)
	margin.add_theme_constant_override("margin_bottom", v)
	margin.add_child(child)
	return margin


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
	var box := UiTheme.flat(UiTheme.PAPER_RAISED if selected else Color(0, 0, 0, 0))
	box.set_corner_radius_all(UiTheme.RADIUS)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	if selected:
		box.border_color = meridian.color
		box.set_border_width_all(UiTheme.PANEL_BORDER)
		UiTheme.hard_shadow(box)
	cell.add_theme_stylebox_override("normal", box)
	cell.add_theme_stylebox_override("hover", box if selected else _cell_hover_box())
	cell.add_theme_stylebox_override("pressed", box)
	cell.add_theme_stylebox_override("focus", UiTheme.focus_box())
	name_label.text = (
		"%s ✓" % MapCatalog.display_name(_maps[index].source_path)
		if selected
		else MapCatalog.display_name(_maps[index].source_path)
	)
	name_label.add_theme_color_override("font_color", UiTheme.INK if selected else UiTheme.NEUTRAL)


func _cell_hover_box() -> StyleBoxFlat:
	var box := UiTheme.flat(
		Color(UiTheme.PAPER_RAISED.r, UiTheme.PAPER_RAISED.g, UiTheme.PAPER_RAISED.b, 0.35)
	)
	box.set_corner_radius_all(UiTheme.RADIUS)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


## The header-right name·size, read off the board itself so no hand-kept table can
## drift from it. The per-cell tooltip carries property count and the blurb.
func _refresh_map_facts() -> void:
	var map := _map_at(_selected_map)
	if map == null:
		_map_header.text = ""
		return
	_map_header.text = (
		"%s · %d×%d" % [MapCatalog.display_name(map.source_path), map.width, map.height]
	)


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


# --- flow (unchanged) --------------------------------------------------------


## Opens the selection page for the chosen mode, hiding the menu behind it so no
## focus or click leaks through to the buttons underneath.
func _open_select(ai_teams: Array[int]) -> void:
	_pending_ai_teams = ai_teams
	_menu_root.hide()
	_select_panel.begin(not ai_teams.is_empty())


func _on_selection_confirmed(red_id: StringName, blue_id: StringName) -> void:
	_start(_pending_ai_teams, false, {1: red_id, 2: blue_id})


func _on_selection_cancelled() -> void:
	_menu_root.show()
	_one_player_button.grab_focus()


## Names the saved match under the Continue button, so the menu alone answers
## "is this the match I meant?" — the whole point of labelling the slot. The day
## and board are read off the save envelope's own keys (SaveGame.peek); nothing is
## rebuilt, and the save format is untouched.
##
## Continue now follows the summary rather than the file's mere existence. That is
## strictly narrower: `decode` refuses everything `summarize` refuses, so a save
## we cannot name is one Continue could only have failed on.
func _refresh_continue() -> void:
	var summary := (
		_capture_driver.posed_slot(_maps) if _capture_driver.poses_slot() else SaveGame.peek()
	)
	_continue_button.disabled = summary == null
	if summary == null:
		_continue_caption.text = "NO SAVED MATCH"
		# The dim NEUTRAL_DARK of PRESS START: it explains a disabled button, so it
		# must not read as loudly as a match waiting to be resumed.
		_continue_caption.add_theme_color_override("font_color", UiTheme.NEUTRAL_DARK)
		_continue_tip.set_copy("Nothing saved yet", "Save in battle from the map menu")
		return
	var label := summary.label()
	_continue_caption.text = label.to_upper()
	# The tagline's tone, which is what a micro-label needs to carry a fact rather
	# than a hint on the dark backdrop — NEUTRAL_DARK is barely legible out here.
	_continue_caption.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	# The caption already names the day and board, so the tip does not repeat them.
	_continue_tip.set_copy("Resume the saved match", "Its own board and commanders apply")


func _continue() -> void:
	# The saved match applies its own map, commanders and AI sides.
	_start([] as Array[int], true, {})


## `load_save` resumes the saved match (its own map, commanders, AI sides and
## difficulty apply, so the choices above are ignored).
func _start(ai_teams: Array[int], load_save: bool, commanders: Dictionary) -> void:
	var map := _map_at(_selected_map)
	if map != null:
		MatchConfig.map_path = map.source_path
	MatchConfig.ai_teams = ai_teams
	MatchConfig.fog_enabled = _fog_on
	MatchConfig.difficulty = _selected_difficulty()
	MatchConfig.commanders = commanders
	MatchConfig.load_save = load_save
	get_tree().change_scene_to_file(BATTLE_SCENE)


# --- dev captures ------------------------------------------------------------


## What a capture measures itself against: the whole centered stack, plus every
## primary action by name. See MenuCaptureDriver._fits for why it is both.
func _chrome() -> Dictionary:
	return {
		"the menu column": _column,
		"1 Player": _one_player_button,
		"2 Player": _two_player_button,
		"Continue": _continue_button,
		"Quit": _quit_button,
	}
