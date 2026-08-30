class_name UiKit
extends RefCounted
## The widgets the design system's screens are assembled from: the padded box, the
## micro-label, the page note and its key legend, the divider, the action button,
## the segmented control, the toggle row, the identity chip, the scroll frame and
## the commander bust. Every one of them
## is drawn out of UiTheme's colours, fonts and styleboxes and holds no state of its own.
##
## UiTheme's sibling, and the split between them is what each answers. UiTheme owns
## the *recipe* — a colour, a size, a stylebox — and UiKit owns the *widget* built
## from it, so a screen assembles rather than draws. They are two files because
## UiTheme is already a facade at the repo's public-method ceiling, and because a
## kit that builds tooltip-carrying widgets depends on Tooltip, which is here in
## scenes/ui/ rather than in scenes/common/ beside the tokens.
##
## Here rather than on the screens for the reason the HUD's labels are on UiTheme:
## a widget defined twice is a widget that drifts (menu-revamp plan D1). `pad` was
## three copies in three files, one of which had quietly grown a null guard the
## other two lacked; that guard is the version below, because a caller passing null
## wants an empty box and not an error.
##
## `settled` is the odd one out and is here for the same reason: it is the
## deferred-measure preamble every floating card opens `_place` with, and it was
## five identical lines in two files.
##
## Presentation only, and no Node held: every builder hands its control back to the
## screen that asked for it and keeps no reference.

## A bust drawn on no field at all — the victory lockup, which stands its portrait
## on the lockup's own paper rather than on a faction colour.
const NO_FIELD := Color(0, 0, 0, 0)

## What a field does with a general's art. WHOLE_FITTED stands the drawing in the
## field entire; WHOLE_COVERED fills the field with it and lets the edges go;
## FACE shows `CommanderVisuals.face_for` instead. Derived from the field's shape
## by `_crop_for` — never named by a caller.
enum BustCrop { WHOLE_FITTED, WHOLE_COVERED, FACE }

## The field height a whole bust needs. A portrait is a framed window with the head
## about five eighths of the drawing tall, so fitted whole into a shorter field the
## head lands under 40px — where two generals stop telling apart, which is what
## CommanderVisuals.FACE_REGION exists for.
const _BUST_MIN_H := 64
const _BUST_ART := &"Bust"

## A text field's height: one line of Silkscreen with the border either side of it.
const FIELD_HEIGHT := 18

## A toggle's ✓-box, and the gap between the three things on its row.
const TOGGLE_CHECK := 12
const TOGGLE_GAP := 5


## The veil a full-screen page is laid over, added to `page` as its first child.
##
## Anchors *and* offsets on the page itself: set_anchors_preset alone rewrites the
## offsets to preserve the rect the control already has, which for a page built in
## code and added to an already-sized menu is 0x0. That is what left commander
## select laid out at its content's minimum size in the top-left corner, with
## nothing bounded by the viewport — the ground COM-31's missing Confirm button
## grew from.
static func page_veil(page: Control, alpha: float = 0.985) -> ColorRect:
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = UiTheme.veil(alpha)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(veil)
	return veil


## The margin a full-screen page's content sits inside, and the column it stacks in.
## Added to `page`, so call it after anything that belongs under the content.
static func page_body(
	page: Control, separation: int, bottom: int = UiTheme.PAGE_MARGIN
) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + edge, UiTheme.PAGE_MARGIN)
	margin.add_theme_constant_override("margin_bottom", bottom)
	page.add_child(margin)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", separation)
	margin.add_child(main)
	return main


