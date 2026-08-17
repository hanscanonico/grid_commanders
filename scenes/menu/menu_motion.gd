class_name MenuMotion
extends RefCounted
## The two moving things behind the main menu — the shipped board drifting under
## the page, and the blinking PRESS START — and the one switch that holds them.
##
## Apart from the menu because holding them is one question about both: a capture
## poses a still frame (the animator's `capturing` precedent, plan MN2/R3) and the
## Menu motion preference asks for the same stillness, so `set_moving` is where
## either answer lands rather than two branches in two builders. The menu keeps
## the setup it is otherwise about; this keeps its scenery.

## Canvas px per cell in the drifting terrain field, and how much bigger than the
## canvas the field is drawn so panning never exposes an edge.
const BACKDROP_TILE := 4
const BACKDROP_SPAN := Vector2(680, 400)
const BLINK_SECONDS := 0.7

var _drift: Tween
var _blink: Timer
var _press_start: Label


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


## Blinks `label` on `host`'s clock.
func blink(host: Control, label: Label) -> void:
	_press_start = label
	_blink = Timer.new()
	_blink.wait_time = BLINK_SECONDS
	_blink.autostart = true
	host.add_child(_blink)
	_blink.timeout.connect(func() -> void: label.visible = not label.visible)


## Lets go of both moving things, or holds them where a still page wants them.
## PRESS START is left lit rather than wherever the blink had it, a held frame
## being no more allowed to depend on when it was held than on which machine held
## it.
func set_moving(moving: bool) -> void:
	if _drift != null:
		if moving:
			_drift.play()
		else:
			_drift.pause()
	if _blink != null:
		_blink.paused = not moving
	if not moving and _press_start != null:
		_press_start.visible = true
