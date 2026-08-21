class_name DisabledPalette
extends RefCounted
## How a control says "unavailable": one recipe for the plate and the label a
## disabled Button wears, so the two are muted together and can never disagree.
##
## Nothing is faded. The plate used to drop to 45% alpha and the label to 60%,
## which reads as *gone* rather than as unavailable: over the HUD's slate the
## cream plate dimmed to a grey the dark ink then sat on at 2.2:1, and over a
## cream panel the same plate had nothing to dim against at all. A translucent
## plate cannot answer for both backdrops, so a disabled plate keeps its own
## opacity and pays in colour instead — drained to grey and pushed toward its own
## border, which is a tone that reads on slate and on paper alike.
##
## Pure and Node-free, the way `PathArrow.segments` is: `UiTheme.apply_button`
## paints exactly what these two return, and `tests/unit/test_disabled_palette.gd`
## holds them to a plate that stays on the page and a label above 3:1 on it.

## How far a drained plate is pushed toward its own border. Enough to read as
## greyed against the cream panel it may sit on, short of the border itself so
## the outline still frames a plate rather than filling one.
const PLATE_SHADE := 0.25
## How far a drained label is lifted toward its plate. This is the whole signal
## that the words are unavailable, and it is small because it spends the contrast
## the label has left: 0.25 keeps every shipped variant above 3:1.
const LABEL_MUTE := 0.25


## The fill a disabled button's plate takes. Alpha is the fill's own, so a GHOST
## button — which has no plate in any state — still has none here.
static func plate(fill: Color, border: Color) -> Color:
	return Color(_drained(fill).lerp(border, PLATE_SHADE), fill.a)


## The ink a disabled button's label takes, muted toward the plate it is read on.
## Alpha is the label's own: a transparent label is exactly the defect this file
## exists to undo.
static func label(fg: Color, plate_color: Color) -> Color:
	return Color(_drained(fg).lerp(plate_color, LABEL_MUTE), fg.a)


static func _drained(color: Color) -> Color:
	var grey := color.get_luminance()
	return Color(grey, grey, grey, color.a)
