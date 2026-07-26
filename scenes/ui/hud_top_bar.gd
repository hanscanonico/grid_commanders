class_name HudTopBar
extends PanelContainer
## The docked strip above the board: the turn state that does not change while a
## unit is being moved. Day, the side in hand and its doctrine, funds, menu hint.
##
## Docked, opaque and full width — never a slab over the map (hud handoff SPEC,
## "Opaque only" / "Nothing floats over the map"). Its height is UiTheme's
## HUD_TOP_H and never varies with content, because the board's viewport is
## computed against it once and must not move mid-turn.
##
## Everything here is presentation: the strings arrive from BattleView, already
## resolved through SideIdentity and the live CommanderType, and this only lays
## them out. The doctrine is `CommanderType.doctrine_text` — the always-on
## passive — not `power_name`, which belongs beside the meter it charges
## (SPEC "Content — read it from COMMANDERS").

const _CHIP := 7  # the faction colour square, handoff 14px
const _PAD := 7
const _GAP := 7
const _RULE_H := UiTheme.HUD_TOP_H - 10

var _day_label: Label
var _chip: Panel
var _faction_label: Label
var _doctrine_label: Label
var _funds_label: Label


func _ready() -> void:
	_build()


func _build() -> void:
	custom_minimum_size = Vector2(0, UiTheme.HUD_TOP_H)
	add_theme_stylebox_override("panel", UiTheme.hud_bar_box(false))
	# Chrome swallows the pointer. The board is deliberately allowed to render
	# *behind* the bars (BattleView._apply_camera_limits), so a bar that let mouse
	# events fall through to Battle._unhandled_input would walk the game cursor
	# onto a cell hidden under opaque paint — and a click there would select it.
	# The bottom bar states the same thing for the same reason.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _GAP)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(row)

	row.add_child(UiTheme.hud_spacer(_PAD - _GAP))
	row.add_child(UiTheme.hud_label("DAY", UiTheme.SIZE_MICRO, UiTheme.INK_3))
	_day_label = UiTheme.hud_label("1", UiTheme.SIZE_BUTTON, UiTheme.WHITE, true)
	row.add_child(_day_label)
	row.add_child(UiTheme.hud_divider(_RULE_H))

	_chip = Panel.new()
	_chip.custom_minimum_size = Vector2(_CHIP, _CHIP)
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_chip)

	_faction_label = UiTheme.hud_label("", UiTheme.SIZE_SEGMENT, UiTheme.WHITE)
	row.add_child(_faction_label)
	# The doctrine takes whatever width is left and clips rather than pushing the
	# funds out of place: a fixed-height bar cannot wrap, and the number on the
	# right has to sit still.
	_doctrine_label = UiTheme.hud_label("", UiTheme.SIZE_MICRO, UiTheme.INK_3)
	_doctrine_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_doctrine_label.clip_text = true
	row.add_child(_doctrine_label)

	row.add_child(UiTheme.hud_label("FUNDS", UiTheme.SIZE_MICRO, UiTheme.INK_3))
	_funds_label = UiTheme.hud_label("0", UiTheme.SIZE_SEGMENT, UiTheme.CAPTURE, true)
	row.add_child(_funds_label)
	row.add_child(UiTheme.hud_divider(_RULE_H))
	# Cancel opens the field menu from IDLE (Battle._cancel), which is the control
	# this names. A hint on permanent chrome has to stay true.
	row.add_child(UiTheme.hud_label("ESC · MENU", UiTheme.SIZE_MICRO, UiTheme.INK_3))
	row.add_child(UiTheme.hud_spacer(_PAD - _GAP))


## One update per turn change. `side_theme` and `faction` come from the side's
## resolved identity, so a commander-less match still names and colours a side.
func show_turn(
	day: int,
	side_theme: CommanderVisuals.FactionTheme,
	faction: String,
	doctrine: String,
	funds: int
) -> void:
	_day_label.text = str(day)
	# The lighter variant, always: a faction's base hue is close enough to the
	# slate bar that Iron's chip disappears into it entirely (SPEC's second token
	# bug). Every faction chip on a dark surface takes the -light value.
	_chip.add_theme_stylebox_override("panel", _chip_box(side_theme.color_light))
	_faction_label.text = faction.to_upper()
	_doctrine_label.text = doctrine
	_funds_label.text = _thousands(funds)


## 13000 -> "13,000". The funds readout is the one number on this bar a player
## reads as a quantity rather than an identifier, and grouping is what makes it
## legible at a glance.
static func _thousands(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if value < 0 else "") + out


func _chip_box(color: Color) -> StyleBoxFlat:
	var box := UiTheme.flat(color)
	box.border_color = UiTheme.HARD_BORDER
	box.set_border_width_all(1)
	return box
