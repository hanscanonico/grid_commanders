class_name CampaignHubPanel
extends Control
## One campaign's mission path: which are open, which are cleared, and what each
## one is about. `CampaignPickerPanel`'s sibling and the page a campaign is
## actually played from.
##
## It is the hub **and** the briefing, in two views of one panel rather than two
## panels. Picking a mission swaps the list for its briefing and Back swaps it
## home again — so "read what this is, then deploy" costs no scene change, and
## the one thing a player does over and over in a campaign is the cheapest thing
## the page does.
##
## The briefing is read **over the board it is about**: the mission's own map,
## baked by `MapThumbnail` — the one renderer the picker's miniatures and the
## menu's drifting field already share, so the establishing shot can never be a
## second opinion about the ground — under a scrim, with the generals talking in a
## band docked at the bottom. The war's own header comes down while it is up,
## because the campaign's tally is the list's context and not this mission's.
##
## Locking is read from the profile, never inferred from the list: a mission is
## open because `CampaignState` says so, and one the route went past without
## opening says so too — a road not taken reads differently from ground nobody
## has reached. Missions are shown grouped under their block titles, which is why
## `CampaignDefinition` carries them.
##
## The strip under the title is the war's own state: what the ledger has recorded,
## in the words the beats that wrote it used, and what is left of the army the war
## carries. Both are handed over already settled — the notes by
## `CampaignDefinition.ledger_notes`, the army by `CampaignState.roster` — and a
## war that has recorded nothing and carries nobody draws no strip at all.

signal deployed(mission_id: StringName)
signal cancelled

const _ROW_HEIGHT := 26
const _ROW_WIDTH := 420
const _ROW_INSET := 6
const _BUST := 44
## How dark the scrim over the establishing shot runs, top to bottom: enough to
## read a title against at the top, enough to sit the speech band on at the foot.
const _SCRIM_TOP := 0.55
const _SCRIM_BOTTOM := 0.8
## Canvas px per cell the board behind a briefing is baked at. The bake is at full
## atlas resolution whatever this is, so the ceiling only bounds the texture a
## pocket-sized board is resized to; the floor keeps the widest board in the game
## legible rather than exact.
const _BOARD_TILE_MIN := 4
const _BOARD_TILE_MAX := 32
## The band the dialogue is docked in. Fixed so every mission's briefing keeps the
## same shape and the same amount of board showing above it; a longer conversation
## scrolls rather than eating the picture.
const _SPEECH_H := 96
## The foot of the page the shot stays out of, so the whole board is read above
## the conversation about it rather than half of it behind one. Measured off the
## band a three-term briefing actually draws — the ordinary mission — rather than
## guessed: at 170 the band's own top sat 36px inside the shot and every board
## lost its last two rows, the player's own corner among them. A mission whose
## terms run longer than that still covers the shot's last rows; the shot is
## centred in what is left, so a shorter band leaves dark rather than a seam.
const _BOARD_FOOT := 206

var _title: Label
var _subtitle: Label
var _war: VBoxContainer
## The war's own header — title, tally, the war so far — down while a briefing is
## up so the board behind it is not read through the campaign's scoreboard.
var _header: VBoxContainer
var _board: Control
var _board_art: TextureRect
var _list_view: VBoxContainer
var _list_scroll: ScrollContainer
var _rows: VBoxContainer
var _brief_view: VBoxContainer
var _brief_title: Label
var _brief_where: Label
var _brief_picture: HBoxContainer
var _brief_body: VBoxContainer
var _brief_terms: VBoxContainer
var _deploy_button: Button
var _back_button: Button
var _brief_back: Button
var _row_buttons: Array[Button] = []
var _ids: Array[StringName] = []

var _commanders := CommanderDB.load_default()
var _units := UnitDB.load_default()
var _terrain := TerrainDB.load_default()
var _campaign: CampaignDefinition
var _progress: CampaignState
var _showing: StringName = &""
## The mission whose saved board the profile holds, or "" — what turns its
## Deploy into a Resume. Read once at `begin`, because it is a disk fact.
var _resume_mission: StringName = &""


func _ready() -> void:
	_build()
	hide()


