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

const _TITLE_SIZE := 15
const _ROW_HEIGHT := 18
const _ROW_WIDTH := 420

var _title: Label
var _subtitle: Label
var _war: VBoxContainer
var _list_view: VBoxContainer
var _rows: VBoxContainer
var _brief_view: VBoxContainer
var _brief_title: Label
var _brief_where: Label
var _brief_body: VBoxContainer
var _deploy_button: Button
var _back_button: Button
var _brief_back: Button
var _row_buttons: Array[Button] = []
var _ids: Array[StringName] = []

var _commanders := CommanderDB.load_default()
var _units := UnitDB.load_default()
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
			named["the first mission row"] = _row_buttons[0]
	return named


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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.veil(0.985)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	add_child(margin)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 5)
	margin.add_child(main)

	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.display(true))
	_title.add_theme_font_size_override("font_size", _TITLE_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_title)

	_subtitle = _note("")
	main.add_child(_subtitle)

	_war = VBoxContainer.new()
	_war.add_theme_constant_override("separation", 1)
	main.add_child(_war)

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

	var footer := Label.new()
	footer.add_theme_font_override("font", UiTheme.stat())
	footer.add_theme_font_size_override("font_size", 8)
	footer.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	footer.text = "UP/DOWN  BROWSE      ENTER  OPEN      ESC  BACK      MOUSE OK"
	main.add_child(footer)


func _build_list(parent: VBoxContainer) -> void:
	var frame := ScrollContainer.new()
	frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(_rows)

	_back_button = Button.new()
	_back_button.text = "Back"
	UiTheme.apply_button(_back_button, UiTheme.ButtonVariant.GHOST, null, UiTheme.SIZE_BUTTON)
	_back_button.custom_minimum_size = Vector2(_ROW_WIDTH, 20)
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(_leave)
	parent.add_child(_back_button)


func _build_briefing(parent: VBoxContainer) -> void:
	_brief_title = Label.new()
	_brief_title.add_theme_font_override("font", UiTheme.display(true))
	_brief_title.add_theme_font_size_override("font_size", 12)
	_brief_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(_brief_title)

	_brief_where = _note("")
	parent.add_child(_brief_where)

	var frame := ScrollContainer.new()
	frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)

	_brief_body = VBoxContainer.new()
	_brief_body.add_theme_constant_override("separation", 4)
	_brief_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(_brief_body)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(buttons)

	_deploy_button = Button.new()
	_deploy_button.text = "Deploy"
	UiTheme.apply_button(_deploy_button, UiTheme.ButtonVariant.PRIMARY, null, UiTheme.SIZE_BUTTON)
	_deploy_button.custom_minimum_size = Vector2(120, 20)
	_deploy_button.pressed.connect(_deploy)
	buttons.add_child(_deploy_button)

	_brief_back = Button.new()
	_brief_back.text = "Back"
	UiTheme.apply_button(_brief_back, UiTheme.ButtonVariant.GHOST, null, UiTheme.SIZE_BUTTON)
	_brief_back.custom_minimum_size = Vector2(90, 20)
	_brief_back.pressed.connect(_show_list)
	buttons.add_child(_brief_back)


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.stat())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	label.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


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
	_war.add_child(_note("THE WAR SO FAR"))
	for note: String in notes:
		_war.add_child(_note(note))
	if army != "":
		_war.add_child(_note("VETERANS   %s" % army))


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


func _fill() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_row_buttons.clear()
	_ids.clear()
	var block := -1
	for index in _campaign.missions.size():
		var mission: MissionDefinition = _campaign.missions[index]
		var at := _campaign.block_of(mission.id)
		if at != block and at >= 0 and at < _campaign.block_titles.size():
			block = at
			_rows.add_child(_note(_campaign.block_titles[at].to_upper()))
		var button := Button.new()
		var open := _progress.is_unlocked(mission.id)
		button.text = _row_text(index, mission, open)
		button.disabled = not open
		UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY, null, UiTheme.SIZE_BUTTON)
		button.custom_minimum_size = Vector2(_ROW_WIDTH, _ROW_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var slot := _ids.size()
		button.pressed.connect(func() -> void: _open_briefing(slot))
		_rows.add_child(button)
		_row_buttons.append(button)
		_ids.append(mission.id)


## "03 · The Long Watch          ★★☆", or a row the player cannot play that says
## why. Stars are drawn rather than counted in words because the row is scanned,
## not read.
func _row_text(index: int, mission: MissionDefinition, open: bool) -> String:
	var number := "%02d" % (index + 1)
	if not open:
		var skipped := _progress.is_skipped(_campaign, mission.id)
		return "%s · %s   —   %s" % [number, mission.title, "not taken" if skipped else "locked"]
	if not _progress.is_cleared(mission.id):
		return "%s · %s" % [number, mission.title]
	var earned := _progress.stars_for(mission.id)
	var most := MissionRuntime.new(mission).max_stars()
	var stars := "★".repeat(earned) + "☆".repeat(maxi(0, most - earned))
	return "%s · %s   %s" % [number, mission.title, stars]


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
	# The word has to name what pressing it does: the mission the profile is
	# midway through picks its saved board back up rather than starting over.
	_deploy_button.text = "Resume" if mission.id == _resume_mission else "Deploy"
	for child in _brief_body.get_children():
		child.queue_free()
	# The briefing is read against the war so far, so a mission that has a
	# different opening after a different mission five gets it (campaign-depth D5).
	for line: MissionLine in MissionLine.spoken(mission.briefing, _progress):
		_brief_body.add_child(MissionSpeech.render(line, _commanders))
	_brief_body.add_child(_body_line(""))
	for objective in mission.objectives:
		if objective != null and objective.text != "":
			_brief_body.add_child(_body_line("OBJECTIVE   %s" % objective.text, true))
	for failure in mission.failures:
		if failure != null and failure.text != "":
			_brief_body.add_child(_body_line("FAILURE   %s" % failure.text, true))
	for bonus in mission.bonus_objectives:
		if bonus != null and bonus.text != "":
			_brief_body.add_child(_body_line("BONUS STAR   %s" % bonus.text, true))
	if mission.par_day > 0:
		_brief_body.add_child(_body_line("PAR STAR   Finish by day %d." % mission.par_day, true))
	_show_briefing()


func _show_list() -> void:
	_brief_view.hide()
	_list_view.show()
	_showing = &""
	if _row_buttons.is_empty():
		_back_button.grab_focus()
	else:
		_focus_first_open()


func _show_briefing() -> void:
	_list_view.hide()
	_brief_view.show()
	_deploy_button.grab_focus()


## Lands on the mission a returning player would want, which is the first one
## still open to them rather than the top of a list they have half finished.
func _focus_first_open() -> void:
	for index in _row_buttons.size():
		if not _row_buttons[index].disabled and not _progress.is_cleared(_ids[index]):
			_row_buttons[index].grab_focus()
			return
	for button in _row_buttons:
		if not button.disabled:
			button.grab_focus()
			return
	_back_button.grab_focus()


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
