class_name CampaignPickerPanel
extends Control
## The six campaigns, shown over the main menu without tearing it down —
## `ReplayPickerPanel`'s sibling, built the same way and for the same reason: a
## Back has to land on the setup exactly as it was left.
##
## Each row names a campaign and how far its own profile has got, because
## progress is per campaign (`CampaignProfile` keeps one file each) and a player
## returning after a week needs the menu to answer "which one was I in?" without
## opening any of them.
##
## It reads campaigns and profiles and hands back an id. It never starts a
## battle and never touches `core/` beyond the two registries it asks.

signal picked(campaign_id: StringName)
signal cancelled

const _TITLE_SIZE := 15
const _ROW_HEIGHT := 22
const _ROW_WIDTH := 400

var _title: Label
var _rows: VBoxContainer
var _empty: Label
var _back_button: Button
var _row_buttons: Array[Button] = []
var _ids: Array[StringName] = []


func _ready() -> void:
	_build()
	hide()


## Opens the page on a roster of campaigns. Handed in rather than read here for
## `ReplayPickerPanel.begin`'s reason: a photographed frame must not depend on
## what the machine that took it happens to have on disk. `posed` is the same
## rule applied to the other half of a row — a capture hands in the war it wants
## photographed, and every campaign it does not name is read off the profile as
## a player's opening is.
func begin(
	campaigns: Array[CampaignDefinition], posed: Dictionary[StringName, CampaignState] = {}
) -> void:
	_fill(campaigns, posed)
	show()
	if _row_buttons.is_empty():
		_back_button.grab_focus()
	else:
		_row_buttons[0].grab_focus()


func chrome() -> Dictionary[String, Control]:
	var named: Dictionary[String, Control] = {"the campaign title": _title, "Back": _back_button}
	if _row_buttons.is_empty():
		named["the empty note"] = _empty
	else:
		named["the first campaign row"] = _row_buttons[0]
	return named


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cancel"):
		get_viewport().set_input_as_handled()
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
	main.add_theme_constant_override("separation", 6)
	margin.add_child(main)

	_title = Label.new()
	_title.text = "CAMPAIGNS"
	_title.add_theme_font_override("font", UiTheme.display(true))
	_title.add_theme_font_size_override("font_size", _TITLE_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_title)

	main.add_child(_note("Six wars against the Iron Dominion. Eighteen missions each."))

	_empty = _note("No campaigns installed.")
	main.add_child(_empty)

	var frame := ScrollContainer.new()
	frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(frame)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(_rows)

	_back_button = Button.new()
	_back_button.text = "Back"
	UiTheme.apply_button(_back_button, UiTheme.ButtonVariant.GHOST, null, UiTheme.SIZE_BUTTON)
	_back_button.custom_minimum_size = Vector2(_ROW_WIDTH, 20)
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(_leave)
	main.add_child(_back_button)

	var footer := Label.new()
	footer.add_theme_font_override("font", UiTheme.stat())
	footer.add_theme_font_size_override("font_size", 8)
	footer.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	footer.text = "UP/DOWN  BROWSE      ENTER  OPEN      ESC  BACK      MOUSE OK"
	main.add_child(footer)


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.stat())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	label.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _fill(
	campaigns: Array[CampaignDefinition], posed: Dictionary[StringName, CampaignState]
) -> void:
	for button in _row_buttons:
		button.queue_free()
	_row_buttons.clear()
	_ids.clear()
	_empty.visible = campaigns.is_empty()
	for campaign in campaigns:
		var button := Button.new()
		var progress: CampaignState = (
			posed[campaign.id]
			if posed.has(campaign.id)
			else CampaignProfile.load_progress(campaign.id)
		)
		button.text = row_text(campaign, progress)
		var variant := (
			UiTheme.ButtonVariant.PRIMARY
			if CampaignDB.leads(campaign.id)
			else UiTheme.ButtonVariant.SECONDARY
		)
		UiTheme.apply_button(button, variant, null, UiTheme.SIZE_BUTTON)
		button.custom_minimum_size = Vector2(_ROW_WIDTH, _ROW_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var index := _ids.size()
		button.pressed.connect(func() -> void: _pick(index))
		_rows.add_child(button)
		_row_buttons.append(button)
		_ids.append(campaign.id)


## "The Six Marshals — 4/18 · 9 stars", or "— new" for a war with no profile, or
## "— complete" for one with nothing left to offer.
##
## Both halves are the **route's** answers, never the list's: finished is
## `is_complete` and the total is `offered_count`, the same two the hub's headline
## reads. A row counting the whole list said "17/18" forever to a player the war
## had no eighteenth mission for — the campaign finished on the hub and stayed
## unfinished here, which is one campaign with two notions of done. It is the
## offered total rather than the authored one on the same reasoning: a road the
## route walked past can never be cleared, so counting it is counting to a number
## nobody can reach.
##
## Static and argument-taking so the row can be read without a profile on disk and
## without the page — `SeatStrip.normalised_sides`' shape, for its reason.
static func row_text(campaign: CampaignDefinition, progress: CampaignState) -> String:
	return _standing(campaign, progress) + _badge(campaign)


## The flagship's mark, from `CampaignDB`'s own key rather than the row's position,
## so the war that leads the list is the war that says to start there.
static func _badge(campaign: CampaignDefinition) -> String:
	return "   ·   START HERE" if CampaignDB.leads(campaign.id) else ""


static func _standing(campaign: CampaignDefinition, progress: CampaignState) -> String:
	if progress == null:
		return "%s   —   new" % campaign.title
	if progress.is_complete(campaign):
		return "%s   —   complete · %d stars" % [campaign.title, progress.total_stars()]
	return (
		"%s   —   %d/%d · %d stars"
		% [
			campaign.title,
			progress.records.size(),
			progress.offered_count(campaign),
			progress.total_stars()
		]
	)


func _pick(index: int) -> void:
	if index < 0 or index >= _ids.size():
		return
	hide()
	picked.emit(_ids[index])


func _leave() -> void:
	hide()
	cancelled.emit()
