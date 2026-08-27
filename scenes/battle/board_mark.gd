class_name BoardMark
extends RefCounted
## The count a board badge carries, written the one way every board badge writes
## one: outlined rather than boxed.
##
## The design reference set the chip on a filled ink panel. At a 44-pixel tile
## that panel is trim; at this board's 16 it covers the very thing the mark is
## about — the building being captured, the unit a power just touched — so the
## number can no longer be read against what it is counting. Outlined marks carry
## on any terrain and leave the tile readable underneath, which is the badge
## idiom UnitSprite already wears for HP and fuel, for the same reason.
##
## Node-free and stateless — one static over a canvas the caller hands in, no
## scene of its own — on the same terms `PathArrow.segments` and `ReadyUnits.of`
## are.


## The outline pass and then the digits, in the one size and the two colours a
## board badge is written in. Each drawer keeps its own outline weight, that
## being the only part of a badge that is the badge's own.
static func count(canvas: CanvasItem, font: Font, pen: Vector2, text: String, outline: int) -> void:
	canvas.draw_string_outline(
		font,
		pen,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiTheme.SIZE_MARK,
		outline,
		UiTheme.HARD_BORDER
	)
	canvas.draw_string(
		font, pen, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_MARK, UiTheme.WHITE
	)
