class_name BoardPunch
extends Control
## The board's flinch as a cut-in takes the frame: a still of the board, scaled.
##
## The flinch used to be a camera zoom — `BattleView.punch_zoom` multiplied into
## `camera.zoom` — and a camera zoom is the one thing the integer zoom ladder
## exists to forbid. It walks the board through 1.00 … 1.14 screen pixels per
## world pixel, so on every frame of the punch a different set of rows is dropped
## and doubled, in a different place on every sprite. Scaling a frame that has
## already been drawn spreads the same filtering over the whole image at once:
## uniform, and it reads as motion rather than as sixty sprites tearing
## independently.
##
## The still is exact rather than approximate. A camera zoom scales what is
## rendered about the camera's screen anchor, and that anchor is the middle of
## the board band by construction (`BattleView._apply_board_offset`) — so scaling
## the captured frame about the same point draws what the camera zoom drew,
## without resampling the art.
##
## Clipped to the band, which is what keeps the docked bars out of it: the still
## carries the whole window, chrome included, and at any scale of 1.0 or more the
## snapshot's own bars fall outside the clip and the live ones are what is on
## screen. At exactly 1.0 the buffer is therefore pixel-identical to the board
## under it, so opening and closing it is invisible.
##
## A card standing *inside* the band — the mission objectives panel — is in the
## still as well, and the flinch scales that copy behind the live one for its
## tenth of a second. That is the price of photographing the window rather than
## the world, which is what a SubViewport would have bought and what wrapping the
## world in a second coordinate space costs everywhere else.
##
## It decides nothing. `BattleAnimator` opens it, `CutscenePlayback` eases it back
## out on the cut-in's one clock, and `close` runs unconditionally when the cut-in
## ends — so a skip lands on the live board like everything else does.

var _frame: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_frame = TextureRect.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The grab comes back at the window's resolution while the band is measured in
	# canvas pixels, and a TextureRect's minimum size is its texture's — so without
	# this the still is pinned to 1280x720 in a 640x360 canvas and the "punch" is a
	# doubling.
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(_frame)
	hide()


## The screen point a camera zoom scales the board about: the middle of the band
## between the two docked bars, which is where the camera's own centre lands.
## Static and pure, so the geometry is checked without a viewport.
static func band_center(view_size: Vector2) -> Vector2:
	return Vector2(view_size.x * 0.5, view_size.y * 0.5 - float(BattleView.BOARD_LIFT_PX))


## Grabs the board as it stands and shows it in place of the live one, at rest.
## One frame is awaited first: the viewport texture is whatever was last drawn,
## and the attacker has only just been snapped onto the cell the cut-in is about
## to be about.
##
## A frame that cannot be read costs the flinch and nothing else. macOS stops
## presenting an occluded window and hands back an empty image (the same fact
## `ScreenshotUtil.save_frame` forces a draw over), and a cut-in that failed to
## open because the *board* could not be photographed would be a presentation
## nicety taking the scene down with it.
func open() -> void:
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return
	var view_size := get_viewport_rect().size
	_frame.texture = ImageTexture.create_from_image(image)
	position = Vector2(0.0, float(UiTheme.HUD_TOP_H))
	size = view_size - Vector2(0.0, float(UiTheme.HUD_BARS_H))
	_frame.position = Vector2(0.0, -float(UiTheme.HUD_TOP_H))
	_frame.size = view_size
	_frame.pivot_offset = band_center(view_size)
	set_punch(1.0)
	show()


## How far in the still is pushed, as a multiple of the board's resting scale.
func set_punch(punch: float) -> void:
	if _frame != null:
		_frame.scale = Vector2(punch, punch)


## Drops the still and hands the frame back to the live board.
func close() -> void:
	hide()
	if _frame != null:
		_frame.texture = null
