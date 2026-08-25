class_name UiKit
extends RefCounted
## The widgets the design system's screens are assembled from: the padded box, the
## micro-label, the divider, the action button, the segmented control, the toggle
## row, the identity chip and the commander bust. Every one of them is drawn out of
## UiTheme's colours, fonts and styleboxes and holds no state of its own.
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
## Presentation only, and no Node held: every builder hands its control back to the
## screen that asked for it and keeps no reference.

## A bust drawn on no field at all — the victory lockup, which stands its portrait
## on the lockup's own paper rather than on a faction colour.
const NO_FIELD := Color(0, 0, 0, 0)

## The field height a whole bust needs. A portrait is a framed window with the head
## about five eighths of the drawing tall, so fitted whole into a shorter field the
## head lands under 40px — where two generals stop telling apart, which is what
## CommanderVisuals.FACE_REGION exists for. A caller that states no height is being
## sized by a container, which can promise none, so it shows the face too.
const _BUST_MIN_H := 64
const _BUST_ART := &"Bust"


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


## A thin ink divider between a panel's rows (handoff --border-soft).
static func rule() -> Control:
	var line := ColorRect.new()
	line.color = UiTheme.BORDER_SOFT
	line.custom_minimum_size = Vector2(0, UiTheme.BORDER)
	return line


## A faction-tinted or cream action button with an optional suffix ("MATCH"),
## appended to the label rather than set as a second run: one Button draws one
## string in one font, so the suffix wears the same Pixelify the label does.
static func action_button(
	text: String,
	suffix: String,
	variant: UiTheme.ButtonVariant,
	theme: CommanderVisuals.FactionTheme
) -> Button:
	var button := Button.new()
	button.text = text if suffix.is_empty() else "%s  %s" % [text, suffix]
	UiTheme.apply_button(button, variant, theme, UiTheme.SIZE_BUTTON)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 20)
	return button


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
		seg_row.add_child(seg)
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


## A toggle row: a ✓-box (capture green on, grey off), a label, and a Silkscreen
## ON/OFF status. The whole row is one focusable button (handoff Toggle), so mouse,
## keyboard and controller all flip it — and, like a segmented group, its
## explanation hangs off the words rather than off the whole row.
static func toggle(
	text: String, is_on: bool, tip: String, tip_detail: String, on_change: Callable
) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = is_on
	button.custom_minimum_size = Vector2(0, 16)
	var ghost := UiTheme.flat(Color(0, 0, 0, 0))
	button.add_theme_stylebox_override("normal", ghost)
	button.add_theme_stylebox_override("hover", ghost)
	button.add_theme_stylebox_override("pressed", ghost)
	button.add_theme_stylebox_override("focus", UiTheme.focus_box())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(row)

	var check := Panel.new()
	check.custom_minimum_size = Vector2(12, 12)
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
	# the same rect; the spacer below keeps ON/OFF hard right where FILL had it.
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

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
## (`NO_FIELD`). The crop is not the caller's — it is a function of the field,
## decided here and nowhere else.
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
		if size.y >= _BUST_MIN_H
		else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	)
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(art)
	bind_bust(field, commander, tint)
	return field


## Points a built bust at another general, for the four surfaces that outlive the
## match's commanders. The crop was settled when the field was built, so the
## texture follows it rather than asking the size a second time.
static func bind_bust(bust: Panel, commander: CommanderType, tint: Color) -> void:
	bust.add_theme_stylebox_override("panel", UiTheme.flat(tint))
	var art := bust.get_node(NodePath(_BUST_ART)) as TextureRect
	if art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		art.texture = CommanderVisuals.portrait_for(commander)
	else:
		art.texture = CommanderVisuals.face_for(commander)


# --- internals ---------------------------------------------------------------


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
