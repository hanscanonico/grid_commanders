class_name UnitMark3D
extends RefCounted
## The mission's goal diamond for a unit the mission names, stood over its model.
##
## The flat board lays the diamond on the unit's square (ObjectiveMarks); on this
## board the model stands on that square and hides it, so the same diamond is
## drawn upright over the model instead, where nothing can stand in front of it.

## The diamond in texels — ObjectiveMarks' rings, outer to inner — and how big
## one texel is in the world, so the diamond reads at about a quarter cell.
const RADII: Array[int] = [4, 3, 1]
const TEXEL := 0.035
## How far over the model's top the diamond's foot floats, and how far it bobs.
const CLEAR := 0.12
const BOB := 0.03

static var _texture: ImageTexture


## A fresh diamond, hidden until the mirror places it.
static func make() -> Sprite3D:
	var mark := Sprite3D.new()
	mark.texture = _diamond()
	mark.pixel_size = TEXEL
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mark.shaded = false
	mark.no_depth_test = true
	mark.render_priority = 2
	mark.offset = Vector2(0, RADII[0] + 0.5)
	mark.visible = false
	return mark


## Stands `mark` over a model whose top is `top` above `foot`, bobbing on
## `clock` unless the board is held still.
static func place(mark: Sprite3D, foot: Vector3, top: float, clock: float) -> void:
	var bob := 0.0 if BoardBeat.still() else sin(clock * 3.0) * BOB
	mark.position = foot + Vector3.UP * (top + CLEAR + bob)


static func _diamond() -> ImageTexture:
	if _texture != null:
		return _texture
	var side := RADII[0] * 2 + 1
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var colours: Array[Color] = [UiTheme.HARD_BORDER, UiTheme.AMMO, UiTheme.HARD_BORDER]
	for y in side:
		for x in side:
			var distance := absi(x - RADII[0]) + absi(y - RADII[0])
			for ring in RADII.size():
				if distance <= RADII[ring]:
					image.set_pixel(x, y, colours[ring])
	_texture = ImageTexture.create_from_image(image)
	return _texture
