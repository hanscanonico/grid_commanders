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

## Which side of its trigger the slab opens on. A side is a request, not a
## promise: `_resolved_side` flips it when the slab would leave the viewport.
##
## Above or below, and deliberately nothing else: every tip in the game opens
## downward into the panel it belongs to (the callers all pass BOTTOM), and a
## left/right pair bought two more arms in four places for a placement nobody
## asks for. A slab is 110px wide on a 640px canvas — it goes beside a control
## far less comfortably than it goes under one.
##
## Spelled `Tooltip.Side` wherever it is written as a *type* — in a script that
## registers a global class, a bare `Side` annotation resolves to a different
## type than the values it is compared with, and the file will not parse.
enum Side { TOP, BOTTOM }

## Canvas pixels, so every metric is half the handoff's and doubles on screen
## (UiTheme's div-2 rule). The slab never sizes to its text: a long string wraps
## inside WIDTH instead of stretching across the board.
const WIDTH := 110  # handoff 220
const DELAY_SECONDS := 0.35
const GAP := 5  # handoff 10 — trigger edge to slab
const MARGIN := 4  # handoff 8 — the viewport edge a clamped slab keeps off
const PAD_H := 5  # handoff 10
const PAD_V := 4  # handoff 8

## The overlay every tip is mounted on. A CanvasLayer above the scene so a slab is
## never clipped by the panel, scroll container or map cell it belongs to, and
## never laid out by them either. The layer also carries the one `FocusSource`
## every tip reads to tell a Tab from a click.
const LAYER_NAME := "TooltipLayer"

var _trigger: Control
var _side := Side.TOP
var _slab: PanelContainer
var _label: Label
var _detail: Label
var _tail: NotchTail
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
		text_trigger.add_child(DottedUnderline.new())

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
##
## Only *keyboard* focus opens it, the rule a browser calls `:focus-visible`.
## `focus_entered` does not say how focus arrived, and a pointer press grabs focus
## for any focusable control — so without the gate, clicking a segment would fire
## the group's explanation over the row just used, which is precisely what the
## micro-label rule exists to prevent. Blur still closes, whatever moved focus.
func follow_focus(control: Control) -> void:
	control.focus_entered.connect(_request_focused)
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

	# Built by hand rather than through UiKit.pad: UiKit depends on Tooltip, so
	# folding this one in would close a class_name cycle.
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
	_detail = _line(UiTheme.stat(), UiTheme.SIZE_STAT, UiTheme.NEUTRAL_LIGHT)
	column.add_child(_detail)

	_tail = NotchTail.new()
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
	FocusSource.ensure(layer)
	layer.add_child(self)


# --- opening and closing ------------------------------------------------------


func _request() -> void:
	if not is_inside_tree() or _trigger == null or not _trigger.is_visible_in_tree():
		return
	_wanted = true
	_timer.start()


## `follow_focus`'s half of the door, open only to the keyboard and the pad. The
## pointer keeps its own way in — the trigger's `mouse_entered`, ungated.
func _request_focused() -> void:
	if not FocusSource.by_keyboard:
		return
	_request()


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
	var below := side == Side.BOTTOM
	var top := rect.end.y + GAP if below else rect.position.y - GAP - size.y
	var pos := Vector2(rect.get_center().x - size.x * 0.5, top)
	# Both axes, not just the one the side does not choose: `_resolved_side` returns
	# the requested side unchanged when *neither* side has room, and copy that comes
	# from a map file can grow the slab taller than any code here decided.
	pos.x = clampf(pos.x, MARGIN, maxf(MARGIN, view.x - MARGIN - size.x))
	pos.y = clampf(pos.y, MARGIN, maxf(MARGIN, view.y - MARGIN - size.y))
	position = pos.round()
	_tail.place(below, rect.get_center() - position, size)


## The requested side, unless the slab would run off the viewport there and the
## opposite side has room. A 640x360 canvas is small enough that the bottom row of
## a panel has nowhere below it to open into.
func _resolved_side(rect: Rect2, view: Vector2) -> Tooltip.Side:
	var above := rect.position.y
	var below := view.y - rect.end.y
	if _side == Side.TOP and _short(above) and not _short(below):
		return Side.BOTTOM
	if _side == Side.BOTTOM and _short(below) and not _short(above):
		return Side.TOP
	return _side


## Is `room` — the gap between one trigger edge and the viewport — too small for
## the slab, its gap and its margin?
func _short(room: float) -> bool:
	return room < size.y + GAP + MARGIN