## A full-screen page's headline: the display face at page-title size, centred.
## A page that reads its title from the left (the gallery, commander select's
## topbar) sets `horizontal_alignment` back, and a page that recolours it (the
## debrief's verdict) sets `font_color` after — the dress is what is shared here,
## not the two things a page has its own answer to.
static func page_title(text: String = "") -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.display(true))
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_PAGE_TITLE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Wraps `child` (may be null) in a MarginContainer with even h/v padding.
static func pad(child: Control, h: int, v: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", h)
	margin.add_theme_constant_override("margin_right", h)
	margin.add_theme_constant_override("margin_top", v)
	margin.add_theme_constant_override("margin_bottom", v)
	if child != null:
		margin.add_child(child)
	return margin


## Gives `button` a finger-sized hit rectangle and hands it back, so a caller can
## wrap a control where it builds it. A no-op off a touch build — nothing is
## constructed there, which is what keeps every desktop frame byte-identical
## (mobile plan D5) — and a no-op for a control already big enough.
##
## Call it once the control is built and, on anything that carries decoration,
## *after* UiTheme.make_decoration: that pass silences a whole subtree, and a
## silenced area answers no tap.
static func touchable(button: BaseButton) -> BaseButton:
	if MobileProfile.active():
		TouchTarget.expand(button, UiTheme.TOUCH_MIN)
	return button


## A caption that carries the reason its control is dead, on a touch build only.
##
## The reason lives in a tooltip on desktop, and a disabled control takes no
## focus, so no focus source of any kind reaches that tip — the tip banks on the
## pointer, which a finger is not. So the words move into the caption already
## under the control, where they need no interaction at all (mobile plan D8, and
## its rejected alternative: a disabled control that answers a tap is a control
## that is not disabled).
static func caption_with_reason(headline: String, reason: String) -> String:
	if reason.is_empty() or not MobileProfile.active():
		return headline
	return "%s\n%s" % [headline, reason.to_upper()]


## A Silkscreen micro-label, set in caps: the heading over a group and the caption
## under a control.
static func micro_label(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UiTheme.stat())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	label.add_theme_color_override("font_color", UiTheme.NEUTRAL_DARK)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## Always-visible setup copy. Tooltips can elaborate on these lines, but the
## choice can be made without hover, a mouse, or prior knowledge.
static func help_label(text: String) -> Label:
	var label := micro_label(text)
	label.add_theme_color_override("font_color", UiTheme.NEUTRAL)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## A full-screen page's centred explanatory line: what this page is, or what it
## would hold if it held anything. Unlike `micro_label`/`help_label` it reads as a
## sentence rather than a caption, so it keeps its own case and centres — and it
## resets `hud_label`'s vertical centring, which is a bar row's answer rather than
## a page's.
static func page_note(text: String) -> Label:
	var label := UiTheme.hud_label(text, UiTheme.SIZE_STAT, UiTheme.NEUTRAL_LIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return label


## The key legend a full-screen page closes with. `page_note`'s dress, flush with
## the page's left margin rather than centred: it is a rail of key-and-verb pairs
## read from the left, not a sentence about the page.
static func key_legend(text: String) -> Label:
	var label := UiTheme.hud_label(text, UiTheme.SIZE_STAT, UiTheme.NEUTRAL_LIGHT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return label


## `filled` of `of` stars, the rest hollow — a terrain's defence and a mission's
## award are counted the same way, so they are spelled once. Clamped at both ends
## because `String.repeat` answers a negative count with an empty string, which
## would silently draw a bar of the wrong length instead of failing.
static func star_bar(filled: int, of: int) -> String:
	var lit := clampi(filled, 0, maxi(of, 0))
	return "★".repeat(lit) + "☆".repeat(maxi(of, 0) - lit)


## One number and the two buttons that walk it: a caption, the value's own label —
## the caller keeps it and writes the number into it, since what the number *is*
## is the caller's — and a step of -1 or +1. How wide the row stands is the
## caller's too, set on the control it is handed.
static func stepper(caption: String, value: Label, on_step: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_label := micro_label(caption)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var less := action_button("-", "", UiTheme.ButtonVariant.SECONDARY, null, 20)
	less.pressed.connect(func() -> void: on_step.call(-1))
	row.add_child(touchable(less))

	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.custom_minimum_size = Vector2(24, 0)
	row.add_child(value)

	var more := action_button("+", "", UiTheme.ButtonVariant.SECONDARY, null, 20)
	more.pressed.connect(func() -> void: on_step.call(1))
	row.add_child(touchable(more))
	return row


## A thin ink divider between a panel's rows (handoff --border-soft).
static func rule() -> Control:
	var line := ColorRect.new()
	line.color = UiTheme.BORDER_SOFT
	line.custom_minimum_size = Vector2(0, UiTheme.BORDER)
	return line


## The frame a page's body scrolls inside: it takes the height its container has
## to give and never scrolls sideways, a page whose copy can slide out of the left
## margin being a page the reader has to steer. A caller that wants the frame to
## chase focus or to stand at a fixed height sets that on the control it is handed —
## those are the page's business, and this is the shape they all share.
static func vscroll() -> ScrollContainer:
	var frame := ScrollContainer.new()
	frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return frame


## A faction-tinted or cream action button with an optional suffix ("MATCH"),
## appended to the label rather than set as a second run: one Button draws one
## string in one font, so the suffix wears the same Pixelify the label does.
##
## `width` 0 is the main menu's stack: the button takes the column's whole width.
## A width names a page footer's button instead, which stands at its own size —
## how that button is then placed in its row is the page's own answer, so the
## size flag is left where the caller set it.
static func action_button(
	text: String,
	suffix: String,
	variant: UiTheme.ButtonVariant,
	theme: CommanderVisuals.FactionTheme,
	width: int = 0
) -> Button:
	var button := Button.new()
	button.text = text if suffix.is_empty() else "%s  %s" % [text, suffix]
	UiTheme.apply_button(button, variant, theme, UiTheme.SIZE_BUTTON)
	if width <= 0:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(maxi(width, 0), 20)
	return button


## A typed line, dressed as the cream controls beside it. The editor's save
## dialog owned this while it was the game's only text field; the picker's rename
## prompt is the second caller, which is when a widget stops being its caller's.
static func text_field(placeholder: String, max_length: int, width: int) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = max_length
	field.custom_minimum_size = Vector2(width, FIELD_HEIGHT)
	field.add_theme_font_override("font", UiTheme.stat())
	field.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	field.add_theme_color_override("font_color", UiTheme.INK)
	field.add_theme_color_override("font_placeholder_color", UiTheme.NEUTRAL)
	field.add_theme_color_override("caret_color", UiTheme.INK)
	field.add_theme_stylebox_override(
		"normal", UiTheme.bordered(UiTheme.PAPER, UiTheme.HARD_BORDER, UiTheme.BORDER, true)
	)
	field.add_theme_stylebox_override(
		"focus", UiTheme.bordered(UiTheme.PAPER_RAISED, UiTheme.HARD_BORDER, UiTheme.BORDER, true)
	)
	return field


## A text link: the lightest action the system has, for the one row that belongs
## at the edge of a page rather than in its button stack. Silkscreen at micro size
## in muted ink, brightening on hover and focus, and shrunk to its own words — a
## full-width row with no fill and no border reads as a button whose chrome failed
## to draw, which is exactly what the menu's Quit used to look like.
static func text_link(text: String) -> Button:
	var link := Button.new()
	link.text = text.to_upper()
	link.add_theme_font_override("font", UiTheme.stat())
	link.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	var blank := UiTheme.flat(Color(0, 0, 0, 0))
	link.add_theme_stylebox_override("normal", blank)
	link.add_theme_stylebox_override("hover", blank)
	link.add_theme_stylebox_override("pressed", blank)
	link.add_theme_stylebox_override("focus", UiTheme.focus_box())
	link.add_theme_color_override("font_color", UiTheme.NEUTRAL)
	link.add_theme_color_override("font_hover_color", UiTheme.NEUTRAL_LIGHT)
	link.add_theme_color_override("font_pressed_color", UiTheme.NEUTRAL_LIGHT)
	link.add_theme_color_override("font_focus_color", UiTheme.NEUTRAL_LIGHT)
	link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return link


## A chip that answers the mouse as well as the key it names. Pressing it feeds
## the board the very action the keyboard sends, so which states honour it and
## what it then does are the key path's and cannot drift from it — the chips are
## the one part of the board a mouse-only player could not reach at all.
##
## Both docked screens build their chips here: the top bar's three lenses and the
## touch dock's row are one idiom for "a control that says a key and then presses
## it", rather than two copies of the synthesised event below (mobile plan D2).
static func action_chip(text: String, action: StringName) -> Button:
	var chip := UiTheme.hud_chip(text, UiTheme.SIZE_STAT, UiTheme.INK_3)
	chip.pressed.connect(_send_action.bind(action))
	# A chip is the smallest control in the game — 7 px of ink on a 23 px bar — so
	# on a touch build it answers a finger-sized rectangle it does not draw. The
	# bar's height is untouched, which is what leaves the zoom ladder where it is.
	return touchable(chip)


## A segmented control: a Silkscreen micro-label over a bordered row of toggle
## buttons, the active one carrying the faction fill. Labels come from the
## authority that owns them (GameSpeed / DifficultyDB), never typed in, so the
## control can never disagree with the tiers it drives (plan section 2).
##
## The group's explanation hangs off the micro-label, not off the column or the
## segments: reaching for "Quick" is not asking what Speed means. The always-visible
## help line under a group is the *screen's*, added by the caller — it is what a
## capture gate measures, so the screen keeps hold of it.
##
## `micro` is optional: an empty caption builds no label, no tip and no wrapping
## column, and hands back the bordered run itself — the seat strip's rows are two
## of these to a line and have no room for a caption over either (SeatStrip's
## `_seat_row`). `button_sink` and `restyle_sink` collect the buttons and the
## repaint closure a caller needs to reach in from outside a press: greying one
## button (the seat strip's Empty) or moving the highlight from a sibling control
## (a seat strip preset) rather than the segment's own. `height` is the segment
## buttons' minimum height; the seat strip's rows are denser than a stand-alone
## group and pass 16 against this default of 18.
static func segment(
	micro: String,
	labels: PackedStringArray,
	selected: int,
	accent: Color,
	tip: String,
	tip_detail: String,
	on_select: Callable,
	button_sink: Array[Button] = [],
	restyle_sink: Array[Callable] = [],
	height: int = 18
) -> Control:
	var frame := PanelContainer.new()
	var frame_box := UiTheme.bordered(UiTheme.PAPER, UiTheme.HARD_BORDER, UiTheme.BORDER, true)
	frame.add_theme_stylebox_override("panel", frame_box)

	var seg_row := HBoxContainer.new()
	seg_row.add_theme_constant_override("separation", 0)
	frame.add_child(seg_row)

	var buttons: Array[Button] = []
	for i in labels.size():
		var seg := Button.new()
		seg.text = labels[i]
		seg.toggle_mode = true
		seg.clip_text = true
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.custom_minimum_size = Vector2(0, height)
		seg.add_theme_font_override("font", UiTheme.display())
		seg.add_theme_font_size_override("font_size", UiTheme.SIZE_SEGMENT)
		seg_row.add_child(UiKit.touchable(seg))
		buttons.append(seg)
		button_sink.append(seg)

	var restyle := func(index: int) -> void:
		for i in buttons.size():
			style_segment(buttons[i], i == index, i > 0, accent)
	restyle.call(selected)
	restyle_sink.append(restyle)
	for i in labels.size():
		buttons[i].pressed.connect(
			func() -> void:
				restyle.call(i)
				on_select.call(i)
		)

	if micro.is_empty():
		return frame

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	var group_tip := _tip_label(col, micro, tip, tip_detail)
	col.add_child(frame)
	for seg in buttons:
		group_tip.follow_focus(seg)  # focus lands here, never on the micro-label
	return col


## One segment of a segmented row, in every state. Public because the seat strip
## dresses its own rows and its tier chips with it, so a seat row is the same
## control the speed row is.
static func style_segment(seg: Button, active: bool, divided: bool, accent: Color) -> void:
	var normal := UiTheme.segment_box(active, accent)
	if divided:
		normal.border_color = UiTheme.HARD_BORDER
		normal.border_width_left = UiTheme.BORDER
	seg.add_theme_stylebox_override("normal", normal)
	seg.add_theme_stylebox_override("hover", normal)
	seg.add_theme_stylebox_override("pressed", normal)
	seg.add_theme_stylebox_override("focus", UiTheme.focus_box())
	# Dimmed rather than blanked: a disabled group still has a tier in hand, and a
	# player must be able to read which one before the mode that greyed it out.
	# The fill loses its saturation, so the words take the ink the pale segments
	# already wear rather than the white that only reads against a full accent.
	var disabled := UiTheme.segment_box(active, accent.lerp(UiTheme.PAPER, 0.55))
	if divided:
		disabled.border_color = UiTheme.HARD_BORDER
		disabled.border_width_left = UiTheme.BORDER
	seg.add_theme_stylebox_override("disabled", disabled)
	var fg := UiTheme.WHITE if active else UiTheme.INK
	seg.add_theme_color_override("font_color", fg)
	seg.add_theme_color_override("font_hover_color", fg)
	seg.add_theme_color_override("font_pressed_color", fg)
	seg.add_theme_color_override("font_focus_color", fg)
	seg.add_theme_color_override(
		"font_disabled_color", UiTheme.INK if active else UiTheme.NEUTRAL_DARK
	)


## The width a toggle needs to say its whole piece: the box, the words and the
## ON/OFF, with the row's two gaps. The row inside the button is anchored
## rather than parented by a container, so the button has to state this itself —
## without it a narrow column clips the words instead of the layout refusing.
static func toggle_width(text: String) -> float:
	var words := UiTheme.display().get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_BODY
	)
	var status := UiTheme.stat().get_string_size(
		"OFF", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_STAT
	)
	return TOGGLE_CHECK + words.x + status.x + 2 * TOGGLE_GAP


## A toggle row: a ✓-box (capture green on, grey off), a label, and a Silkscreen
## ON/OFF status. The whole row is one focusable button (handoff Toggle), so mouse,
## keyboard and controller all flip it — and, like a segmented group, its
## explanation hangs off the words rather than off the whole row.
##
## The status sits tight after its own label rather than pushed to the row's far
## edge: hard right it landed against the *next* toggle's box, and a state word
## reads as belonging to whichever label it touches (COM-258 QA).
static func toggle(
	text: String, is_on: bool, tip: String, tip_detail: String, on_change: Callable
) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = is_on
	button.custom_minimum_size = Vector2(toggle_width(text), 16)
	var ghost := UiTheme.flat(Color(0, 0, 0, 0))
	button.add_theme_stylebox_override("normal", ghost)
	button.add_theme_stylebox_override("hover", ghost)
	button.add_theme_stylebox_override("pressed", ghost)
	button.add_theme_stylebox_override("focus", UiTheme.focus_box())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", TOGGLE_GAP)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(row)

	var check := Panel.new()
	check.custom_minimum_size = Vector2(TOGGLE_CHECK, TOGGLE_CHECK)
	var mark := Label.new()
	mark.text = "✓"
	mark.add_theme_font_override("font", UiTheme.stat(true))
	mark.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	mark.add_theme_color_override("font_color", UiTheme.SLATE_900)
	mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check.add_child(mark)
	row.add_child(check)

	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.display())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	label.add_theme_color_override("font_color", UiTheme.INK)
	# Shrunk to its own string, so the underlined words and the hover target are
	# the same rect.
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	var status := Label.new()
	status.add_theme_font_override("font", UiTheme.stat())
	status.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status)
	UiTheme.make_decoration(row)
	# After the decoration pass, never before: that pass silences the whole subtree
	# and a silenced label emits no `mouse_entered` (see UiTheme.make_decoration),
	# so the words are the one piece of dress reopened to the pointer. The row is
	# the one focusable control here, so that is where the tip's focus half goes.
	Tooltip.attach(label, tip, tip_detail, Tooltip.Side.BOTTOM).follow_focus(button)

	var repaint := func(on: bool) -> void:
		_paint_check(check, mark, on)
		status.text = "ON" if on else "OFF"
		status.add_theme_color_override("font_color", UiTheme.CAPTURE if on else UiTheme.NEUTRAL)
	repaint.call(is_on)
	# After the decoration pass and after the tip, for the reason stated on
	# `touchable`: the 12x12 check box inside this row is the smallest control in
	# the shell, and the row is what a finger aims at.
	UiKit.touchable(button)
	button.toggled.connect(
		func(pressed: bool) -> void:
			repaint.call(pressed)
			on_change.call(pressed)
	)
	return button


## A faction identity chip — a coloured dot and the seat's faction name, the
## classic meridian/aurora identities a commander-less match plays as. Speaks
## faction, never "Red"/"Blue" (faction-identity D5): the words are the theme's,
## the hue is CommanderVisuals', resolved through the default identity (plan D4).
static func identity_chip(identity: SideIdentity, team: int, role: String) -> Control:
	var theme := identity.theme(team)
	var chip := PanelContainer.new()
	var box := UiTheme.bordered(UiTheme.PAPER, UiTheme.HARD_BORDER, UiTheme.BORDER, true)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(6, 6)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", UiTheme.bordered(theme.color, UiTheme.HARD_BORDER))
	row.add_child(dot)

	var label := Label.new()
	label.text = "%s · %s" % [String(theme.key).capitalize(), role]
	label.add_theme_font_override("font", UiTheme.stat())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	label.add_theme_color_override("font_color", UiTheme.INK)
	row.add_child(label)
	chip.add_child(row)
	return chip


## A general's art on a faction-tinted field, clipped to `size` — the one bust
## every surface that shows a commander is built from. Six of them kept their own
## TextureRect recipe and disagreed about the crop, which is the drift this kit
## exists to prevent (menu-revamp D1).
##
## The tint stays the caller's, because the three in the tree are deliberate: the
## speech card's darkened field is a reading column, the HUD chip's `color_light`
## is chrome, and the victory lockup stands its bust on the panel's own paper
## (`NO_FIELD`). The crop is not the caller's — it is a function of the field's
## shape, decided by `_crop_for` and nowhere else.
static func commander_bust(commander: CommanderType, size: Vector2, tint: Color) -> Panel:
	var field := Panel.new()
	field.custom_minimum_size = size
	field.clip_contents = true
	var art := TextureRect.new()
	art.name = _BUST_ART
	art.texture_filter = CommanderVisuals.ART_FILTER
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if _crop_for(size) == BustCrop.WHOLE_FITTED
		else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	)
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(art)
	bind_bust(field, commander, tint)
	return field


