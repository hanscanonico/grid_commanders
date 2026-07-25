class_name Tooltip
extends Control
## An anchored explanation for a control whose label cannot carry the whole idea
## — the design system's Tooltip, transcribed into Godot (handoff `Tooltip.jsx`).
##
## It replaces Godot's built-in `tooltip_text` across the menu. The native tip is
## a separate unfocusable Window drawn in the default theme: translucent over the
## board, set in the OS font at OS size, sized to the viewport rather than to its
## trigger, and floating at the cursor with no visible referent. This one is an
## opaque slate slab with an ink border, a hard shadow and a notched tail that
## points at the control it describes. Every colour, font and metric is UiTheme's,
## so a tip reads like the panel it sits on.
##
## Attach it to the *micro-label* of a group, never to the group's control: a tip
## on a segmented row fires while the player is only reaching for a segment.
## `attach` dresses a Label trigger with the dotted underline and help cursor that
## make it discoverable; the tip opens after a delay, so sweeping across a row does
## not strobe, and closes on leave, blur or `ui_cancel`.
##
## Hover and focus deliberately have different sources — see `follow_focus`, which
## mirrors the focus half onto the control the label heads, so a keyboard-only
## player reaches the same explanation without the label joining the tab order.
##
## Presentation only, like every other node under scenes/: nothing in core/ or ai/
## knows a tooltip exists, and the copy is handed in by the caller.
##
## A slab lives on an overlay layer and takes no space in the flow it points into,
## so where a tip is *pinned* — a coach mark, a specimen — and must not cover the
## control it explains, reserve it a real block in the layout (a row of its own),
## never a margin tuned to today's string: the height moves with the words. A tip
## opened by *focus* is that pinned case: it stays up for as long as its trigger
## holds focus, so tabbing through the map picker keeps a slab over the cell below
## the focused one, and a focused tip and a hovered one can be up at once. The menu
## accepts the overlap rather than reserving a block for it — the slab is
## MOUSE_FILTER_IGNORE, so it never blocks the control it covers, and the words
## underneath it are one keystroke from being uncovered again.
##
## Three of the handoff's props are deliberately absent. `align` exists there to
## hand-tune tips on edge-adjacent controls, which the viewport clamp below already
## handles — every tip centres on its trigger and the tail follows. `disabled` and
## `defaultOpen` serve specimens and coach marks, neither of which this game has.

## Where the slab sits relative to its trigger. A side is a request, not a
## promise: `_resolved_side` flips it when the slab would leave the viewport.
##
## Spelled `Tooltip.Side` wherever it is written as a *type* — in a script that
## registers a global class, a bare `Side` annotation resolves to a different
## type than the values it is compared with, and the file will not parse.
enum Side { TOP, BOTTOM, LEFT, RIGHT }

## Canvas pixels, so every metric is half the handoff's and doubles on screen
## (UiTheme's div-2 rule). The slab never sizes to its text: a long string wraps
## inside WIDTH instead of stretching across the board.
const WIDTH := 110  # handoff 220
const DELAY_SECONDS := 0.35
const GAP := 5  # handoff 10 — trigger edge to slab
const MARGIN := 4  # handoff 8 — the viewport edge a clamped slab keeps off
const PAD_H := 5  # handoff 10
const PAD_V := 4  # handoff 8
## The notch. Its own edges are BORDER, not the slab's PANEL_BORDER: on a
## triangle this small a 2px inset swallows the slate core whole, and the notch
## reads as a solid ink arrowhead instead of an opening in the slab.
const TAIL_W := 10
const TAIL_H := 5
const TAIL_BORDER := UiTheme.BORDER

## The overlay every tip is mounted on. A CanvasLayer above the scene so a slab is
## never clipped by the panel, scroll container or map cell it belongs to, and
## never laid out by them either.
const LAYER_NAME := "TooltipLayer"

var _trigger: Control
var _side := Side.TOP
var _slab: PanelContainer
var _label: Label
var _detail: Label
var _tail: _Tail
var _timer: Timer
## Set on hover/focus and cleared on leave/blur, so the frame the slab spends
## being measured cannot resurrect a tip the pointer has already left.
var _wanted := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


# --- the component ------------------------------------------------------------


