class_name TurnBanner
extends PanelContainer
## The card that stops the board for a beat: the day and the side taking it, an
## ambush sprung, an army fallen, the result of a save.
##
## The design system's cream panel, like the Command Power card it alternates
## with — a beat lands *on* the board and is read across the room, where the
## docked bars are slate chrome beside it.
##
## Presentation only, and only the words: how long a beat holds, what a press does
## to it and where it sits are BattleAnimator's.

const _PAD_X := 14
const _PAD_Y := 8

var _label: Label


func _ready() -> void:
	_build()


func _build() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_box())

	var margin := UiKit.pad(null, _PAD_X, _PAD_Y)
	add_child(margin)

	_label = UiTheme.hud_label("", UiTheme.SIZE_BANNER, UiTheme.INK)
	_label.add_theme_font_override("font", UiTheme.display(true))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	margin.add_child(_label)


func announce(text: String) -> void:
	_label.text = text
