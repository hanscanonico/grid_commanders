class_name CinemaFrame
extends Control
## The flat half of a board cinematic, drawn over the 3D view: the letterbox,
## the subtitle a line is typed into, a Command Power's title card and its
## flash.
##
## Posed, never self-timed — every number arrives from the cinematic's clock —
## so it holds no tween. The speaker's face, name and words are drawn by
## `MissionSpeech`, the one drawer every other surface that speaks a line uses,
## so a general reads the same in a cinematic as on the card it replaces.
##
## Nothing here takes the pointer: a click falls through to the battle, whose
## press is what advances the line.

const BAR_H := 40.0
## The subtitle bar is a little deeper than the top one: two lines of words
## under a name have to fit, and it covers the HUD's own taller bottom bar.
const BOTTOM_MIN_H := 52.0
const BAR_PAD := 7.0
const SIDE_PAD := 12.0
const BAR_INK := Color("#07090d")
## The top bar's title card grows to hold a power's effect text.
const BLURB_WIDTH := 440
const EYEBROW_SIZE := UiTheme.SIZE_SEGMENT
const BLURB_SIZE := UiTheme.SIZE_SEGMENT
## How much larger the power's name starts before it lands.
const TITLE_SLAM := 0.6
const FLASH_ALPHA := 0.55
const CUE_BLINK_HZ := 2.0
## The letterbox is near-black, darker than the card's slate, so a speaker's
## name is lifted off their army's colour to read on it — Iron's dark grey
## otherwise all but disappears.
const NAME_LIFT := 0.3


## The mark at the end of a typed line that says a press moves on.
class Cue:
	extends Control

	const SIZE := Vector2(5, 4)

	func _init() -> void:
		custom_minimum_size = SIZE
		size = SIZE

	func _draw() -> void:
		draw_colored_polygon(
			PackedVector2Array([Vector2.ZERO, Vector2(SIZE.x, 0), Vector2(SIZE.x / 2.0, SIZE.y)]),
			UiTheme.WHITE
		)


var _top: ColorRect
var _top_rule: ColorRect
var _bottom: ColorRect
var _bottom_rule: ColorRect
var _row: HBoxContainer
var _face_slot: CenterContainer
var _copy: VBoxContainer
var _name: Label
var _words: Label
var _cue: Cue
var _titles: VBoxContainer
var _eyebrow: Label
var _title: Label
var _blurb: Label
var _hint: Label
var _flash: ColorRect


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_flash = _rect(self, Color.TRANSPARENT)
	_top = _rect(self, BAR_INK)
	_top_rule = _rect(_top, Color.TRANSPARENT)
	_bottom = _rect(self, BAR_INK)
	_bottom_rule = _rect(_bottom, Color.TRANSPARENT)
	_build_subtitle()
	_build_titles()
	_hint = UiTheme.hud_label("ESC  SKIP", EYEBROW_SIZE, UiTheme.INK_3)
	_hint.visible = not MobileProfile.active()
	_top.add_child(_hint)
	_quiet(self)


## The line being said: `speaker`'s face, name and words, or the narrator's
## words alone when `speaker` is null. The words start untyped.
func say(speaker: CommanderType, words: String) -> void:
	for child in _face_slot.get_children():
		_face_slot.remove_child(child)
		child.queue_free()
	if _name != null:
		_copy.remove_child(_name)
		_name.queue_free()
		_name = null
	var narrated := speaker == null
	_face_slot.visible = not narrated
	if not narrated:
		_face_slot.add_child(MissionSpeech.bust_of(speaker))
		_name = MissionSpeech.name_of(speaker, 0)
		var army := CommanderVisuals.theme_for(speaker).color
		_name.add_theme_color_override("font_color", army.lightened(NAME_LIFT))
		_copy.add_child(_name)
		_copy.move_child(_name, 0)
	var width := MissionSpeech.WIDTH
	if not narrated:
		width -= MissionSpeech.BUST + int(_row.get_theme_constant("separation"))
	_words.custom_minimum_size.x = width
	_words.text = words
	_words.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER if narrated else HORIZONTAL_ALIGNMENT_LEFT
	)
	_words.add_theme_color_override(
		"font_color", UiTheme.NEUTRAL_LIGHT if narrated else UiTheme.WHITE
	)
	_words.visible_ratio = 0.0
	var rule := UiTheme.SLATE_700 if narrated else CommanderVisuals.theme_for(speaker).color
	_bottom_rule.color = rule
	_top_rule.color = rule
	_quiet(_row)


