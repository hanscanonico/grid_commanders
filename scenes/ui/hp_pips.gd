class_name HpPips
extends HBoxContainer
## Ten cells of HP, filled to the unit's displayed health and coloured by the
## band it is in — the HUD-density reading of the number a card would print as
## text.
##
## Pips rather than a StatBar on purpose (hud handoff SPEC, "HP is pips"): a
## StatBar carries its own label and value readout and wants roughly a card's
## width, while a HUD row has one line of vertical room and already prints the
## unit's name beside it. Same data, denser control — and it is read without
## reading, because the colour changes before the count does.
##
## The colour rule is UiTheme.hp_color's, not a private copy, so the strip and
## anything else that ever bands the same number stay in step.

const MAX_PIPS := 10

var _cells: Array[Panel] = []


func _ready() -> void:
	add_theme_constant_override("separation", UiTheme.PIP_GAP)
	for i in MAX_PIPS:
		var cell := Panel.new()
		cell.custom_minimum_size = UiTheme.PIP
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(cell)
		_cells.append(cell)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `hp` is the unit's displayed health, 0-10. Empty cells stay visible in the
## divider slate so the strip reads as a gauge with a missing part rather than a
## shorter bar — the length of the row is a constant, only the fill moves.
func set_hp(hp: int) -> void:
	var filled := clampi(hp, 0, MAX_PIPS)
	var fill := UiTheme.hp_color(filled)
	for i in _cells.size():
		var color := fill if i < filled else UiTheme.SLATE_700
		_cells[i].add_theme_stylebox_override("panel", UiTheme.flat(color))
