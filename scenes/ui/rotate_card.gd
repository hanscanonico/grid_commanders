class_name RotateCard
extends CanvasLayer
## The card a touch build shows while its window stands taller than wide.
##
## The game is landscape only (a user decision) under `aspect="keep"`, so an
## upright phone draws the whole canvas as a thin strip a few pixels tall per
## letter. Rather than a strip nobody can read, the strip says what to do, and
## the card goes the moment the window turns. Built only on a touch build (mobile
## plan D5): a desktop window that is merely tall never gets one.

## Over every page, banner and cut-in the game can raise.
const LAYER := 128

var _card: Control


## Hangs a card off `root` on a touch build, and nothing on a desktop one.
static func install(root: Window) -> void:
	if MobileProfile.active():
		root.add_child.call_deferred(RotateCard.new())


## Whether a window of `size` is held the wrong way up for this game.
static func upright(size: Vector2i) -> bool:
	return size.y > size.x


func _ready() -> void:
	layer = LAYER
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	UiKit.page_veil(_card, 1.0)
	var col := UiKit.page_body(_card, 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UiKit.page_title("ROTATE YOUR DEVICE")
	title.add_theme_font_size_override("font_size", UiTheme.SIZE_WORDMARK)
	col.add_child(title)
	var note := UiKit.page_note("Grid Commanders is played in landscape.")
	note.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	col.add_child(note)
	get_window().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	_card.visible = upright(get_window().size)
