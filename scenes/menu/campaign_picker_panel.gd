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

## Six cards, the page's chrome and no scrollbar inside 360px. The card is its three
## lines of type — 40px, measured off their own fonts — plus a margin above and
## below, because a card whose last line sat on its own border read as clipped copy;
## the two separations below are what pays for that margin, the page offering 261px
## of frame at the old spacing and 269 at this one against the six cards' 268. A war
## the player has to scroll to is a war the picker did not offer, so all four numbers
## are measured rather than guessed.
const _ROW_HEIGHT := 43
const _ROW_WIDTH := 460
const _THUMB := Vector2(88, 36)
const _PAGE_SEPARATION := 4
const _CARD_SEPARATION := 2
## The card's two micro lines are the button's own ink, faded — full ink is the
## headline's. Both stay clear of `apply_button`'s 0.6 disabled fade, which is what
## a card picking a grey of its own read as on the flagship's red.
const _ANTAGONIST_FADE := 0.85
const _PREMISE_FADE := 0.7

var _terrain := TerrainDB.load_default()
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
		margin.add_theme_constant_override("margin_" + edge, UiTheme.PAGE_MARGIN)
	add_child(margin)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", _PAGE_SEPARATION)
	margin.add_child(main)

	_title = Label.new()
	_title.text = "CAMPAIGNS"
	_title.add_theme_font_override("font", UiTheme.display(true))
	_title.add_theme_font_size_override("font_size", UiTheme.SIZE_PAGE_TITLE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_title)

	main.add_child(_note("Six wars against the Iron Dominion. Eighteen missions each."))

	_empty = _note("No campaigns installed.")
	main.add_child(_empty)

	var frame := UiKit.vscroll()
	main.add_child(frame)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", _CARD_SEPARATION)
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
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
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
		var variant := (
			UiTheme.ButtonVariant.PRIMARY
			if CampaignDB.leads(campaign.id)
			else UiTheme.ButtonVariant.SECONDARY
		)
		UiTheme.apply_button(button, variant, null, UiTheme.SIZE_BUTTON)
		button.custom_minimum_size = Vector2(_ROW_WIDTH, _ROW_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_child(_row_face(campaign, progress, button.get_theme_color(&"font_color")))
		var index := _ids.size()
		button.pressed.connect(func() -> void: _pick(index))
		_rows.add_child(button)
		_row_buttons.append(button)
		_ids.append(campaign.id)


## The row as a card rather than a line of text — `CampaignHubPanel._row_face`'s
## shape, for its reason: a button's own `text` can say one thing, and a war has
## three (where it is fought, who it is against, what it is about). The board is
## the first mission's, drawn by `MapThumbnail`, so the miniature is a truthful
## picture of the war's opening ground rather than a second opinion about it.
## Children of a button, so every one of them ignores the mouse — and all three
## lines are set in `ink`, the button's own resolved label colour, the two micro
## ones faded off it, because a card that picked its own would read white on the
## cream rows and dark on the flagship's red. `UiTheme.apply_button` is still the
## one authority for that colour.
func _row_face(campaign: CampaignDefinition, progress: CampaignState, ink: Color) -> Control:
	var face := HBoxContainer.new()
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.offset_left = 6
	face.offset_right = -6
	face.add_theme_constant_override("separation", 6)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thumb := _thumbnail(campaign)
	if thumb != null:
		face.add_child(thumb)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(_headline(row_text(campaign, progress), ink))
	if not campaign.antagonist.is_empty():
		words.add_child(_micro(campaign.antagonist.to_upper(), _faded(ink, _ANTAGONIST_FADE), 1))
	if not campaign.premise.is_empty():
		words.add_child(_micro(campaign.premise, _faded(ink, _PREMISE_FADE), 2))
	face.add_child(words)
	return face


## The war's opening ground. A board that will not load costs the row its picture
## and nothing else — the picker still has to offer the war.
func _thumbnail(campaign: CampaignDefinition) -> MapThumbnail:
	if campaign.missions.is_empty():
		return null
	var map := MapData.load_from_file(campaign.missions[0].map_path, _terrain)
	if map == null:
		return null
	var thumb := MapThumbnail.new()
	thumb.setup(map, UiTheme.menu_identity(map.player_count()), _THUMB)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return thumb


func _headline(text: String, ink: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.display())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_BUTTON)
	label.add_theme_color_override("font_color", ink)
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The card's ink, faded — never a grey of its own, so the fade is right on cream
## and on the flagship's red by construction.
static func _faded(ink: Color, amount: float) -> Color:
	return Color(ink, ink.a * amount)


## A wrapped, clipped line is measured off its own font: a `Label` that both wraps
## and clips reports a 1x1 minimum, so left to itself it lays out invisible, and
## `get_line_height()` answers for the default theme until the label is in a tree.
## With no line spacing a line is exactly the font's height. The cut is advertised
## on the last line that fits: a premise is a teaser, and one that stops mid-clause
## with no ellipsis reads as broken copy instead.
func _micro(text: String, ink: Color, lines: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.stat())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	label.add_theme_color_override("font_color", ink)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.max_lines_visible = lines
	label.add_theme_constant_override("line_spacing", 0)
	label.custom_minimum_size.y = UiTheme.stat().get_height(UiTheme.SIZE_STAT) * lines
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


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
