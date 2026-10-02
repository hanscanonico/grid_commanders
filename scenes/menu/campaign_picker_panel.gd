class_name CampaignPickerPanel
extends Control
## The installed campaigns, shown over the main menu without tearing it down —
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

## A card's floor: three lines of type — 40px, measured off their own fonts — plus a
## margin above and below, because a card whose last line sat on its own border
## read as clipped copy. A card stands taller by every further line its premise
## wraps to, since the card is the one place the whole premise is printed; six
## one-line cards and the page's chrome still fit 360px without a scrollbar.
const _ROW_HEIGHT := 43
const _ROW_WIDTH := 460
const _THUMB := Vector2(88, 36)
const _ROW_INSET := 6
## `ListRow.face`'s own gap between the miniature and the words.
const _FACE_SEPARATION := 6
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
	if TransitionInput.dismissed_by_cancel(self, event):
		_leave()


# --- build -------------------------------------------------------------------


func _build() -> void:
	UiKit.page_veil(self)
	var main := UiKit.page_body(self, _PAGE_SEPARATION)

	_title = UiKit.page_title("CAMPAIGNS")
	main.add_child(_title)

	main.add_child(UiKit.page_note("One war in six acts, from the Seam to Hammer Hill."))

	_empty = UiKit.page_note("No campaigns installed.")
	main.add_child(_empty)

	var frame := UiKit.vscroll()
	main.add_child(frame)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", _CARD_SEPARATION)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(_rows)

	_back_button = UiKit.action_button("Back", "", UiTheme.ButtonVariant.GHOST, null, _ROW_WIDTH)
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(_leave)
	main.add_child(_back_button)

	main.add_child(
		UiKit.key_legend("UP/DOWN  BROWSE      ENTER  OPEN      ESC  BACK      MOUSE OK")
	)


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
		var premise := premise_lines(campaign.premise, _words_width())
		var line_height := UiTheme.stat().get_height(UiTheme.SIZE_STAT)
		var height := _ROW_HEIGHT + maxi(premise - 1, 0) * line_height
		button.custom_minimum_size = Vector2(_ROW_WIDTH, height)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var saved := posed.is_empty() and _holds_saved_board(campaign, progress)
		var ink := button.get_theme_color(&"font_color")
		button.add_child(_row_face(campaign, progress, saved, premise, ink))
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
func _row_face(
	campaign: CampaignDefinition, progress: CampaignState, saved: bool, premise: int, ink: Color
) -> Control:
	var face := ListRow.face(_ROW_INSET)
	var thumb := _thumbnail(campaign)
	if thumb != null:
		face.add_child(thumb)
	var words := ListRow.words()
	words.add_child(ListRow.clipped(ListRow.cell(row_text(campaign, progress, saved), ink)))
	if not campaign.antagonist.is_empty():
		words.add_child(_micro(campaign.antagonist.to_upper(), _faded(ink, _ANTAGONIST_FADE), 1))
	if premise > 0:
		words.add_child(_micro(campaign.premise, _faded(ink, _PREMISE_FADE), premise))
	face.add_child(words)
	return face


## How many lines the premise wraps to across `width` — all of them, because the
## card stands as tall as its premise rather than cutting it: the card is the one
## place a war's pitch is printed, and a pitch that stopped at an ellipsis was
## never read whole anywhere. 0 for a war with no premise.
##
## Static and argument-taking for `row_text`'s reason.
static func premise_lines(premise: String, width: float) -> int:
	if premise.is_empty():
		return 0
	var font := UiTheme.stat()
	var line_height := font.get_height(UiTheme.SIZE_STAT)
	var wrapped := font.get_multiline_string_size(
		premise, HORIZONTAL_ALIGNMENT_LEFT, width, UiTheme.SIZE_STAT
	)
	return maxi(1, roundi(wrapped.y / line_height))


## The width a card's lines are set in: the card, less its insets, the miniature
## and the gap after it.
static func _words_width() -> float:
	return _ROW_WIDTH - 2 * _ROW_INSET - _THUMB.x - _FACE_SEPARATION


## Whether the war's profile holds a mission's saved board — the same disk fact
## the hub turns a Deploy into a Resume on.
static func _holds_saved_board(campaign: CampaignDefinition, progress: CampaignState) -> bool:
	if progress == null or progress.active_mission == &"":
		return false
	return CampaignProfile.saved_mission(campaign.id) == progress.active_mission


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


## The card's ink, faded — never a grey of its own, so the fade is right on cream
## and on the flagship's red by construction.
static func _faded(ink: Color, amount: float) -> Color:
	return Color(ink, ink.a * amount)


## A wrapped, clipped line is measured off its own font: a `Label` that both wraps
## and clips reports a 1x1 minimum, so left to itself it lays out invisible, and
## `get_line_height()` answers for the default theme until the label is in a tree.
## With no line spacing a line is exactly the font's height. A line past `lines`
## is cut with an ellipsis rather than painted over the next card; the premise is
## handed the lines it wraps to, so only the one-line antagonist could ever be cut.
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


## "Five Flags — 4/39 · 9 stars", or "— new" for a war with no profile, or
## "— complete" for one with nothing left to offer — and, when `saved` says the
## profile holds a mission's board, which mission is waiting to be resumed.
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
static func row_text(
	campaign: CampaignDefinition, progress: CampaignState, saved: bool = false
) -> String:
	return _standing(campaign, progress) + _badge(campaign, progress, saved)


## The flagship's mark, from `CampaignDB`'s own key rather than the row's position,
## so the war that leads the list is the war that says to start there — and only
## until its first clear, after which the row's own tally is the better answer. A
## mission midway through outranks it: that is where the player left off.
static func _badge(campaign: CampaignDefinition, progress: CampaignState, saved: bool) -> String:
	if saved and progress != null:
		var index := campaign.missions.find(campaign.mission(progress.active_mission))
		if index >= 0:
			return "   ·   %02d IN PROGRESS" % (index + 1)
	var unplayed := progress == null or progress.records.is_empty()
	return "   ·   START HERE" if unplayed and CampaignDB.leads(campaign.id) else ""


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
