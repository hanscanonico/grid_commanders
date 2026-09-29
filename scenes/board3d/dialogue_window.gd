class_name DialogueWindow
extends Control
## The window a 3D cinematic speaks through, in the style the genre made its
## own: a deep blue field shading down inside a light border, the speaker's face
## at its left, their name over their words, and a cursor that bobs once the
## words are all out. It unfurls from a line as it opens and points a tail at
## whoever is speaking; the narrator's window has no face, no name and no tail.
##
## Posed, never self-timed: the cinematic sets `open`, the typed share of the
## words and where the tail points each frame. The face, the name and the words
## are `MissionSpeech`'s own pieces, so a general reads the same here as on every
## other surface that speaks a line.

const FIELD_TOP := Color("#3a5ac8")
const FIELD_BOTTOM := Color("#0c1850")
const BORDER := Color("#e8edfb")
const EDGE := Color("#070b1e")
const BORDER_PX := 2.0
const PAD := Vector2(9, 7)
## The face chip at twice its size: a whole rung, so it is drawn on whole texels.
const FACE := CommanderVisuals.FACE_SIZE.x * 2
const GAP := 8
const WORDS_WIDTH := 250
const NARRATION_WIDTH := 330
## Words are set a step above body copy: they are read across a cinematic, not
## at a panel's distance.
const WORDS_SIZE := UiTheme.SIZE_SUBTITLE
## A speaker's name is lifted off their army's colour to read on the blue.
const NAME_LIFT := 0.35
const TAIL := Vector2(12, 8)
const CURSOR := Vector2(7, 5)
const CURSOR_BOB_HZ := 3.0

## 0 is a closed line across the window's middle, 1 fully open.
var open := 1.0
## Where the tail's tip is, in this window's own coordinates; no tail when
## `has_tail` is false. A tip below the window points down, above it points up.
var tail_tip := Vector2.ZERO
var has_tail := false
var cursor_on := false
var clock := 0.0

var _row: HBoxContainer
var _face_slot: CenterContainer
var _copy: VBoxContainer
var _name: Label
var _words: Label


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", GAP)
	_row.position = PAD
	add_child(_row)
	_face_slot = CenterContainer.new()
	_face_slot.custom_minimum_size = Vector2.ONE * FACE
	_face_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_row.add_child(_face_slot)
	_copy = VBoxContainer.new()
	_copy.add_theme_constant_override("separation", 1)
	_row.add_child(_copy)
	_words = MissionSpeech.paragraph("", false, WORDS_WIDTH)
	_words.add_theme_font_size_override("font_size", WORDS_SIZE)
	_words.add_theme_color_override("font_color", UiTheme.WHITE)
	_copy.add_child(_words)


## Fills the window for `speaker` saying `words`, or the narrator when
## `speaker` is null, with nothing typed yet, and sizes it to them.
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
		_face_slot.add_child(MissionSpeech.bust_of(speaker, FACE))
		_name = MissionSpeech.name_of(speaker, 0)
		var army := CommanderVisuals.theme_for(speaker).color
		_name.add_theme_color_override("font_color", army.lightened(NAME_LIFT))
		_copy.add_child(_name)
		_copy.move_child(_name, 0)
	_words.custom_minimum_size.x = NARRATION_WIDTH if narrated else WORDS_WIDTH
	_words.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER if narrated else HORIZONTAL_ALIGNMENT_LEFT
	)
	_words.text = words
	_words.visible_ratio = 0.0
	quiet(_row)
	var content := _row.get_combined_minimum_size()
	_row.size = content
	size = content + PAD * 2.0


## How many letters of the words are showing at `typed` (0..1): what the blip
## that accompanies typing counts.
func letters_at(typed: float) -> int:
	return int(floorf(_words.text.length() * clampf(typed, 0.0, 1.0)))


func pose(typed: float) -> void:
	_words.visible_ratio = clampf(typed, 0.0, 1.0)
	visible = open > 0.0
	pivot_offset = size / 2.0
	scale = Vector2(1.0, maxf(open, 0.02))
	_row.modulate.a = clampf(open * 2.0 - 1.0, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var field := Rect2(Vector2.ZERO, size)
	if has_tail and open >= 1.0:
		_draw_tail(field)
	draw_rect(field.grow(1.0), EDGE)
	draw_rect(field, BORDER)
	var inner := field.grow(-BORDER_PX)
	draw_polygon(
		PackedVector2Array(
			[
				inner.position,
				Vector2(inner.end.x, inner.position.y),
				inner.end,
				Vector2(inner.position.x, inner.end.y)
			]
		),
		PackedColorArray([FIELD_TOP, FIELD_TOP, FIELD_BOTTOM, FIELD_BOTTOM])
	)
	for corner: Vector2 in [
		field.position,
		Vector2(field.end.x - 1, field.position.y),
		Vector2(field.position.x, field.end.y - 1),
		field.end - Vector2.ONE
	]:
		draw_rect(Rect2(corner, Vector2.ONE), EDGE)
	if cursor_on and open >= 1.0:
		var bob := roundf(sin(clock * TAU * CURSOR_BOB_HZ) * 1.5)
		var at := field.end - PAD - CURSOR + Vector2(0, bob + 2)
		draw_colored_polygon(
			PackedVector2Array(
				[at, at + Vector2(CURSOR.x, 0), at + Vector2(CURSOR.x / 2.0, CURSOR.y)]
			),
			BORDER
		)


## The tail from the window's nearer edge to `tail_tip`, drawn under the border
## so the window's edge closes over its root.
func _draw_tail(field: Rect2) -> void:
	var below := tail_tip.y > field.end.y
	var root_y := field.end.y - BORDER_PX if below else field.position.y + BORDER_PX
	var x := clampf(tail_tip.x, TAIL.x, field.size.x - TAIL.x)
	var tip := Vector2(x, root_y + (TAIL.y if below else -TAIL.y))
	var left := Vector2(x - TAIL.x / 2.0, root_y)
	var right := Vector2(x + TAIL.x / 2.0, root_y)
	draw_colored_polygon(PackedVector2Array([left, right, tip]), BORDER)
	var inset := Vector2(0, -BORDER_PX if below else BORDER_PX)
	draw_colored_polygon(
		PackedVector2Array(
			[left + Vector2(BORDER_PX, 0), right - Vector2(BORDER_PX, 0), tip + inset * 1.5]
		),
		FIELD_BOTTOM if below else FIELD_TOP
	)


## Every control under `node` lets the pointer through, so a click on a
## cinematic falls to the battle that advances it.
static func quiet(node: Node) -> void:
	var control := node as Control
	if control != null:
		control.mouse_filter = MOUSE_FILTER_IGNORE
	for child in node.get_children():
		quiet(child)
