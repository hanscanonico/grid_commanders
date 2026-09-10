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
## The width the card needs before more of it stops helping, measured across the
## whole roster: past this, widening the column wraps no line the select page's
## frame was clipping. Callers with the room ask for it by name rather than
## guessing a number — narrower is legible but taller, and height is the
## dimension this screen has none of. Re-measured at the 10px body (COM-271):
## 250 pushed nine of the twenty-two cards past the select page's frame, and 280
## leaves over it only the two that were over it before the raise.
const READING_WIDTH := 280

## De-emphasised copy on paper: the signature line, and the micro-label over each
## block under it. Card-local because the design system has no token for it — the
## shell's faint text (UiTheme.INK_3) is mixed for slate and washes out on cream.
const _MICRO_INK := Color(0.408, 0.443, 0.471)

## The two portrait bands a card can be built with, one of which `_init` takes.
## Public because a surface that frames a card names the band it built it with
## and checks its own layout against that same number.
## `WHOLE_BUST_BAND` is the drawing's own height and the default; `CHIP_BAND` is
## `CommanderVisuals`' chip field plus one texel of air, which `CommanderBust`
## centres as two pixels over the chip and one under it. The commander info sheet
## is the one caller that asks for the chip, and states there why.
const WHOLE_BUST_BAND := CommanderVisuals.PORTRAIT_SIZE.y
const _BAND_AIR_TEXELS := 1
const CHIP_BAND := CommanderVisuals.CHIP_FIELD.y + _BAND_AIR_TEXELS * CommanderVisuals.CHIP_ZOOM

## Which of the two bands this card was built with. Written once, by `_init`, so
## there is no order a caller has to get right and no later reader sees a card
## framed for one band drawing the other.
var _portrait_h: int
## The faction badge pinned into the band's top-left corner, and the inset it sits
## at. Card-local like the geometry above it, not a missing shell token: the design
## system sizes widgets rather than pins on art, and its smallest icon
## (UiTheme.MENU_ICON) is a menu row's glyph.
const _EMBLEM_PX := 22
const _EMBLEM_INSET := 6

var _commander: CommanderType
var _built := false

var _field: CommanderBust
var _emblem: TextureRect
var _name_band: PanelContainer
var _name_label: Label
var _quote_label: Label
var _doctrine_label: Label
var _power_box: PanelContainer
var _power_cost_label: Label
var _power_name_label: Label
var _power_text_label: Label


## `band` is one of the two constants above; the whole general is the default and
## `CHIP_BAND` is the commander info sheet's, which states there why.
func _init(band: int = WHOLE_BUST_BAND) -> void:
	_portrait_h = band


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

	# --- portrait stage: faction field, bust, emblem pin ---
	# The kit's bust extends Panel, not PanelContainer: the latter force-
	# stretches every child to fill it, which would blow the little emblem pinned
	# into the corner up over the whole portrait. The band names no width, so it
	# takes the card's, and the kit reads the height against the art: the whole
	# bust at `WHOLE_BUST_BAND`, the baked face chip at `CHIP_BAND`.
	_field = UiKit.commander_bust(null, Vector2(0, _portrait_h), UiKit.NO_FIELD)
	rows.add_child(_field)

	_emblem = TextureRect.new()
	_emblem.texture_filter = CommanderVisuals.EMBLEM_FILTER
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
	_name_label.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBTITLE)
	_name_band = PanelContainer.new()
	_name_band.add_child(UiKit.pad(_name_label, 6, 2))
	rows.add_child(_name_band)

	# --- rules copy on paper ---
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 3)
	var copy_wrap := _paper_panel(copy, 7, 4)
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

	var power_head := UiKit.pad(null, 5, 2)
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
	power_rows.add_child(UiKit.pad(_power_text_label, 6, 2))

	_built = true


func _apply() -> void:
	var theme := CommanderVisuals.theme_for(_commander)
	_field.bind(_commander, theme.color)
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
