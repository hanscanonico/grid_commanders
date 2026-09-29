class_name CinemaFrame
extends Control
## The flat half of a board cinematic, drawn over the 3D view: the letterbox,
## the fade out of black a scene opens on, the mission's title card, the
## dialogue window (`DialogueWindow`) placed over whoever is speaking, and a
## Command Power's title and flash.
##
## Posed, never self-timed — every number arrives from the cinematic's clock —
## so it holds no tween. Nothing here takes the pointer: a click falls through
## to the battle, whose press is what advances the line.

const BAR_H := 28.0
const BAR_PAD := 6.0
const SIDE_PAD := 12.0
const BAR_INK := Color("#05070b")
## Room kept between a dialogue window and the head it points at, and between
## the window and the picture's edges.
const HEAD_GAP := 14.0
const EDGE_GAP := 6.0
const BLURB_WIDTH := 440
const TITLE_RULE := Vector2(48, 1)
## How much larger the power's name starts before it lands.
const TITLE_SLAM := 0.6
const FLASH_ALPHA := 0.55

var _top: ColorRect
var _bottom: ColorRect
var _fade: ColorRect
var _flash: ColorRect
var _window: DialogueWindow
var _card: VBoxContainer
var _card_title: Label
var _card_place: Label
var _power: VBoxContainer
var _eyebrow: Label
var _power_name: Label
var _blurb: Label
var _hint: Label


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_flash = _rect(self, Color.TRANSPARENT)
	_window = DialogueWindow.new()
	add_child(_window)
	_build_card()
	_fade = _rect(self, Color.BLACK)
	_top = _rect(self, BAR_INK)
	_bottom = _rect(self, BAR_INK)
	_build_power()
	_hint = UiTheme.hud_label("ESC  SKIP", UiTheme.SIZE_SEGMENT, UiTheme.INK_3)
	_hint.visible = not MobileProfile.active()
	_top.add_child(_hint)
	DialogueWindow.quiet(self)


## The part of the screen between the bars as they stand at rest.
func picture() -> Rect2:
	var view := get_viewport_rect().size
	var top := _top_height()
	return Rect2(0, top, view.x, view.y - top - BAR_H)


## Fills the dialogue window for `speaker` saying `words` (the narrator when
## `speaker` is null), with nothing typed yet.
func say(speaker: CommanderType, words: String) -> void:
	_window.say(speaker, words)


func letters_at(typed: float) -> int:
	return _window.letters_at(typed)


## The mission's title card: its name, and where it is fought.
func show_card(title: String, place: String) -> void:
	_card_title.text = title.to_upper()
	_card_place.text = place.to_upper()
	_card_place.visible = not place.is_empty()


## A Command Power's title card, in the top bar: who, the power's name and what
## it does. It lands when `pose_power` says so.
func show_power(
	eyebrow: String, title: String, blurb: String, faction: CommanderVisuals.FactionTheme
) -> void:
	_eyebrow.text = eyebrow
	_eyebrow.add_theme_color_override("font_color", faction.color_light)
	_power_name.text = title
	_power_name.add_theme_color_override("font_color", faction.color_light)
	_blurb.text = blurb
	_blurb.visible = not blurb.is_empty()
	_flash.color = Color(faction.color_light, 0.0)
	_power.visible = true


func hide_power() -> void:
	_power.visible = false


## The bars (0 out of frame, 1 home), how black the screen still is and how
## bright the power's flash still is.
func pose_bars(bars: float, fade: float, flash: float) -> void:
	visible = bars > 0.0 or fade > 0.0
	var view := get_viewport_rect().size
	size = view
	var eased := smoothstep(0.0, 1.0, bars)
	var top_h := _top_height()
	_top.size = Vector2(view.x, top_h)
	_top.position = Vector2(0, -top_h * (1.0 - eased))
	_bottom.size = Vector2(view.x, BAR_H)
	_bottom.position = Vector2(0, view.y - BAR_H * eased)
	var hint := _hint.get_combined_minimum_size()
	_hint.position = Vector2(view.x - hint.x - SIDE_PAD, (BAR_H - hint.y) / 2.0).round()
	_fade.size = view
	_fade.color.a = clampf(fade, 0.0, 1.0)
	_flash.size = view
	_flash.color.a = FLASH_ALPHA * clampf(flash, 0.0, 1.0)