## Opens the hub on a campaign and the progress recorded for it.
func begin(campaign: CampaignDefinition, progress: CampaignState) -> void:
	_campaign = campaign
	_progress = progress
	_resume_mission = &""
	if progress.active_mission != &"" and not CampaignProfile.load_battle(campaign.id).is_empty():
		_resume_mission = progress.active_mission
	_title.text = campaign.title.to_upper()
	# Out of the missions this war still offers, not out of the list: a road the
	# route did not take can never be cleared, and a count nobody can finish is a
	# campaign that always reads unfinished.
	_subtitle.text = (
		"%d of %d cleared · %d stars"
		% [progress.records.size(), progress.offered_count(campaign), progress.total_stars()]
	)
	_fill_war()
	_fill()
	_show_list()
	show()


func chrome() -> Dictionary[String, Control]:
	var named: Dictionary[String, Control] = {"the campaign title": _title}
	if _brief_view.visible:
		named["Deploy"] = _deploy_button
		named["the briefing title"] = _brief_title
	else:
		named["Back"] = _back_button
		if not _row_buttons.is_empty():
			named["the mission row in hand"] = _shown_row()
	return named


## The row the list is actually showing, which is the row focus landed on. A
## half-played war scrolls its earlier missions above the viewport on purpose, so
## row zero witnesses nothing about whether the page fits its frame.
func _shown_row() -> Button:
	for button in _row_buttons:
		if button.has_focus():
			return button
	return _row_buttons[0]


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cancel"):
		get_viewport().set_input_as_handled()
		if _brief_view.visible:
			_show_list()
		else:
			_leave()


# --- build -------------------------------------------------------------------


func _build() -> void:
	UiKit.page_veil(self)

	_board = _build_board()
	add_child(_board)

	var main := UiKit.page_body(self, 5)

	_header = VBoxContainer.new()
	_header.add_theme_constant_override("separation", 5)
	main.add_child(_header)

	_title = UiKit.page_title()
	_header.add_child(_title)

	_subtitle = UiKit.page_note("")
	_header.add_child(_subtitle)

	_war = VBoxContainer.new()
	_war.add_theme_constant_override("separation", 1)
	_header.add_child(_war)

	_list_view = VBoxContainer.new()
	_list_view.add_theme_constant_override("separation", 5)
	_list_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_list_view)
	_build_list(_list_view)

	_brief_view = VBoxContainer.new()
	_brief_view.add_theme_constant_override("separation", 5)
	_brief_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_brief_view)
	_build_briefing(_brief_view)

	main.add_child(
		UiKit.key_legend("UP/DOWN  BROWSE      ENTER  OPEN      ESC  BACK      MOUSE OK")
	)


## The establishing shot the briefing is read over: the mission's board, filling
## the page, under a scrim that darkens toward the foot so the speech band and the
## terms sit on ink rather than on grass. Down for the list, which is the war's
## page and not one mission's.
func _build_board() -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.clip_contents = true
	layer.hide()

	_board_art = TextureRect.new()
	_board_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_board_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_board_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_art.offset_bottom = -_BOARD_FOOT
	_board_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_board_art)

	var gradient := Gradient.new()
	gradient.set_color(0, UiTheme.veil(_SCRIM_TOP))
	gradient.set_color(1, UiTheme.veil(_SCRIM_BOTTOM))
	var wash := GradientTexture2D.new()
	wash.gradient = gradient
	wash.fill_from = Vector2.ZERO
	wash.fill_to = Vector2(0, 1)
	var scrim := TextureRect.new()
	scrim.texture = wash
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.offset_bottom = -_BOARD_FOOT
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(scrim)

	# The face is pinned to the shot's own corner rather than stacked above it: in
	# the flow it sat in the middle of the board it is standing on.
	var corner := MarginContainer.new()
	corner.set_anchors_preset(Control.PRESET_FULL_RECT)
	corner.offset_bottom = -_BOARD_FOOT
	corner.add_theme_constant_override("margin_right", UiTheme.PAGE_MARGIN)
	corner.add_theme_constant_override("margin_top", UiTheme.PAGE_MARGIN)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(corner)

	_brief_picture = HBoxContainer.new()
	_brief_picture.alignment = BoxContainer.ALIGNMENT_END
	_brief_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_child(_brief_picture)
	return layer


