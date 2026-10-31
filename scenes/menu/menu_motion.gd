class_name MenuMotion
extends RefCounted
## The shipped board drifting under the main menu, and the one switch that holds it:
## a capture poses a still frame (the animator's `capturing` precedent, plan MN2/R3)
## and the Menu motion preference asks for the same stillness, so `set_moving` is
## where either answer lands.

## Canvas px per cell in the drifting terrain field, and how much bigger than the
## canvas the field is drawn so panning never exposes an edge.
const BACKDROP_TILE := 4
const BACKDROP_SPAN := Vector2(680, 400)

var _drift: Tween


## The backdrop the menu sits on: a radial-lit slate floor (a brighter pool at
## top-centre so the header reads against light, the panels against dark) with
## `board` baked to a texture and drifting faintly behind everything — the
## boot-screen game feel of the mockup. A null board is the floor alone.
func paint_backdrop(host: Control, board: MapData) -> void:
	var floor := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, UiTheme.SLATE_800)
	gradient.set_color(1, UiTheme.SLATE_900)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.12)
	tex.fill_to = Vector2(1.05, 1.05)
	tex.width = 128
	tex.height = 72
	floor.texture = tex
	floor.stretch_mode = TextureRect.STRETCH_SCALE
	floor.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(floor)

	if board == null:
		return
	var period := Vector2(board.width * BACKDROP_TILE, board.height * BACKDROP_TILE)
	var field := TextureRect.new()
	field.texture = MapThumbnail.bake(
		board, UiTheme.menu_identity(board.player_count()), BACKDROP_TILE
	)
	field.stretch_mode = TextureRect.STRETCH_TILE
	field.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	field.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	field.modulate = Color(1, 1, 1, 0.14)
	# Oversized by one tiling period so the screen stays covered across a full pan;
	# at −period the tiled field is pixel-identical to its start, so the loop is
	# seamless.
	field.size = BACKDROP_SPAN + period
	host.add_child(field)
	_drift = field.create_tween().set_loops()
	_drift.tween_property(field, "position", -period, 40.0).from(Vector2.ZERO)


## Lets the board drift, or holds it where a still page wants it.
func set_moving(moving: bool) -> void:
	if _drift == null:
		return
	if moving:
		_drift.play()
	else:
		_drift.pause()
