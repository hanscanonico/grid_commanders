class_name EmoteBubble3D
extends Node3D
## The little balloon that pops over a speaker's head as a line opens — "!",
## "?" or "..." — facing the lens and drawn over the board, never behind it.
## Posed off the cinematic's clock: it pops, holds and fades as `pose` says.

const BUBBLE_PX := Vector2i(22, 22)
const PIXEL := 0.012
const GLYPH_SIZE := 64
const GLYPH_PIXEL := 0.0032
const INK := Color("#10131c")
const PAPER := Color("#fbfbf6")
## A pop overshoots a little before it settles, then the bubble holds and fades.
const POP_SECONDS := 0.2
const OVERSHOOT := 1.25
const FADE_SECONDS := 0.25

static var _texture: ImageTexture

var _bubble: Sprite3D
var _glyph: Label3D


static func make(emote: StringName) -> EmoteBubble3D:
	var bubble := EmoteBubble3D.new()
	bubble.name = "EmoteBubble3D"
	bubble._build(String(emote))
	return bubble


func _build(emote: String) -> void:
	_bubble = Sprite3D.new()
	_bubble.texture = _bubble_texture()
	_bubble.pixel_size = PIXEL
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_bubble.no_depth_test = true
	_bubble.shaded = false
	_bubble.render_priority = 1
	add_child(_bubble)
	_glyph = Label3D.new()
	_glyph.text = emote
	_glyph.font = UiTheme.display(true)
	_glyph.font_size = GLYPH_SIZE
	_glyph.pixel_size = GLYPH_PIXEL
	_glyph.modulate = INK
	_glyph.outline_size = 0
	_glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glyph.no_depth_test = true
	_glyph.render_priority = 2
	_glyph.position.y = PIXEL * 1.5
	add_child(_glyph)


## The bubble `t` seconds after it popped, gone after `life` seconds.
func pose(t: float, life: float) -> void:
	visible = t >= 0.0 and t < life
	if not visible:
		return
	var grow := clampf(t / POP_SECONDS, 0.0, 1.0)
	var size := (
		lerpf(0.0, OVERSHOOT, grow) if grow < 0.7 else lerpf(OVERSHOOT, 1.0, (grow - 0.7) / 0.3)
	)
	scale = Vector3.ONE * maxf(size, 0.001)
	var alpha := clampf((life - t) / FADE_SECONDS, 0.0, 1.0)
	_bubble.modulate.a = alpha
	_glyph.modulate.a = alpha


## A round balloon with an ink rim and a tail at its lower left, drawn once:
## the paper shape first, then ink on every pixel that borders it.
static func _bubble_texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var image := Image.create_empty(BUBBLE_PX.x, BUBBLE_PX.y, false, Image.FORMAT_RGBA8)
	for y in BUBBLE_PX.y:
		for x in BUBBLE_PX.x:
			if _is_paper(x, y):
				image.set_pixel(x, y, PAPER)
	for y in BUBBLE_PX.y:
		for x in BUBBLE_PX.x:
			if _is_paper(x, y):
				continue
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if _is_paper(x + step.x, y + step.y):
					image.set_pixel(x, y, INK)
					break
	_texture = ImageTexture.create_from_image(image)
	return _texture


static func _is_paper(x: int, y: int) -> bool:
	var round_part := Vector2(x, y).distance_to(Vector2(11, 9.5)) <= 8.2
	var tail := y >= 15 and y <= 20 and x >= 4 and x <= 4 + (20 - y)
	return round_part or tail
