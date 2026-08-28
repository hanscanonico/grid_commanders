class_name CommanderPowerBanner
extends PanelContainer
## The Command Power activation card: a portrait, the general's spoken line, the
## power's name, and its exact effect text, faction-tinted, shown center-screen
## for a beat when a power fires. The third and largest density of the shared
## card component (plan G1); it reads the same CommanderType and CommanderVisuals
## as the select card and HUD chip, so the three never disagree about a
## commander's face, colour, or copy.
##
## The quote is the card's headline and reads as the portrait speaking (plan PQ1:
## face left, words right — a quote never appears without the bust beside it).
## Lines rotate per side by activation count, never by RNG, so a replayed match
## speaks the same words and a captured activation is always the same frame. A
## commander with no quotes gets today's card unchanged: label hidden, power name
## back at full size.
##
## Pure presentation, and deliberately inert as far as the sim is concerned: it is
## populated from the already-fired PowerCommand's event and only *shows* what the
## power did. It may briefly gate input while it holds, but it never owns or
## alters simulation state — save/replay determinism stays entirely in core/.

## The headline hierarchy: with a quote on the card the power name steps down so
## the general's words lead; without one it keeps the size it always had.
const _QUOTE_SIZE := 16
const _POWER_NAME_SIZE := 22
const _POWER_NAME_QUOTED_SIZE := 13
## The overline above the quote ("GENERAL · COMMAND POWER"): one size past the
## shell's SIZE_TIP (8), because it reads across a center-screen card rather than
## at a tooltip's reading distance, and the shell has no token at this size.
const _EYEBROW_SIZE := 9
## The power's effect text, one step past the shell's SIZE_BODY (8) for the same
## reason as the eyebrow above.
const _POWER_TEXT_SIZE := 11
## The eyebrow's own shade of de-emphasised ink on the banner's paper field:
## UiTheme.INK_3 is tuned for slate (HUD labels) and washes out on cream, the
## same reason CommanderCard keeps its own _MICRO_INK rather than the token.
const _EYEBROW_INK := Color(0.431, 0.463, 0.482)
## The wrap width shared by the quote and the effect text, so both autowrap
## Labels compute a sane min height instead of reporting the pathological "one
## word per line" height that would balloon the whole banner.
const _COPY_WIDTH := Vector2(300, 0)
## The portrait window: taller than it is wide, so a general is shown whole (see
## `bind`'s note on the framed window) rather than cropped to a card's strip.
const _PORTRAIT_FIELD := Vector2(104, 108)

var _built := false
## Activations announced so far, per team — the rotation index for the next
## quote. Scene-lifetime state: a loaded save restarts the rotation, which is
## cosmetic by construction.
var _spoken: Dictionary[int, int] = {}
var _field: Panel
var _eyebrow: Label
var _quote: Label
var _power_name: Label
var _power_text: Label


func _ready() -> void:
	_build()


func _build() -> void:
	add_theme_stylebox_override(
		"panel", UiTheme.bordered(CommanderVisuals.PAPER, CommanderVisuals.HARD_BORDER, 4)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	# A fixed-size portrait field: an explicit height the portrait is fitted into,
	# and a width the HBox will not stretch (it has no expand flag). Tall enough
	# that the kit shows the general whole, as on the card — this is the one surface
	# that shows one full size, and the framed window they stand in is half the
	# drawing. Neutral until `bind` puts the firing general's faction on it.
	_field = UiKit.commander_bust(null, _PORTRAIT_FIELD, UiKit.NO_FIELD)
	row.add_child(_field)

	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 4)
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var wrap := UiKit.pad(copy, 14, 14)
	row.add_child(wrap)

	_eyebrow = UiTheme.hud_label("", _EYEBROW_SIZE, _EYEBROW_INK)
	copy.add_child(_eyebrow)
	_quote = UiTheme.hud_label("", _QUOTE_SIZE, CommanderVisuals.PAPER_INK, true)
	_quote.custom_minimum_size = _COPY_WIDTH
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_quote)
	# Neutral until `bind` puts the firing general's own faction on it, like the
	# panel border above — never a hand-copy of one faction's dark.
	_power_name = Label.new()
	_power_name.add_theme_font_override("font", UiTheme.display(true))
	_power_name.add_theme_font_size_override("font_size", _POWER_NAME_SIZE)
	_power_name.add_theme_color_override("font_color", CommanderVisuals.theme_for(null).color_dark)
	copy.add_child(_power_name)
	_power_text = UiTheme.hud_label("", _POWER_TEXT_SIZE, CommanderVisuals.PAPER_INK, true)
	_power_text.custom_minimum_size = _COPY_WIDTH
	_power_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_power_text)

	_built = true


func bind(commander: CommanderType, team: int) -> void:
	if not _built:
		_build()
	var theme := CommanderVisuals.theme_for(commander)
	add_theme_stylebox_override(
		"panel", UiTheme.bordered(CommanderVisuals.PAPER, theme.color_dark, 4)
	)
	UiKit.bind_bust(_field, commander, theme.color)
	_eyebrow.text = "%s · COMMAND POWER" % commander.display_name.to_upper()
	var line := _next_quote(commander, team)
	_quote.visible = not line.is_empty()
	_quote.text = "“%s”" % line
	_power_name.text = commander.power_name.to_upper()
	_power_name.add_theme_font_size_override(
		"font_size", _POWER_NAME_SIZE if line.is_empty() else _POWER_NAME_QUOTED_SIZE
	)
	_power_name.add_theme_color_override("font_color", theme.color_dark)
	_power_text.text = commander.power_text


## The next line in this side's rotation. Activation count picks quotes in
## order — deliberately not randf(), in the tradition of shake_camera's note
## about game.rng: a replayed match must speak the same words, and the scenario
## gallery's activation #1 must always photograph the same frame.
func _next_quote(commander: CommanderType, team: int) -> String:
	if commander.power_quotes.is_empty():
		return ""
	var count: int = _spoken.get(team, 0)
	_spoken[team] = count + 1
	return commander.power_quotes[count % commander.power_quotes.size()]
