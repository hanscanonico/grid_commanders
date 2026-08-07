class_name HandoffScreen
extends RefCounted
## Dresses the hot-seat handoff modal in the design system (COM-190). It used to
## be styled entirely in battle.tscn — an unnamed dark fill, raw font sizes, no
## font override — because battle.gd sits at its own line budget
## (tools/check_scripts.sh) with no room to dress it inline. The HUD-bar pattern
## moves the recipe here instead: battle.gd's _ready calls `dress` once, on the
## nodes it already grabs, the same shape hud_top_bar.gd and hud_bottom_bar.gd
## take for the docked bars.


## `backdrop`/`label`/`hint`/`button` are the modal's four styled nodes, handed
## over rather than looked up here, so this stays a pure recipe like the rest of
## UiTheme's factories.
static func dress(backdrop: ColorRect, label: Label, hint: Label, button: Button) -> void:
	# Near-solid: the handoff exists to hide one player's fog from the next, so
	# it reads as a page that *replaces* the screen — the weight UiTheme.veil
	# gives the commander sheet and the two full-screen menu pickers, not the
	# end-turn guard's dim, which leaves the board visible underneath as context.
	backdrop.color = UiTheme.veil(0.995)

	label.add_theme_font_override("font", UiTheme.display(true))
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_BANNER)
	label.add_theme_color_override("font_color", UiTheme.WHITE)

	# A sentence, not a word — SIZE_TIP is UiTheme's token for exactly that
	# shape, already proven at this same weight on Tooltip's own dark slab.
	hint.add_theme_font_override("font", UiTheme.display())
	hint.add_theme_font_size_override("font_size", UiTheme.SIZE_TIP)
	hint.add_theme_color_override("font_color", UiTheme.INK_3)

	UiTheme.apply_button(button, UiTheme.ButtonVariant.PRIMARY)