## The dialogue window `open` of the way unfurled with `typed` of its words
## out. `anchor` is the speaker's head on screen: the window stands over it
## with its tail pointing down at it, or under it when there is no room above.
## The narrator's window (`anchored` false) sits low in the picture.
func pose_window(
	open: float, typed: float, cursor: bool, anchor: Vector2, anchored: bool, clock: float
) -> void:
	_window.open = open
	_window.cursor_on = cursor
	_window.clock = clock
	var frame := picture()
	var box := _window.size
	var at := Vector2((frame.size.x - box.x) / 2.0, frame.end.y - box.y - EDGE_GAP * 2.0)
	_window.has_tail = anchored
	if anchored:
		at.x = clampf(
			anchor.x - box.x / 2.0, frame.position.x + EDGE_GAP, frame.end.x - box.x - EDGE_GAP
		)
		at.y = anchor.y - HEAD_GAP - box.y
		if at.y < frame.position.y + EDGE_GAP:
			at.y = minf(anchor.y + HEAD_GAP * 3.0, frame.end.y - box.y - EDGE_GAP)
		_window.tail_tip = anchor - at.round()
	_window.position = at.round()
	_window.pose(typed)


## The title card `amount` of the way in (0 gone, 1 fully shown).
func pose_card(amount: float) -> void:
	_card.visible = amount > 0.0
	_card.modulate.a = clampf(amount, 0.0, 1.0)
	var box := _card.get_combined_minimum_size()
	_card.size = box
	var frame := picture()
	_card.position = (frame.position + (frame.size - box) / 2.0).round()


## The power's title `amount` of the way landed.
func pose_power(amount: float) -> void:
	if not _power.visible:
		return
	var box := _power.get_combined_minimum_size()
	_power.size = box
	_power.position = ((Vector2(size.x, _top_height()) - box) / 2.0).round()
	_power.pivot_offset = box / 2.0
	var landed := clampf(amount, 0.0, 1.0)
	_power.scale = Vector2.ONE * (1.0 + TITLE_SLAM * (1.0 - landed) * (1.0 - landed))
	_power.modulate.a = landed


func _top_height() -> float:
	if _power != null and _power.visible:
		return maxf(BAR_H, _power.get_combined_minimum_size().y + BAR_PAD * 2.0)
	return BAR_H


func _build_card() -> void:
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 3)
	_card.visible = false
	add_child(_card)
	var headline := HBoxContainer.new()
	headline.add_theme_constant_override("separation", 10)
	headline.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_child(headline)
	headline.add_child(_rule())
	_card_title = Label.new()
	_card_title.add_theme_font_override("font", UiTheme.display(true))
	_card_title.add_theme_font_size_override("font_size", UiTheme.SIZE_BANNER)
	_card_title.add_theme_color_override("font_color", UiTheme.WHITE)
	_card_title.add_theme_color_override("font_outline_color", BAR_INK)
	_card_title.add_theme_constant_override("outline_size", 4)
	headline.add_child(_card_title)
	headline.add_child(_rule())
	_card_place = UiTheme.hud_label("", UiTheme.SIZE_SEGMENT, UiTheme.WHITE)
	_card_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_place.add_theme_color_override("font_outline_color", BAR_INK)
	_card_place.add_theme_constant_override("outline_size", 3)
	_card.add_child(_card_place)


func _build_power() -> void:
	_power = VBoxContainer.new()
	_power.add_theme_constant_override("separation", 1)
	_power.visible = false
	_top.add_child(_power)
	_eyebrow = UiTheme.hud_label("", UiTheme.SIZE_SEGMENT, UiTheme.WHITE)
	_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power.add_child(_eyebrow)
	_power_name = Label.new()
	_power_name.add_theme_font_override("font", UiTheme.display(true))
	_power_name.add_theme_font_size_override("font_size", UiTheme.SIZE_BANNER)
	_power_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power.add_child(_power_name)
	_blurb = UiTheme.hud_label("", UiTheme.SIZE_SEGMENT, UiTheme.NEUTRAL_LIGHT)
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(BLURB_WIDTH, 0)
	_power.add_child(_blurb)


static func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = UiTheme.WHITE
	rule.custom_minimum_size = TITLE_RULE
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rule


static func _rect(parent: Control, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	parent.add_child(rect)
	return rect