## Wires a tip to `trigger`. A Label trigger is also dressed with the dotted
## underline and help cursor the handoff asks for — an interactive trigger (a
## button) keeps its own affordances, including its own cursor.
##
## The trigger has to be the control the pointer actually lands on. `tooltip_text`
## did not care: the engine walks up the tree looking for one, so a tip survived a
## child that swallowed the mouse. A signal does not walk, so a decorative child
## of the trigger must be MOUSE_FILTER_IGNORE — which is what it should have been
## anyway, since it was eating the trigger's hover styling too.
static func attach(trigger: Control, label: String, detail := "", side := Side.TOP) -> Tooltip:
	var tip := Tooltip.new()
	tip._trigger = trigger
	tip._side = side
	tip.set_copy(label, detail)

	# PASS, not STOP: hover reaches the tip while clicks still reach whatever is
	# underneath — a Label inside a toggle must not swallow the toggle's press.
	if trigger.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		trigger.mouse_filter = Control.MOUSE_FILTER_PASS
	var text_trigger := trigger as Label
	if text_trigger != null:
		text_trigger.mouse_default_cursor_shape = Control.CURSOR_HELP
		text_trigger.add_child(_Underline.new())

	trigger.mouse_entered.connect(tip._request)
	trigger.mouse_exited.connect(tip.close)
	trigger.focus_entered.connect(tip._request)
	trigger.focus_exited.connect(tip.close)
	trigger.visibility_changed.connect(tip._on_trigger_visibility)
	trigger.tree_exiting.connect(tip._on_trigger_gone)
	if trigger.is_inside_tree():
		tip._mount()
	else:
		trigger.tree_entered.connect(tip._mount, CONNECT_ONE_SHOT)
	return tip


## Mirrors the tip's *focus* source onto the control its trigger label heads — each
## segment of a segmented row, the toggle button itself, the Continue button. One
## tip, one slab, one set of state: this only adds a second way in.
##
## Hover and focus have different triggers on purpose. A pointer crossing a segment
## is on its way to press it, not asking what the group means, which is the whole
## reason the hover trigger is the micro-label; but focus *arriving* on a control is
## an unambiguous "I am here now", and the label can never be that arrival — it is
## not in the tab order, and putting it there would add a stop that does nothing
## when pressed. A control that cannot take focus (a disabled Continue) simply never
## opens the tip this way; its caption stays hoverable.
func follow_focus(control: Control) -> void:
	control.focus_entered.connect(_request)
	control.focus_exited.connect(close)


## The words. `label` is one short line in sentence case with no trailing period;
## `detail` is the caveat, set in uppercase Silkscreen micro beneath it. Copy may
## change while a tip is attached — Continue names the save it would resume — so
## the slab is measured on every open rather than once at attach.
func set_copy(label: String, detail := "") -> void:
	_label.text = label
	_detail.text = detail.to_upper()
	_detail.visible = not detail.is_empty()


func close() -> void:
	_wanted = false
	_timer.stop()
	visible = false
	set_process_input(false)


# --- construction -------------------------------------------------------------


func _build() -> void:
	_slab = PanelContainer.new()
	_slab.add_theme_stylebox_override("panel", UiTheme.dark_panel_box())
	_slab.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slab)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", PAD_H)
	pad.add_theme_constant_override("margin_right", PAD_H)
	pad.add_theme_constant_override("margin_top", PAD_V)
	pad.add_theme_constant_override("margin_bottom", PAD_V)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slab.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(column)

	_label = _line(UiTheme.display(), UiTheme.SIZE_TIP, UiTheme.WHITE)
	column.add_child(_label)
	_detail = _line(UiTheme.stat(), UiTheme.SIZE_MICRO, UiTheme.NEUTRAL_LIGHT)
	column.add_child(_detail)

	_tail = _Tail.new()
	add_child(_tail)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DELAY_SECONDS
	_timer.timeout.connect(_open)
	add_child(_timer)


