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

var _day_label: Label
var _chip: Panel
var _faction_label: Label
var _doctrine_label: Label
var _funds_label: Label
var _threat_label: Label
var _range_label: Label
var _objectives_label: Label
var _keys_label: Label


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
	row.add_theme_constant_override("separation", UiTheme.HUD_GAP)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(row)

	row.add_child(UiTheme.hud_spacer(UiTheme.HUD_PAD - UiTheme.HUD_GAP))
	row.add_child(UiTheme.hud_label("DAY", UiTheme.SIZE_MICRO, UiTheme.INK_3))
	_day_label = UiTheme.hud_label("1", UiTheme.SIZE_BUTTON, UiTheme.WHITE, true)
	row.add_child(_day_label)
	row.add_child(UiTheme.hud_divider(UiTheme.HUD_TOP_RULE_H))

	_chip = Panel.new()
	_chip.custom_minimum_size = Vector2(UiTheme.HUD_CHIP, UiTheme.HUD_CHIP)
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
	row.add_child(UiTheme.hud_divider(UiTheme.HUD_TOP_RULE_H))
	# The threat lens, stated as a chip rather than a legend entry: it is a way of
	# looking at the board rather than a key that does something in one interaction,
	# so it has to say both that T exists *and* whether the lens is currently up —
	# which a legend line, swapped per context and already full, cannot do. The copy
	# is still ControlHints'.
	_threat_label = UiTheme.hud_label(ControlHints.THREAT_CHIP, UiTheme.SIZE_MICRO, UiTheme.INK_3)
	row.add_child(_threat_label)
	# The fire ring, the same way: R answers for whatever the cursor is on in every
	# board context, so it is a lens rather than a legend entry. Beside T, and lit the
	# same way, because the two are one pair of questions — where can this unit shoot,
	# and where can anything shoot me.
	_range_label = UiTheme.hud_label(ControlHints.RANGE_CHIP, UiTheme.SIZE_MICRO, UiTheme.INK_3)
	row.add_child(_range_label)
	# The mission card's chip, beside the two lenses because O is the same kind of
	# key. Off the bar until a campaign mission says otherwise, so a skirmish's bar
	# is laid out exactly as it was before this chip existed.
	_objectives_label = UiTheme.hud_label(
		ControlHints.OBJECTIVES_CHIP, UiTheme.SIZE_MICRO, UiTheme.INK_3
	)
	_objectives_label.hide()
	row.add_child(_objectives_label)
	# The next-ready-unit key, beside the lenses because N is stated once for the
	# same reason they are. No field and no lit state: it never changes, so there is
	# nothing here to hold on to. The doctrine label absorbs its width by expanding.
	row.add_child(UiTheme.hud_label(ControlHints.NEXT_CHIP, UiTheme.SIZE_MICRO, UiTheme.INK_3))
	row.add_child(UiTheme.hud_divider(UiTheme.HUD_TOP_RULE_H))
	# The key legend, and the whole of it: whichever keys do something in the
	# interaction the player is currently in. It replaced a lone "ESC · MENU" that
	# was true but was also the only control the game ever named out loud (COM-12).
	# A hint on permanent chrome has to stay true, so the line is swapped per
	# context rather than listing every binding at once — see ControlHints, which
	# owns the copy, and Battle, which maps its State to a context key.
	_keys_label = UiTheme.hud_label(
		ControlHints.legend_for(ControlHints.IDLE), UiTheme.SIZE_MICRO, UiTheme.INK_3
	)
	row.add_child(_keys_label)
	row.add_child(UiTheme.hud_spacer(UiTheme.HUD_PAD - UiTheme.HUD_GAP))


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
	_chip.add_theme_stylebox_override(
		"panel", UiTheme.bordered(side_theme.color_light, UiTheme.HARD_BORDER)
	)
	_faction_label.text = faction.to_upper()
	_doctrine_label.text = doctrine
	_funds_label.text = _thousands(funds)


## Lights the threat chip while the lens is up. Colour only — the text never
## changes, so the chip reads as the same control in both states rather than as
## two different ones, and the bar's layout cannot shift when it is toggled.
func show_threat_lens(on: bool) -> void:
	_light(_threat_label, on)


## The fire ring's chip, lit on the same terms as the threat lens's above.
func show_range_lens(on: bool) -> void:
	_light(_range_label, on)


## The mission card's chip: on the bar only while there is a mission to describe,
## and lit while its card is up. Two facts rather than one, because a lowered card
## is exactly when the key most needs advertising — the chip is then the only thing
## on screen saying the mission's terms are one press away.
func show_objectives_lens(available: bool, on: bool) -> void:
	if _objectives_label != null:
		_objectives_label.visible = available
		_light(_objectives_label, on)


func _light(chip: Label, on: bool) -> void:
	if chip != null:
		chip.add_theme_color_override("font_color", UiTheme.DANGER if on else UiTheme.INK_3)


## Swaps the key legend for the interaction the player is now in. Called on every
## state change rather than once a turn, because that is exactly when the keys
## change; the copy itself is ControlHints', so this only prints it.
func show_keys(legend: String) -> void:
	if _keys_label != null:
		_keys_label.text = legend


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
