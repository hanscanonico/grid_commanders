class_name CommanderCard
extends PanelContainer
## The full commander card: a large portrait establishes identity, then the name,
## doctrine, and Command Power follow in a strict vertical hierarchy — the
## "face before rules" reading order the supplied Claude card sheet is built on.
##
## Every value it shows is bound straight from the sim-side CommanderType
## (display_name, faction, doctrine_text, power_quotes, power_name, power_text,
## power_cost, power_duration); nothing is duplicated here, so the card can
## never drift from the numbers the rules actually use. All faction art — the field colour,
## the emblem, the portrait — comes from CommanderVisuals, the one authority on
## it. The card itself is pure presentation and never touches core/.
##
## It is dressed in the design system like every other surface (menu-revamp plan
## D1): Pixelify for the name and the rules copy, Silkscreen for the micro-labels
## and the cost, sizes and slates from UiTheme and every fill through UiTheme.flat
## — bar the two constants below, which say why they are the card's own. The card
## is also the in-battle info sheet and the select page's focus, so this is the one
## dress three screens wear, which is why it was deferred to a follow-up of its own
## rather than changed alongside the page it sits on.
##
## Built in code rather than a .tscn: the layout is regular and data-driven, and
## the repo would rather not hand-maintain scene-graph plumbing for it.

## The hard floor: narrower than this and the doctrine copy shreds into two-word
## lines. The card claims it unless the caller has already asked for more.
const MIN_WIDTH := 158
## The width every line of shipped copy needs to stop wrapping further, measured
## across the whole roster — and no page on a 640x360 screen can spare more than
## that. Callers with the room ask for it by name rather than guessing a number —
## narrower is legible but taller, and height is the dimension this screen has
## none of.
const READING_WIDTH := 250

## De-emphasised copy on paper: the signature line, and the micro-label over each
## block under it. Card-local because the design system has no token for it — the
## shell's faint text (UiTheme.INK_3) is mixed for slate and washes out on cream.
const _MICRO_INK := Color(0.408, 0.443, 0.471)

## The one size this card states for itself: its headline. Every other line is a
## UiTheme token, but the shell has no size between a button's 10 and a banner's
## 18, and a name band is neither — it is the card's face, read before the rules
## under it. Named here like the two full-screen pages name their own titles.
const _NAME_SIZE := 12
## The portrait band, public because a surface that frames this card checks its
## own layout against it — a card showing less than its face is showing nothing.
## Deliberately not raised to fill the band's width with the bust: the four-army
## info sheet shows a card 119px tall, and both cards of a duel already stand at
## their scroll frame's full height, so every pixel added here is a pixel of the
## Command Power block scrolled off the one sheet that photographs it.
const PORTRAIT_H := 96
## The faction badge pinned into the band's top-left corner, and the inset it sits
## at. Card-local for the reason _NAME_SIZE is: the design system has no token for
## a corner pin, and the shell's smallest icon (UiTheme.MENU_ICON) is a menu row's
## glyph rather than a badge on art.
const _EMBLEM_PX := 22
const _EMBLEM_INSET := 6

var _commander: CommanderType
var _built := false

var _field: Panel
var _portrait: TextureRect
var _emblem: TextureRect
var _name_band: PanelContainer
var _name_label: Label
var _quote_label: Label
var _doctrine_label: Label
var _power_box: PanelContainer
var _power_cost_label: Label
var _power_name_label: Label
var _power_text_label: Label


func _ready() -> void:
	_build()
	if _commander != null:
		_apply()


## Points the card at a commander (or CommanderType.neutral() for "No Commander").
## Safe to call before the node enters the tree; the card applies it once built.
func bind(commander: CommanderType) -> void:
	_commander = commander
	if _built:
		_apply()


