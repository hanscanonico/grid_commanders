class_name MobileDock
extends PanelContainer
## The third docked bar, built only on a touch build (mobile plan D5, MB3): the
## way out of every state a finger could otherwise not leave.
##
## The headline is not "a Back button" but the abort. In POWER_TARGETING any tap
## on the board fires the aimed power at the cell it landed on, and the only way
## out is the `cancel` action — so without this bar a touch player who opens
## Radek Morn's Hammerfall must spend the most expensive power in the game on a
## square they did not choose. Back also leaves the three other targeting states,
## asks for the pause during a computer turn, and at rest opens the map menu:
## every one of those is a branch `Battle._cancel` already has.
##
## Every chip dispatches the action the keyboard dispatches, through
## `HudTopBar.chip_button`'s idiom — so which states honour it and what it then
## does are the key path's and cannot drift from it (D2). Nothing here calls a
## `Battle` branch of its own and nothing here knows what a `Battle` is.
##
## Disabled, never hidden. The bar keeps its height in every state, because the
## height is part of the chrome the board's viewport is framed against and a bar
## that came and went would move the zoom ladder's floor several times a turn.
## A disabled chip also cannot be pressed, which is what makes one physical tap
## produce one receipt rather than an action *and* a banner skip during the
## states that swallow board input.

## The gap between a chip's ink and the bar's edge, and between the two thumbs'
## groups. The dock is one row of short labels, so it uses the bars' own pad.
const _PAD := UiTheme.HUD_PAD

var _back: Button
var _resume: Button
var _step: Button
## The chips by the action each dispatches, which is also how a driven capture
## presses one: a scenario reaches the bar the way a finger does rather than
## calling a `Battle` branch the touch player has no route to.
var _chips: Dictionary[StringName, Button] = {}


## Docks a bar under `bottom` and hands it back, or hands back null on a desktop
## build — where D5 says the chrome is never constructed at all rather than built
## and hidden. The bottom bar rides up by the dock's height, so the dock takes
## the window's last rows and the two bars above it are otherwise untouched.
static func install(bottom: Control) -> MobileDock:
	if not MobileProfile.active():
		return null
	var dock := MobileDock.new()
	bottom.offset_top -= UiTheme.HUD_DOCK_H
	bottom.offset_bottom -= UiTheme.HUD_DOCK_H
	bottom.get_parent().add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.offset_top = -UiTheme.HUD_DOCK_H
	return dock


## How much of the window the docked chrome takes: the two fixed bars, plus this
## one where it was built. The single answer, so the board's viewport, the camera
## clamp and the cut-in's still cannot each hold a different opinion about where
## the board's band is.
static func chrome_h() -> int:
	return UiTheme.HUD_BARS_H + height()


## The dock's own height, and zero on a desktop build.
static func height() -> int:
	return UiTheme.HUD_DOCK_H if MobileProfile.active() else 0


## How many *screen* pixels the board rides up out of the window's middle so it
## sits centred in the band the chrome leaves. The bars' heights differ by an odd
## number, so the exact half-difference is fractional, and half a screen pixel of
## camera offset puts every texel boundary of the board on a half pixel — the
## fractional rest the whole integer-rung argument exists to forbid. The odd pixel
## goes to the bottom: the board rides one further up, so the extra half of
## clearance sits above the taller chrome, where a unit standing on the last row
## is further from it rather than nearer.
##
## Here rather than on `BattleView` because the dock is the only reason it is not
## a constant, and two answers to where the band's middle is would be one answer
## too many.
static func board_lift_px() -> int:
	return (UiTheme.HUD_BOTTOM_H + height() - UiTheme.HUD_TOP_H + 1) / 2


func _ready() -> void:
	custom_minimum_size = Vector2(0, UiTheme.HUD_DOCK_H)
	add_theme_stylebox_override("panel", UiTheme.hud_bar_box(true))
	# The same reason the two bars above swallow the pointer: the board renders
	# behind the chrome, so an event falling through would walk the game cursor
	# onto a cell hidden under opaque paint.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.HUD_GAP)
	add_child(row)

	row.add_child(UiTheme.hud_spacer(_PAD - UiTheme.HUD_GAP))
	_back = _chip(ControlHints.DOCK_BACK, &"cancel")
	row.add_child(_back)
	_resume = _chip(ControlHints.DOCK_RESUME, &"confirm")
	row.add_child(_resume)
	_step = _chip(ControlHints.DOCK_STEP, &"replay_step")
	row.add_child(_step)
	# The two thumbs: what leaves a state on the left, what looks around the board
	# on the right, with the whole bar between them.
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	row.add_child(_chip(ControlHints.DOCK_ZOOM_OUT, &"zoom_out"))
	row.add_child(_chip(ControlHints.DOCK_ZOOM_IN, &"zoom_in"))
	row.add_child(_chip(ControlHints.DOCK_NEXT, &"next_unit"))
	row.add_child(UiTheme.hud_spacer(_PAD - UiTheme.HUD_GAP))
	refresh(ControlHints.IDLE)


## Brings the bar up to date with the interaction the player is now in. Called
## from `BattleView.refresh_keys`, which `Battle`'s state setter is the one caller
## of — so the dock reads the same context the key legend does and neither can
## fall out of step with the flow.
func refresh(context: StringName) -> void:
	var live := BattleLegend.dock_live(context)
	_back.text = ControlHints.dock_back_for(context)
	for chip: Button in _chips.values():
		chip.disabled = not live
	# Resume and Step are the two chips a wrong state would not merely waste: at
	# rest the confirm action selects whatever the cursor is on, so they answer
	# only where the keyboard's own keys do.
	_resume.disabled = not BattleLegend.paused_in(context)
	_step.disabled = not BattleLegend.steppable(context)


## The chip that dispatches `action`, and what the leading chip currently says.
## Read back by the `mobile_back` capture, which presses these rather than calling
## into `Battle`.
func chip_for(action: StringName) -> Button:
	return _chips.get(action)


func back_word() -> String:
	return _back.text


func _chip(text: String, action: StringName) -> Button:
	var chip := HudTopBar.chip_button(text, action)
	chip.add_theme_color_override("font_disabled_color", UiTheme.SLATE_700)
	chip.size_flags_vertical = Control.SIZE_FILL
	_chips[action] = chip
	return chip
