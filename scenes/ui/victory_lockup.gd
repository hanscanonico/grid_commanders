class_name VictoryLockup
extends PanelContainer
## The screen a match ends on: the winning general fronting a cream card, who won,
## the day it took and the standings, and the two ways out.
##
## The turn banner's card one size up — same paper, same ink outline, same hard
## shadow — with a faction band across the top when a commander won it, so the
## last screen wears the livery the board has been wearing all match.
##
## Presentation only. Which words go on it are BattleOutcome's, and so is the
## input guard that keeps a buffered cut-in press from restarting the match: the
## two buttons are public because that guard grabs and releases their focus and
## switches their hit-testing, which no signal can say.

const _PAD_X := 16
const _PAD_Y := 10
const _PORTRAIT := 76
## A floor both actions clear, so the stack is one column rather than two centred
## buttons of whatever width their words happen to want — and so Rematch does not
## change size when a playback renames it Restart.
const _ACTION_W := 68

## The two ways out, and BattleOutcome's to arm — see the class note above.
var rematch_button: Button
var menu_button: Button

var _band: PanelContainer
var _band_label: Label
var _portrait: TextureRect
var _title: Label
var _sub: Label


func _ready() -> void:
	_build()


func _build() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_box())

	# The band spans the card, so it sits outside the padding rather than inside
	# it — the same shape the end-turn guard's header takes.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	_band = PanelContainer.new()
	column.add_child(_band)
	_band_label = UiTheme.hud_label("", UiTheme.SIZE_SEGMENT, UiTheme.WHITE)
	_band_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_band.add_child(_band_label)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", _PAD_X)
	margin.add_theme_constant_override("margin_right", _PAD_X)
	margin.add_theme_constant_override("margin_top", _PAD_Y)
	margin.add_theme_constant_override("margin_bottom", _PAD_Y)
	column.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(_PORTRAIT, _PORTRAIT)
	_portrait.texture_filter = CommanderVisuals.ART_FILTER
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rows.add_child(_portrait)

	_title = UiTheme.hud_label("", UiTheme.SIZE_BANNER, UiTheme.INK)
	_title.add_theme_font_override("font", UiTheme.display(true))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_title)
	_sub = UiTheme.hud_label("", UiTheme.SIZE_BODY, UiTheme.INK)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_sub)

	# Rematch leads in the shell's own primary fill, the way the main menu's Start
	# does, and never in the winner's colour: the livery is the band's job, and a
	# button that changed hue with the result would read as a different button.
	rematch_button = _action(rows, UiTheme.ButtonVariant.PRIMARY, "")
	menu_button = _action(rows, UiTheme.ButtonVariant.SECONDARY, "Main Menu")


func _action(rows: VBoxContainer, variant: UiTheme.ButtonVariant, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.x = _ACTION_W
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.apply_button(button, variant)
	rows.add_child(button)
	return button


## The result, as BattleOutcome worded it. `rematch_text` because a playback has
## no match to play again and the button has to name what pressing it does.
func announce(title: String, sub: String, rematch_text: String) -> void:
	_title.text = title
	_sub.text = sub
	rematch_button.text = rematch_text


## Fronts the card with the winning general. A side that played without one — and
## a draw, which has no winner to front at all — drops the band and the portrait
## and leaves the plain lockup.
func front_with(commander: CommanderType) -> void:
	var known := commander != null and commander.id != CommanderType.NEUTRAL_ID
	_band.visible = known
	_portrait.visible = known
	if not known:
		return
	var theme := CommanderVisuals.theme_for(commander)
	_band.add_theme_stylebox_override("panel", UiTheme.header_box(theme.color))
	_band_label.text = "%s · %s" % [commander.display_name, theme.display]
	_band_label.add_theme_color_override("font_color", theme.ink)
	_portrait.texture = CommanderVisuals.portrait_for(commander)