func _build_list(parent: VBoxContainer) -> void:
	_list_scroll = UiKit.vscroll()
	# Without it the list stays where it was while the keyboard walks off the page,
	# so from mission eleven on Enter deploys a mission nobody can see.
	_list_scroll.follow_focus = true
	parent.add_child(_list_scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_rows)

	_back_button = UiKit.action_button("Back", "", UiTheme.ButtonVariant.GHOST, null, _ROW_WIDTH)
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(_leave)
	parent.add_child(_back_button)


func _build_briefing(parent: VBoxContainer) -> void:
	_brief_title = Label.new()
	_brief_title.add_theme_font_override("font", UiTheme.display(true))
	_brief_title.add_theme_font_size_override("font_size", 12)
	_brief_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(_brief_title)

	_brief_where = UiKit.page_note("")
	parent.add_child(_brief_where)

	# Open ground between the title block and the band: the board showing through
	# it is the point of the page, so it takes whatever height is left over.
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gap)

	var band := PanelContainer.new()
	var box := UiTheme.dark_panel_box()
	box.set_content_margin_all(UiTheme.GAP)
	band.add_theme_stylebox_override("panel", box)
	band.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(band)

	var docked := VBoxContainer.new()
	docked.add_theme_constant_override("separation", 5)
	band.add_child(docked)

	var frame := ScrollContainer.new()
	frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.follow_focus = true
	frame.custom_minimum_size.y = _SPEECH_H
	docked.add_child(_column(frame))

	_brief_body = VBoxContainer.new()
	_brief_body.add_theme_constant_override("separation", 4)
	_brief_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(_brief_body)

	# The terms sit outside the scroll, between the dialogue and Deploy: what the
	# player is agreeing to has to be on the page at the moment they agree to it.
	_brief_terms = VBoxContainer.new()
	_brief_terms.add_theme_constant_override("separation", 2)
	docked.add_child(_column(_brief_terms))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(buttons)

	_deploy_button = UiKit.action_button("Deploy", "", UiTheme.ButtonVariant.PRIMARY, null, 120)
	_deploy_button.pressed.connect(_deploy)
	buttons.add_child(_deploy_button)

	_brief_back = UiKit.action_button("Back", "", UiTheme.ButtonVariant.GHOST, null, 90)
	_brief_back.pressed.connect(_show_list)
	buttons.add_child(_brief_back)


## Pins a briefing row to the one reading column `MissionSpeech` already lays
## dialogue out in, so the picture, the words and the terms cannot disagree about
## where the page's edges are and nothing shifts between two missions.
func _column(control: Control) -> Control:
	control.custom_minimum_size.x = MissionSpeech.WIDTH
	control.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return control


func _body_line(text: String, dim: bool = false) -> Label:
	return MissionSpeech.paragraph(text, dim)


# --- the war so far ----------------------------------------------------------


## What this war has recorded and what it still has to fight with. Hidden whole
## when there is neither, which is every campaign until a mission writes one — so
## a war that has not started yet shows the list and nothing else.
func _fill_war() -> void:
	for child in _war.get_children():
		child.queue_free()
	var notes := _campaign.ledger_notes(_progress)
	var army := _army_line()
	_war.visible = not notes.is_empty() or army != ""
	if not _war.visible:
		return
	_war.add_child(UiKit.page_note("THE WAR SO FAR"))
	for note: String in notes:
		_war.add_child(UiKit.page_note(note))
	if army != "":
		_war.add_child(UiKit.page_note("VETERANS   %s" % army))


## The army the war carries, as condition and identity — "TANK 40 · RECON 55" —
## or "" outside a chain, which is where most of a campaign is spent.
func _army_line() -> String:
	var standing: Array[String] = []
	for carried: CarriedUnit in _progress.roster:
		var type := _units.by_id(carried.unit_id)
		var named := type.display_name if type != null else String(carried.unit_id)
		standing.append("%s %d" % [named.to_upper(), carried.hp])
	return " · ".join(standing)


# --- the list ----------------------------------------------------------------