## Points a built bust at another general, for the four surfaces that outlive the
## match's commanders. It asks `_crop_for` the same field it was built with, so
## the two readings are one answer rather than a stored copy of it.
static func bind_bust(bust: Panel, commander: CommanderType, tint: Color) -> void:
	bust.add_theme_stylebox_override("panel", UiTheme.flat(tint))
	var art := bust.get_node(NodePath(_BUST_ART)) as TextureRect
	if _crop_for(bust.custom_minimum_size) == BustCrop.FACE:
		art.texture = CommanderVisuals.face_for(commander)
	else:
		art.texture = CommanderVisuals.portrait_for(commander)


## Waits a frame for a floating card to be laid out, then answers whether it is
## still there to be placed. A `PanelContainer`'s size is only true once its labels
## have been laid out, so a card that positions itself off its own size has to
## measure a frame late — and by then a rematch, a menu exit or a batch scene change
## may have freed it, or a `hide` may have left its size stale. `false` means place
## nothing.
static func settled(card: Control) -> bool:
	await card.get_tree().process_frame
	if not card.is_inside_tree() or not card.visible:
		return false
	card.reset_size()
	return true


# --- internals ---------------------------------------------------------------


## Pressed and released, the way the key itself arrives. Only the press does
## anything today — every reader of these three asks `is_action_pressed` on the
## event — but an action fed in and never let go stays held in `Input` for the
## rest of the match, and that is a trap laid for the first line that polls one.
static func _send_action(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


## What a field of this shape shows of a general, and the one statement of it.
##
## A field tall enough to hold the drawing stands it there whole — the portrait is
## a framed window with the head breaking over its top edge, and filling a band
## that wide can only cut that composition in half.
##
## A field that names a square shorter than a bust is a chip: fitted whole its head
## lands under 40px, where two generals stop telling apart, so it shows the face
## crop instead.
##
## A field that names a short *band*, or names no height at all and takes what a
## container hands it, gets the drawing whole and covered. The face region is a
## square, and covering a wide band with it magnifies a head past its own art;
## covered whole is the reading the commander-select tile has always drawn (#358)
## and this is where that stays said.
static func _crop_for(size: Vector2) -> BustCrop:
	if size.y >= _BUST_MIN_H:
		return BustCrop.WHOLE_FITTED
	if size.y > 0.0 and size.x <= size.y:
		return BustCrop.FACE
	return BustCrop.WHOLE_COVERED


## A micro-label carrying its group's explanation, added to `into` in place: shrunk
## to its own string so the dotted underline, the hover target and the words are one
## rect, and opening downward so the tip lands inside the panel it heads rather than
## over whatever is behind it (handoff integration note 3). The tip comes back so
## its focus half can be mirrored onto the group's own focusable control.
static func _tip_label(into: Container, text: String, tip: String, tip_detail: String) -> Tooltip:
	var label := micro_label(text)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	into.add_child(label)
	return Tooltip.attach(label, tip, tip_detail, Tooltip.Side.BOTTOM)


static func _paint_check(check: Panel, mark: Label, on: bool) -> void:
	var fill := UiTheme.CAPTURE if on else UiTheme.PAPER_2
	var box := UiTheme.bordered(fill, UiTheme.HARD_BORDER, UiTheme.BORDER, true)
	check.add_theme_stylebox_override("panel", box)
	mark.visible = on