func _build() -> void:
	custom_minimum_size.x = maxf(custom_minimum_size.x, MIN_WIDTH)
	add_theme_stylebox_override("panel", UiTheme.bordered(UiTheme.PAPER, UiTheme.HARD_BORDER, 3))

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)

	# --- portrait stage: faction field, portrait, emblem pin ---
	# A plain Panel, not a PanelContainer: the latter force-stretches every child
	# to fill it, which would blow the little emblem up over the whole portrait.
	_field = Panel.new()
	_field.custom_minimum_size = Vector2(0, PORTRAIT_H)
	_field.clip_contents = true
	rows.add_child(_field)

	_portrait = TextureRect.new()
	_portrait.texture_filter = CommanderVisuals.ART_FILTER
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Centred whole rather than cropped to fill: the portrait carries its own
	# ink-bordered window with the head breaking over its top edge, and a band this
	# wide can only fill by cutting that composition in half. Fitted, it stands on
	# the faction field the way the design's card frames it, at any card width.
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field.add_child(_portrait)

	_emblem = TextureRect.new()
	_emblem.texture_filter = CommanderVisuals.ART_FILTER
	# IGNORE_SIZE, or the 64px source becomes the control's minimum and _EMBLEM_PX
	# is clamped straight back up to it — which is how the badge has been drawing at
	# three times its size, unnoticed while an opaque bust filled the field behind it.
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Anchored to the corner it is pinned to rather than placed there: a bare
	# position/size holds only while nothing lays this child out, so the badge's
	# size was one container away from silently snapping back to its source again.
	_emblem.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_emblem.offset_left = _EMBLEM_INSET
	_emblem.offset_top = _EMBLEM_INSET
	_emblem.offset_right = _EMBLEM_INSET + _EMBLEM_PX
	_emblem.offset_bottom = _EMBLEM_INSET + _EMBLEM_PX
	_field.add_child(_emblem)

	# --- name band ---
	# A PanelContainer, so its stylebox paints the faction-dark band behind the
	# name (a MarginContainer draws no background).
	_name_label = Label.new()
	_name_label.add_theme_font_override("font", UiTheme.display(true))
	_name_label.add_theme_font_size_override("font_size", _NAME_SIZE)
	_name_band = PanelContainer.new()
	_name_band.add_child(UiKit.pad(_name_label, 6, 2))
	rows.add_child(_name_band)

	# --- rules copy on paper ---
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 4)
	var copy_wrap := _paper_panel(copy, 7, 5)
	rows.add_child(copy_wrap)

	# The general's signature line — power_quotes[0], the same words the
	# activation banner opens with on a first firing (power-quotes plan PQ2), so
	# the select screen introduces the character the battle then delivers.
	_quote_label = _body(_MICRO_INK)
	copy.add_child(_quote_label)

	_doctrine_label = _labelled_block(copy, "DOCTRINE")

	_power_box = PanelContainer.new()
	_power_box.add_theme_stylebox_override(
		"panel", UiTheme.bordered(UiTheme.PAPER, UiTheme.SLATE_700, 2)
	)
	copy.add_child(_power_box)
	var power_rows := VBoxContainer.new()
	power_rows.add_theme_constant_override("separation", 1)
	_power_box.add_child(power_rows)

	var power_head := UiKit.pad(null, 5, 3)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 6)
	var head_label := _micro("COMMAND POWER", _MICRO_INK)
	head_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_cost_label = _micro("", UiTheme.AMMO)
	head_row.add_child(head_label)
	head_row.add_child(_power_cost_label)
	power_head.add_child(head_row)  # power_head is a MarginContainer
	power_rows.add_child(power_head)

	# The power's own name, set like a button label rather than as body copy: it is
	# the one line in the block a player looks for.
	_power_name_label = Label.new()
	_power_name_label.add_theme_font_override("font", UiTheme.display(true))
	_power_name_label.add_theme_font_size_override("font_size", UiTheme.SIZE_BUTTON)
	power_rows.add_child(UiKit.pad(_power_name_label, 6, 0))

	_power_text_label = _body(UiTheme.INK)
	power_rows.add_child(UiKit.pad(_power_text_label, 6, 3))

	_built = true


func _apply() -> void:
	var theme := CommanderVisuals.theme_for(_commander)
	_field.add_theme_stylebox_override("panel", UiTheme.flat(theme.color))
	_portrait.texture = CommanderVisuals.portrait_for(_commander)
	if theme.key == CommanderVisuals.NEUTRAL_KEY:
		_emblem.texture = null
		_emblem.visible = false
	else:
		_emblem.texture = CommanderVisuals.emblem_for(_commander)
		_emblem.visible = true

	_name_label.text = _commander.display_name
	_name_label.add_theme_color_override("font_color", theme.ink)
	_name_band.add_theme_stylebox_override("panel", UiTheme.flat(theme.color_dark))
	# The power's name wears its own general's faction, like the band above it —
	# it was a hand-copy of meridian's dark on every card, whoever was on it.
	_power_name_label.add_theme_color_override("font_color", theme.color_dark)

	_quote_label.visible = not _commander.power_quotes.is_empty()
	if _quote_label.visible:
		_quote_label.text = "“%s”" % _commander.power_quotes[0]

	_doctrine_label.text = (
		_commander.doctrine_text
		if not _commander.doctrine_text.is_empty()
		else "Plays by the standard rules — no passive doctrine."
	)

	if _commander.has_power():
		_power_box.visible = true
		_power_cost_label.text = "%s  %d" % [_duration_tag(), _commander.power_cost]
		_power_name_label.text = _commander.power_name
		_power_text_label.text = _commander.power_text
	else:
		_power_box.visible = false


## Whether the power lasts only the owner's turn or through the round — the one
## number a player needs beyond cost to weigh timing.
func _duration_tag() -> String:
	return "ROUND" if _commander.power_duration == CommanderType.Duration.ROUND else "THIS TURN"


# --- small builders ----------------------------------------------------------


## A "MICRO-LABEL / body text" pair, returning the body Label for later binding.
func _labelled_block(parent: Node, micro: String) -> Label:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	parent.add_child(block)
	block.add_child(_micro(micro, _MICRO_INK))
	var body := _body(UiTheme.INK)
	block.add_child(body)
	return body


## One wrapping line of rules copy: Pixelify at the shell's body size, which is
## also its floor — a step down loses the face's space advance. Wrapping is the
## one thing `UiTheme.hud_label` doesn't offer a HUD readout, so the shared
## build is reset to top alignment (hud_label centres, for a bar row) and given
## the wrap its own copy needs.
func _body(color: Color) -> Label:
	var label := UiTheme.hud_label("", UiTheme.SIZE_BODY, color, true)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A block's caption or the cost beside it — Silkscreen, the face the whole game
## sets its labels and numerals in.
func _micro(text: String, color: Color) -> Label:
	var label := UiTheme.hud_label(text, UiTheme.SIZE_STAT, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return label


func _paper_panel(child: Control, h: int, v: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.PAPER))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(UiKit.pad(child, h, v))
	return panel
