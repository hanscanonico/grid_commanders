class_name CommanderInfoSheet
extends Control
## The in-battle commander reference: both sides' full cards, opened from the
## battle menu rather than a hover tooltip (readiness plan G3). Showing both is
## deliberate and safe — a commander's identity and doctrine are match metadata,
## not a fog-hidden unit position, so nothing here leaks what the viewer cannot
## see on the board.
##
## Reuses the same CommanderCard the selection page does; the only thing new is a
## faction header over each, named and tinted by the resolved side identity (a
## mirror shows the borrowed classic). Pure presentation — it reads the two
## CommanderTypes and closes itself; Battle owns when it opens and blocks board
## input while it is up.

signal closed

var _built := false
var _red_card: CommanderCard
var _blue_card: CommanderCard
## The two headers, retitled and retinted per match from the resolved identity —
## a captured commander's faction, or a mirror's borrowed classic (SideIdentity).
var _red_header: PanelContainer
var _red_title: Label
var _blue_header: PanelContainer
var _blue_title: Label
var _close_button: Button


func _ready() -> void:
	_build()
	hide()


## Shows both sides' cards and takes focus, so a controller or keyboard can close
## it without reaching for the mouse.
func open(red_co: CommanderType, blue_co: CommanderType) -> void:
	if not _built:
		_build()
	# The same resolver the board uses, so a mirror match shows the borrowed
	# classic here too: two Iron doctrines read "IRON DOMINION" over slate and blue.
	var identity := SideIdentity.resolve({1: red_co, 2: blue_co})
	_retitle(_red_header, _red_title, identity, 1)
	_retitle(_blue_header, _blue_title, identity, 2)
	_red_card.bind(red_co)
	_blue_card.bind(blue_co)
	show()
	_close_button.grab_focus.call_deferred()


## Names and tints one card header from a side's resolved identity.
func _retitle(header: PanelContainer, title: Label, identity: SideIdentity, team: int) -> void:
	var theme := identity.theme(team)
	var box := StyleBoxFlat.new()
	box.bg_color = theme.color
	header.add_theme_stylebox_override("panel", box)
	title.text = identity.display_name(team).to_upper()
	title.add_theme_color_override("font_color", theme.ink)


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	# Near-solid, not the 0.97 written here before: open() used to re-run this build
	# and stack a second veil over the first, so what the screen actually showed was
	# the pair (~0.999). With the duplicate build gone, 0.97 alone let the board ghost
	# through. This keeps the authored "veil over the board" reading without the bleed.
	bg.color = Color(0.086, 0.106, 0.118, 0.995)
	# set_anchors_preset alone rewrites the offsets to preserve the rect a control
	# already has, so it only bites a node that is *already* parented to a sized
	# parent — the sheet's own call above, added to a full-size battle scene. bg and
	# the margin below are freshly created and still parentless when their preset
	# runs: the parent rect is empty, the offsets stay 0, and either form covers.
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# A bounded margin, not a CenterContainer: centring a column taller than the
	# screen pushes both its ends off, which is how the Close button used to leave
	# the viewport (COM-31, the same overflow the select page had). Here the cards
	# row absorbs the slack and the title and button keep their edges.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)

	# No page title: the two faction headers below already name what this is, and on
	# a 360px-tall screen the row it would cost is the difference between the cards
	# fitting and the Close button being crowded.
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(cards)
	# Headers built blank; open() titles and tints them per match from the
	# resolved identity, so this scene never hardcodes a side name or colour.
	var red := _titled_card(cards)
	_red_card = red[0]
	_red_header = red[1]
	_red_title = red[2]
	var blue := _titled_card(cards)
	_blue_card = blue[0]
	_blue_header = blue[1]
	_blue_title = blue[2]

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.add_theme_font_size_override("font_size", 11)
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_button.pressed.connect(_emit_close)
	rows.add_child(_close_button)

	_built = true


## Builds one column — a header band over a CommanderCard — and hands back
## [card, header, title label] so open() can title and tint the header per match.
func _titled_card(parent: Node) -> Array:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)

	var header := PanelContainer.new()
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	margin.add_child(label)
	header.add_child(margin)
	column.add_child(header)

	# Same bounded frame the select page gives its card: the card's height is
	# content-driven, so it is the one child allowed to run out of room, and the
	# scroll keeps that from reaching the Close button.
	var frame := ScrollContainer.new()
	frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(frame)

	var card := CommanderCard.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.add_child(card)
	return [card, header, label]


func _shortcut_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_emit_close()
		accept_event()


func _emit_close() -> void:
	hide()
	closed.emit()
