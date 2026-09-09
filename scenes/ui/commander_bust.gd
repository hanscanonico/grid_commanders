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
## a rebind and a resize reach the same answer.

var _commander: CommanderType = null
var _art: TextureRect = null


## `size` is the square (or band) the caller asks for, kept as the minimum so an
## unplaced field still knows its shape. It is set before the field can be
## resized, which is why it is a constructor argument rather than a caller's
## assignment.
func _init(size: Vector2 = Vector2.ZERO) -> void:
	custom_minimum_size = size
	clip_contents = true
	_art = TextureRect.new()
	_art.texture_filter = CommanderVisuals.ART_FILTER
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	resized.connect(_place)


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


## The general's drawing — whichever of the two this field's shape calls for — at
## a rung of `CommanderVisuals.art_scale`, centred, and hung from the top edge
## once it is taller than the field.
##
## Which of the two is `CommanderVisuals.fits_whole_bust`, and nobody else asks:
## the whole bust where the art fits at one texel to one pixel, the baked face
## chip everywhere else.
##
## The shape is the field's own size, falling back to the size it was asked for
## while it is still unplaced — a field that states no minimum is the roster
## tile's, which learns its band from the row a frame later and re-places itself
## then.
func _place() -> void:
	var shape := size.max(custom_minimum_size)
	if CommanderVisuals.fits_whole_bust(shape):
		_art.texture = CommanderVisuals.portrait_for(_commander)
	else:
		_art.texture = CommanderVisuals.face_for(_commander)
	var drawn := Vector2i(_art.texture.get_size())
	_art.size = Vector2(drawn * CommanderVisuals.art_scale(shape, drawn))
	_art.position = Vector2(
		roundf((shape.x - _art.size.x) * 0.5), maxf(0.0, roundf((shape.y - _art.size.y) * 0.5))
	)