## Which blocks the list deals mission by mission. A block is expanded when any
## of its missions is open — the block the route is on and every one behind it —
## and collapsed to a single summary row otherwise, so a war reads as a route
## rather than as two dozen grey bars. Block 0 is always expanded, so a fresh
## profile opens on its first missions rather than on nothing at all.
##
## Static and argument-taking, so the shape of a war is read without the page.
static func expanded_blocks(
	campaign: CampaignDefinition, progress: CampaignState
) -> Dictionary[int, bool]:
	var expanded: Dictionary[int, bool] = {0: true}
	for mission: MissionDefinition in campaign.missions:
		if mission == null or not progress.is_unlocked(mission.id):
			continue
		var block := campaign.block_of(mission.id)
		if block >= 0:
			expanded[block] = true
	return expanded


func _fill() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_row_buttons.clear()
	_ids.clear()
	var expanded := expanded_blocks(_campaign, _progress)
	var block := -1
	for index in _campaign.missions.size():
		var mission: MissionDefinition = _campaign.missions[index]
		var at := _campaign.block_of(mission.id)
		var titled := at >= 0 and at < _campaign.block_titles.size()
		var collapsed: bool = titled and not expanded.get(at, false)
		if at != block and titled:
			block = at
			_rows.add_child(
				(
					_block_summary(at)
					if collapsed
					else UiKit.page_note(_campaign.block_titles[at].to_upper())
				)
			)
		if collapsed:
			continue
		var button := Button.new()
		var open := _progress.is_unlocked(mission.id)
		button.disabled = not open
		UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY, null, UiTheme.SIZE_BUTTON)
		button.custom_minimum_size = Vector2(_ROW_WIDTH, _ROW_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.add_child(_row_face(index, mission, open))
		var slot := _ids.size()
		button.pressed.connect(func() -> void: _open_briefing(slot))
		_rows.add_child(button)
		_row_buttons.append(button)
		_ids.append(mission.id)


## A block nobody has reached, in one row: its title, how long it is and the one
## word that matters. Appended to the rows and to neither `_ids` nor
## `_row_buttons` — the two stay index-parallel, and a summary row names no
## mission to focus or deploy.
##
## The count is the block's AUTHORED length, deliberately not a route count:
## `CampaignState.offered_count` stays the route's answer, and this row is about
## the shape of the war rather than about what is left of it.
func _block_summary(block: int) -> Button:
	var button := Button.new()
	button.disabled = true
	UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY, null, UiTheme.SIZE_BUTTON)
	button.custom_minimum_size = Vector2(_ROW_WIDTH, _ROW_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var face := ListRow.face(_ROW_INSET)
	var title := _campaign.block_titles[block].to_upper()
	var length: int = _campaign.block_lengths[block]
	face.add_child(ListRow.cell("%s   ·   0/%d   ·   LOCKED" % [title, length], _locked_ink()))
	button.add_child(face)
	return button


## The words a row nobody has reached wears. A row is drawn on the face of a
## disabled SECONDARY button, so it takes that button's own muted label rather
## than a lighter grey of its own: the disabled plate is opaque, and a row that
## dimmed itself by going lighter than the plate went with it.
static func _locked_ink() -> Color:
	var plate := DisabledPalette.plate(UiTheme.PAPER, UiTheme.HARD_BORDER)
	return DisabledPalette.label(UiTheme.INK, plate)


## The row as columns rather than a padded string: mark, number and title on the
## left, the stars in a fixed right-hand cell so they line up down the page. The
## four states read at a glance — cleared wears a green check and gold stars, an
## open row shows the hollow stars still on offer, locked and not-taken dim to
## their words. Children of a disabled button, so every child ignores the mouse.
##
## Only an open row carries its second line and its fog chip: what the fight is
## and where it is are the mission's own facts to give away, and a road nobody
## has reached must not leak them.
func _row_face(index: int, mission: MissionDefinition, open: bool) -> Control:
	var face := ListRow.face(_ROW_INSET)
	var cleared := open and _progress.is_cleared(mission.id)
	var skipped := not open and _progress.is_skipped(_campaign, mission.id)
	var ink := UiTheme.INK if open else _locked_ink()
	if cleared:
		face.add_child(ListRow.cell("✓", UiTheme.CAPTURE))
	var words := ListRow.words()
	var title := ListRow.cell("%02d · %s" % [index + 1, mission.title], ink)
	title.clip_text = true
	words.add_child(title)
	if open:
		var record: CampaignState.MissionRecord = _progress.records.get(mission.id)
		var detail := row_detail(mission, _commanders, record)
		if detail != "":
			var line := ListRow.detail(detail, UiTheme.INK_3)
			line.clip_text = true
			words.add_child(line)
	face.add_child(words)
	if not open:
		face.add_child(ListRow.cell("NOT TAKEN" if skipped else "LOCKED", _locked_ink()))
		return face
	if mission.fog_enabled:
		face.add_child(ListRow.cell("FOG", UiTheme.AMMO))
	var most := MissionRuntime.new(mission).max_stars()
	var earned := _progress.stars_for(mission.id) if cleared else 0
	if earned > 0:
		face.add_child(ListRow.cell("★".repeat(earned), UiTheme.SELECT_GOLD))
	if most - earned > 0:
		face.add_child(ListRow.cell("☆".repeat(most - earned), UiTheme.INK_3))
	return face


## A row's second line: where the fight is, who it is against, the day it is
## rated on and the day this player already reached. Every part is omitted when
## the mission does not state it, so a row says only what it has.
##
## Static and argument-taking so it can be read without the page and without a
## profile on disk — `CampaignPickerPanel.row_text`'s shape, for its reason.
static func row_detail(
	mission: MissionDefinition, commanders: CommanderDB, record: CampaignState.MissionRecord
) -> String:
	var parts: Array[String] = []
	if mission.location != "":
		parts.append(mission.location.to_upper())
	var foe := _antagonist(mission, commanders)
	if foe != null:
		parts.append("VS %s" % foe.display_name.to_upper())
	if mission.par_day > 0:
		parts.append("PAR %d" % mission.par_day)
	if record != null and record.best_day > 0:
		parts.append("BEST %d" % record.best_day)
	return "   ·   ".join(parts)


# --- the briefing ------------------------------------------------------------


func _open_briefing(slot: int) -> void:
	if slot < 0 or slot >= _ids.size():
		return
	var mission := _campaign.mission(_ids[slot])
	if mission == null or not _progress.is_unlocked(mission.id):
		return
	_showing = mission.id
	_brief_title.text = mission.title.to_upper()
	_brief_where.text = mission.location
	_fill_picture(mission)
	# The word has to name what pressing it does: the mission the profile is
	# midway through picks its saved board back up rather than starting over.
	_deploy_button.text = "Resume" if mission.id == _resume_mission else "Deploy"
	for child in _brief_body.get_children():
		child.queue_free()
	# The briefing is read against the war so far, so a mission that has a
	# different opening after a different mission five gets it (campaign-depth D5).
	for line: MissionLine in MissionLine.spoken(mission.briefing, _progress):
		_brief_body.add_child(MissionSpeech.render(line, _commanders))
	_fill_terms(mission)
	_show_briefing()


## What the mission is won and lost on, drawn where scrolling cannot take it
## away. Hidden whole when a mission states none, so the page keeps its shape.
##
## A held-back condition is not one of the terms: `is_live` is the one answer to
## whether an objective is being judged yet, asked here with no tally because a
## briefing is read before the mission opens and nothing has been revealed. The
## in-battle card asks the same authority, so the two surfaces cannot disagree
## about which conditions the player has been told.
func _fill_terms(mission: MissionDefinition) -> void:
	for child in _brief_terms.get_children():
		child.queue_free()
	var terms: Array[String] = []
	for objective in mission.objectives:
		if objective != null and objective.text != "" and objective.is_live(null):
			terms.append("OBJECTIVE   %s" % objective.text)
	for failure in mission.failures:
		if failure != null and failure.text != "" and failure.is_live(null):
			terms.append("FAILURE   %s" % failure.text)
	for bonus in mission.bonus_objectives:
		if bonus != null and bonus.text != "" and bonus.is_live(null):
			terms.append("BONUS STAR   %s" % bonus.text)
	if mission.par_day > 0:
		terms.append("PAR STAR   Finish by day %d." % mission.par_day)
	_brief_terms.visible = not terms.is_empty()
	if not _brief_terms.visible:
		return
	# The dialogue is cut off wherever the scroll happens to end, so the terms need
	# a line of their own to read as the page rather than as more of it.
	_brief_terms.add_child(_column(UiKit.rule()))
	for term in terms:
		_brief_terms.add_child(_body_line(term, true))


## The briefing's picture: where the fight is, behind everything, and against whom,
## in the one card over it. The face is the first enemy seat's commander, resolved
## by the authorities every other surface uses.
func _fill_picture(mission: MissionDefinition) -> void:
	for child in _brief_picture.get_children():
		_brief_picture.remove_child(child)
		child.queue_free()
	_fill_board(MapData.load_from_file(mission.map_path, _terrain))
	var foe := _antagonist(mission, _commanders)
	if foe != null:
		_brief_picture.add_child(_foe_card(foe))


## Bakes the mission's board to the layer behind the briefing. The whole board is
## in the shot — where the fight is is what a briefing is for — at the largest
## whole tile the page can hold, so it is never scaled up past the pixels it was
## baked with. A board with no file behind it leaves the page on its plain veil
## rather than on the last mission's ground.
func _fill_board(map: MapData) -> void:
	if map == null:
		_board_art.texture = null
		return
	var view := get_viewport_rect().size
	var fit := minf(view.x / float(map.width), (view.y - _BOARD_FOOT) / float(map.height))
	var tile := clampi(floori(fit), _BOARD_TILE_MIN, _BOARD_TILE_MAX)
	_board_art.texture = MapThumbnail.bake(map, UiTheme.menu_identity(map.player_count()), tile)


## The first hostile seat's commander. Hostility is read by side, the way every
## objective reads it: an empty grouping is a free-for-all where every computer
## seat is a foe, and a seat standing with the player is an ally, never the face
## the briefing is set against.
static func _antagonist(mission: MissionDefinition, commanders: CommanderDB) -> CommanderType:
	for team: int in mission.ai_teams:
		var allied: bool = (
			mission.sides.has(team)
			and mission.sides.has(mission.player_team)
			and mission.sides[team] == mission.sides[mission.player_team]
		)
		if allied:
			continue
		var commander := commanders.by_id(mission.commanders.get(team, &""))
		if commander != null:
			return commander
	return null


func _foe_card(commander: CommanderType) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var bust := MissionSpeech.bust_of(commander, _BUST)
	bust.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_child(bust)
	card.add_child(UiKit.page_note("VS %s" % commander.display_name.to_upper()))
	return card


func _show_list() -> void:
	_brief_view.hide()
	_board.hide()
	_header.show()
	_list_view.show()
	_showing = &""
	if _row_buttons.is_empty():
		_back_button.grab_focus()
	else:
		_focus_first_open()


func _show_briefing() -> void:
	_list_view.hide()
	_header.hide()
	_board.show()
	_brief_view.show()
	_deploy_button.grab_focus()


## Lands on the mission a returning player would want, which is the first one
## still open to them rather than the top of a list they have half finished.
func _focus_first_open() -> void:
	for index in _row_buttons.size():
		if not _row_buttons[index].disabled and not _progress.is_cleared(_ids[index]):
			_focus_row(_row_buttons[index])
			return
	for button in _row_buttons:
		if not button.disabled:
			_focus_row(button)
			return
	_back_button.grab_focus()


## The rows are dealt and focused in one go, so the list has not been laid out
## when the focus lands and `follow_focus` would scroll to a row still sitting at
## the container's origin. Deferred, the scroll runs on the settled page.
func _focus_row(button: Button) -> void:
	button.grab_focus()
	_list_scroll.ensure_control_visible.call_deferred(button)


func _deploy() -> void:
	if _showing == &"":
		return
	hide()
	deployed.emit(_showing)


func _leave() -> void:
	hide()
	cancelled.emit()


## Dev captures only: opens the briefing of the first mission on the list, so the
## page's other half can be photographed. Not on any play path.
func debug_open_first() -> void:
	if not _ids.is_empty():
		_open_briefing(0)
