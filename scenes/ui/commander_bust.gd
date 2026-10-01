class_name CommanderBust
extends Panel

## A general's art on a faction-tinted field, clipped to the field — the one bust
## every surface that shows a commander is built from. Six of them kept their own
## TextureRect recipe and disagreed about the framing, which is the drift the kit
## exists to prevent (menu-revamp D1); `UiKit.commander_bust` is the constructor
## every one of them calls.
##
## The field owns which general it is showing, because which of the two drawings
## that general gets is a function of the size a container hands over — known a
## frame after the bust is built — so the texture is chosen at placement time and
## a rebind and a resize reach the same answer. Which picture of that drawing —
## the pixel art, or the 3D still while the 3D view is chosen — is asked of
## `CommanderPortraits3D` on the same placement, so a flip of the view repaints
## every field on screen.

var _commander: CommanderType = null
var _art: TextureRect = null


func _init(field_size: Vector2 = Vector2.ZERO) -> void:
	custom_minimum_size = field_size
	clip_contents = true
	_art = TextureRect.new()
	_art.texture_filter = CommanderVisuals.ART_FILTER
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	resized.connect(_place)
	Settings.board_view_changed.connect(_place)


## Points the field at a general and paints its faction behind them.
##
## The tint stays the caller's, because the three in the tree are deliberate: the
## speech card's darkened field is a reading column, the HUD chip's `color_light`
## is chrome, and the victory lockup stands its bust on the panel's own paper
## (`UiKit.NO_FIELD`). A null general is the empty seat, which is what
## `portrait_for`/`face_for` answer for one.
func bind(commander: CommanderType, tint: Color) -> void:
	add_theme_stylebox_override("panel", UiTheme.flat(tint))
	_commander = commander
	_place()


## The shape falls back to the minimum while the field is still unplaced: the
## roster tile states none and learns its band from the row a frame later.
##
## The art is centred on both axes, except that a drawing taller than the field
## falls to its top: a clipped bust should lose the chest, not the chin.
func _place() -> void:
	var shape := size.max(custom_minimum_size)
	var drawn := _show(shape)
	_art.visible = drawn != Vector2i.ZERO
	if not _art.visible:
		return
	_art.size = Vector2(drawn * CommanderVisuals.art_scale(shape, drawn))
	_art.position = Vector2(
		roundf((shape.x - _art.size.x) * 0.5), maxf(0.0, roundf((shape.y - _art.size.y) * 0.5))
	)


## Puts the general's drawing on the art and answers the size it is laid out
## at. A 3D still stands in for its drawing at the drawing's size, and answers
## zero while it is still being shot — `_place` runs again once it is. A field
## not laid out yet asks for none: which drawing it needs is not known until its
## container sizes it, and a still shot for the wrong one is a wasted frame.
func _show(shape: Vector2) -> Vector2i:
	var whole := CommanderVisuals.fits_whole_bust(shape)
	if CommanderPortraits3D.showing():
		_art.texture_filter = CommanderPortraits3D.FILTER
		if not Rect2(Vector2.ZERO, shape).has_area():
			return Vector2i.ZERO
		_art.texture = CommanderPortraits3D.still_for(_commander, whole, _place)
		if _art.texture == null:
			return Vector2i.ZERO
		return CommanderVisuals.PORTRAIT_SIZE if whole else CommanderVisuals.FACE_SIZE
	_art.texture_filter = CommanderVisuals.ART_FILTER
	if whole:
		_art.texture = CommanderVisuals.portrait_for(_commander)
	else:
		_art.texture = CommanderVisuals.face_for(_commander)
	return Vector2i(_art.texture.get_size())