func _line(font: Font, font_size: int, color: Color) -> Label:
	var line := Label.new()
	line.add_theme_font_override("font", font)
	line.add_theme_font_size_override("font_size", font_size)
	line.add_theme_color_override("font_color", color)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Godot leads a wrapped line by 3px, which at these sizes reads as a paragraph
	# break rather than a line break. The handoff's --leading-snug is tighter than
	# the box the glyphs already sit in, so the extra leading simply goes.
	line.add_theme_constant_override("line_spacing", 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Mounts on the scene's tooltip overlay, creating it on first use. The scene root
## is found by walking up from the trigger rather than through
## `SceneTree.current_scene`, which is not yet assigned while the root scene's own
## `_ready` builds the controls that attach these tips.
func _mount() -> void:
	if _trigger == null or not _trigger.is_inside_tree():
		return
	var root := _trigger as Node
	var top := _trigger.get_tree().root
	while root.get_parent() != null and root.get_parent() != top:
		root = root.get_parent()
	var layer := root.get_node_or_null(NodePath(LAYER_NAME)) as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = LAYER_NAME
		layer.layer = 1
		root.add_child(layer)
	layer.add_child(self)


# --- opening and closing ------------------------------------------------------


func _request() -> void:
	if not is_inside_tree() or _trigger == null or not _trigger.is_visible_in_tree():
		return
	_wanted = true
	_timer.start()


## Sizes, places and reveals the slab. The width is fixed, so the height is
## whatever the wrapped copy needs — and a container only wraps its labels once it
## has been given that width, which is why the measurement costs a frame. The slab
## spends that frame transparent rather than hidden: an invisible Control is not
## laid out, so hiding it would measure nothing.
func _open() -> void:
	if not _wanted:
		return
	modulate = Color(1, 1, 1, 0)
	size = Vector2(WIDTH, 0)
	visible = true
	await get_tree().process_frame
	if not _wanted or not is_inside_tree():
		return
	var anchor := _visible_trigger_rect()
	# Scrolled entirely out of its clip: there is nothing on screen to point at, so
	# a slab would be the referent-less float this component exists to replace.
	if anchor.size.x <= 0.0 or anchor.size.y <= 0.0:
		close()
		return
	size = Vector2(WIDTH, _slab.get_combined_minimum_size().y)
	_place(anchor)
	modulate = Color(1, 1, 1, 1)
	set_process_input(true)


## Escape dismisses, as it does in the handoff — and is left unhandled, so a menu
## that means something else by it still hears the press.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()


func _on_trigger_visibility() -> void:
	if _trigger != null and not _trigger.is_visible_in_tree():
		close()


func _on_trigger_gone() -> void:
	close()
	queue_free()


# --- placement ----------------------------------------------------------------


## The part of the trigger the player can actually see and hover: its global rect
## intersected with every clipping ancestor's. A map cell scrolled half out of the
## picker is hit-tested only on the sliver the ScrollContainer shows, so anchoring
## to the whole cell would drop the slab below the picker with its tail pointing at
## an edge that is scrolled out of sight.
func _visible_trigger_rect() -> Rect2:
	var rect := _trigger.get_global_rect()
	var node := _trigger.get_parent()
	while node != null:
		var clipper := node as Control
		if clipper != null and clipper.clip_contents:
			rect = rect.intersection(clipper.get_global_rect())
		node = node.get_parent()
	return rect


## Anchors the slab to the visible part of the trigger and the tail to its centre.
## The slab slides inward from a viewport edge and the tail stays put, so an
## edge-adjacent control needs no hand-tuning — and where the requested side has no
## room at all, `_resolved_side` puts the slab on the opposite one instead.
func _place(rect: Rect2) -> void:
	var view := get_viewport_rect().size
	var side := _resolved_side(rect, view)
	var pos := Vector2.ZERO
	match side:
		Side.TOP:
			pos = Vector2(rect.get_center().x - size.x * 0.5, rect.position.y - GAP - size.y)
		Side.BOTTOM:
			pos = Vector2(rect.get_center().x - size.x * 0.5, rect.end.y + GAP)
		Side.LEFT:
			pos = Vector2(rect.position.x - GAP - size.x, rect.get_center().y - size.y * 0.5)
		Side.RIGHT:
			pos = Vector2(rect.end.x + GAP, rect.get_center().y - size.y * 0.5)
	# Both axes, not just the one the side does not choose: `_resolved_side` returns
	# the requested side unchanged when *neither* side has room, and copy that comes
	# from a map file can grow the slab taller than any code here decided.
	pos.x = clampf(pos.x, MARGIN, maxf(MARGIN, view.x - MARGIN - size.x))
	pos.y = clampf(pos.y, MARGIN, maxf(MARGIN, view.y - MARGIN - size.y))
	position = pos.round()
	_tail.place(side, rect.get_center() - position, size)


## The requested side, unless the slab would run off the viewport there and the
## opposite side has room. A 640x360 canvas is small enough that the bottom row of
## a panel has nowhere below it to open into.
func _resolved_side(rect: Rect2, view: Vector2) -> Tooltip.Side:
	match _side:
		Side.TOP:
			if _short(rect.position.y) and not _short(view.y - rect.end.y):
				return Side.BOTTOM
		Side.BOTTOM:
			if _short(view.y - rect.end.y) and not _short(rect.position.y):
				return Side.TOP
		Side.LEFT:
			if _short(rect.position.x) and not _short(view.x - rect.end.x):
				return Side.RIGHT
		Side.RIGHT:
			if _short(view.x - rect.end.x) and not _short(rect.position.x):
				return Side.LEFT
	return _side


## Is `room` — the gap between one trigger edge and the viewport — too small for
## the slab, its gap and its margin?
func _short(room: float) -> bool:
	var span := size.y if _side == Side.TOP or _side == Side.BOTTOM else size.x
	return room < span + GAP + MARGIN


# --- the notch and the dotted underline ---------------------------------------


## The notched tail: an ink triangle with a slate core whose base runs past the
## slab's border, so the notch opens into the slab rather than sitting on it.
## Drawn rather than rotated — a rotated Control resamples, and this UI is
## pixel-crisp everywhere else.
class _Tail:
	extends Control

	var _side := Side.BOTTOM

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Puts the notch on the slab edge that faces the trigger, centred on
	## `anchor` (the trigger's centre, in the slab's own coordinates) but never
	## so far along the edge that it leaves the slab's border behind.
	func place(side: Tooltip.Side, anchor: Vector2, slab: Vector2) -> void:
		_side = side
		var thick := float(UiTheme.PANEL_BORDER)  # the slab's border, its no-go strip
		match side:
			Side.TOP:
				size = Vector2(TAIL_W, TAIL_H)
				position = Vector2(_along(anchor.x, slab.x, TAIL_W, thick), slab.y)
			Side.BOTTOM:
				size = Vector2(TAIL_W, TAIL_H)
				position = Vector2(_along(anchor.x, slab.x, TAIL_W, thick), -TAIL_H)
			Side.LEFT:
				size = Vector2(TAIL_H, TAIL_W)
				position = Vector2(slab.x, _along(anchor.y, slab.y, TAIL_W, thick))
			Side.RIGHT:
				size = Vector2(TAIL_H, TAIL_W)
				position = Vector2(-TAIL_H, _along(anchor.y, slab.y, TAIL_W, thick))
		position = position.round()
		queue_redraw()

	func _along(anchor: float, span: float, tail: float, thick: float) -> float:
		return clampf(
			anchor - tail * 0.5, thick + 1.0, maxf(thick + 1.0, span - tail - thick - 1.0)
		)

	func _draw() -> void:
		var thick := float(TAIL_BORDER)
		var outer := PackedVector2Array(
			[Vector2(0, TAIL_H), Vector2(TAIL_W * 0.5, 0), Vector2(TAIL_W, TAIL_H)]
		)
		# The core's base runs past the slab's own border, so the notch opens into
		# the slab's fill rather than sitting on top of its outline.
		var inner := _inset(outer, thick)
		inner[0].y = TAIL_H + UiTheme.PANEL_BORDER
		inner[2].y = TAIL_H + UiTheme.PANEL_BORDER
		draw_colored_polygon(_orient(outer), UiTheme.HARD_BORDER)
		draw_colored_polygon(_orient(inner), UiTheme.SLATE_800)

	## The triangle drawn apex-up, mapped onto the side the notch actually sits
	## on — a flip or an axis swap, so the geometry is written once.
	func _orient(points: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for point in points:
			match _side:
				Side.TOP:
					out.append(Vector2(point.x, TAIL_H - point.y))
				Side.BOTTOM:
					out.append(point)
				Side.LEFT:
					out.append(Vector2(TAIL_H - point.y, point.x))
				Side.RIGHT:
					out.append(Vector2(point.y, point.x))
		return out

	## Every edge of a triangle pulled `thick` pixels inward: the triangle scaled
	## about its incentre, whose distance to all three edges is the inradius.
	func _inset(tri: PackedVector2Array, thick: float) -> PackedVector2Array:
		var a := tri[1].distance_to(tri[2])
		var b := tri[2].distance_to(tri[0])
		var c := tri[0].distance_to(tri[1])
		var perimeter := a + b + c
		var incentre := (tri[0] * a + tri[1] * b + tri[2] * c) / perimeter
		var radius := absf((tri[1] - tri[0]).cross(tri[2] - tri[0])) / perimeter
		var shrink := maxf((radius - thick) / radius, 0.0) if radius > 0.0 else 0.0
		var out := PackedVector2Array()
		for point in tri:
			out.append(incentre + (point - incentre) * shrink)
		return out


## The dotted rule under a label that carries a tip — the one hint that hovering
## it will explain something. Drawn under the *text*, not the control, so a label
## wider than its string is still underlined only where the words are.
class _Underline:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		var label := get_parent() as Label
		if label != null:
			label.resized.connect(queue_redraw)

	## Drawn off the *parent's* rect rather than this node's own. A Label is not a
	## container, so a child added to one keeps whatever size it had when it
	## entered the tree — here, none — and an anchored rule would land above the
	## words instead of under them.
	func _draw() -> void:
		var label := get_parent() as Label
		if label == null or label.text.is_empty():
			return
		var rect := label.size
		var font := label.get_theme_font(&"font")
		var font_size := label.get_theme_font_size(&"font_size")
		var span := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var start := 0.0
		if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
			start = roundf((rect.x - span) * 0.5)
		elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			start = rect.x - span
		var color := label.get_theme_color(&"font_color")
		var y := rect.y - 1.0
		var x := maxf(start, 0.0)
		while x < start + span:
			draw_rect(Rect2(x, y, 1, 1), color)
			x += 2.0
