class_name OverlayPalette
extends RefCounted
## The modulates the three board overlay layers paint with: reach, fire and the
## threat lens. `CutscenePalette` is the precedent for a surface-local palette —
## these are the board's translucent washes, a different vocabulary from the
## design system's opaque chrome, so they live here rather than on UiTheme.
##
## The top bar's threat chip speaks UiTheme.DANGER; the lens itself is this red
## at this alpha — kept distinct on purpose: chrome is opaque ink, the lens is a
## wash over art.

## MoveOverlay: reachable cells, blue.
const MOVE := Color(0.35, 0.55, 1, 0.75)
## AttackOverlay: the fire ring, the pickable targets and an aimed power's
## square, red.
const ATTACK := Color(1, 0.35, 0.3, 0.8)
## ThreatOverlay: the threat lens, the same red as ATTACK but faint — the
## stripe pattern is what keeps it from reading as the same paint.
const THREAT := Color(1, 0.35, 0.3, 0.38)