## A Command Power's title card, in the top bar: who, the power's name and what
## it does. It lands when `pose` says so.
func show_title(
	eyebrow: String, title: String, blurb: String, faction: CommanderVisuals.FactionTheme
) -> void:
	_eyebrow.text = eyebrow
	_eyebrow.add_theme_color_override("font_color", faction.color_light)
	_title.text = title
	_title.add_theme_color_override("font_color", faction.color_light)
	_blurb.text = blurb
	_blurb.visible = not blurb.is_empty()
	_flash.color = Color(faction.color_light, 0.0)
	_titles.visible = true


func hide_title() -> void:
	_titles.visible = false


## Poses every part at once. `letterbox` slides the bars in (0 out of frame,
## 1 home), `typed` is how much of the words are showing, `cue` whether the
## advance mark blinks, `title` how far the title card has landed and `flash`
## how bright the power's flash still is. `clock` drives the blink.
func pose(
	letterbox: float, typed: float, cue: bool, title: float, flash: float, clock: float
) -> void:
	visible = letterbox > 0.0
	var view := get_viewport_rect().size
	size = view
	var top_h := BAR_H
	if _titles.visible:
		top_h = maxf(BAR_H, _titles.get_combined_minimum_size().y + BAR_PAD * 2.0)
	var row := _row.get_combined_minimum_size()
	var bottom_h := maxf(BOTTOM_MIN_H, row.y + BAR_PAD * 2.0)
	var eased := smoothstep(0.0, 1.0, letterbox)
	_top.size = Vector2(view.x, top_h)
	_top.position = Vector2(0, -top_h * (1.0 - eased))
	_bottom.size = Vector2(view.x, bottom_h)
	_bottom.position = Vector2(0, view.y - bottom_h * eased)
	_top_rule.size = Vector2(view.x, 1)
	_top_rule.position = Vector2(0, top_h - 1)
	_bottom_rule.size = Vector2(view.x, 1)
	_bottom_rule.position = Vector2.ZERO
	_row.size = row
	_row.position = ((Vector2(view.x, bottom_h) - row) / 2.0).round()
	_words.visible_ratio = clampf(typed, 0.0, 1.0)
	_cue.visible = cue and fmod(clock * CUE_BLINK_HZ, 1.0) < 0.6
	_cue.position = _row.position + row + Vector2(4, -Cue.SIZE.y - 2)
	var hint := _hint.get_combined_minimum_size()
	_hint.position = Vector2(view.x - hint.x - SIDE_PAD, (BAR_H - hint.y) / 2.0).round()
	_pose_title(title, top_h, view.x)
	_flash.size = view
	_flash.color.a = FLASH_ALPHA * clampf(flash, 0.0, 1.0)


func _pose_title(title: float, top_h: float, width: float) -> void:
	if not _titles.visible:
		return
	var box := _titles.get_combined_minimum_size()
	_titles.size = box
	_titles.position = ((Vector2(width, top_h) - box) / 2.0).round()
	_titles.pivot_offset = box / 2.0
	var landed := clampf(title, 0.0, 1.0)
	_titles.scale = Vector2.ONE * (1.0 + TITLE_SLAM * (1.0 - landed) * (1.0 - landed))
	_titles.modulate.a = landed


func _build_subtitle() -> void:
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	_bottom.add_child(_row)
	_face_slot = CenterContainer.new()
	_face_slot.custom_minimum_size = Vector2.ONE * MissionSpeech.BUST
	_face_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_row.add_child(_face_slot)
	_copy = VBoxContainer.new()
	_copy.add_theme_constant_override("separation", 0)
	_row.add_child(_copy)
	_words = MissionSpeech.paragraph("")
	_copy.add_child(_words)
	_cue = Cue.new()
	_bottom.add_child(_cue)


func _build_titles() -> void:
	_titles = VBoxContainer.new()
	_titles.add_theme_constant_override("separation", 1)
	_titles.visible = false
	_top.add_child(_titles)
	_eyebrow = UiTheme.hud_label("", EYEBROW_SIZE, UiTheme.WHITE)
	_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titles.add_child(_eyebrow)
	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.display(true))
	_title.add_theme_font_size_override("font_size", UiTheme.SIZE_BANNER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titles.add_child(_title)
	_blurb = UiTheme.hud_label("", BLURB_SIZE, UiTheme.NEUTRAL_LIGHT)
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(BLURB_WIDTH, 0)
	_titles.add_child(_blurb)


static func _rect(parent: Control, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	parent.add_child(rect)
	return rect


## Every control under `node` lets the pointer through.
static func _quiet(node: Node) -> void:
	var control := node as Control
	if control != null:
		control.mouse_filter = MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_quiet(child)
