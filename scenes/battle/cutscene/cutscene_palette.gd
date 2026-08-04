class_name CutscenePalette
extends RefCounted
## The colours the letterboxed frame draws with: one declaration each, shared by
## both cut-ins and everything they paint inside the band.
##
## What is here was either copied file to file — the ink three times over, the
## gold four, and the plate slate under a second constant *named* `SLATE_800`
## whose value was a shade off UiTheme's (COM-89) — or reached for across the two
## halves, with CaptureStage asking CutsceneSide for the plates and the sky.
##
## Where the design system already owns a colour this aliases it, exactly as
## UiTheme aliases CommanderVisuals; only what the band needs for itself is
## declared. Nothing here is named after a UiTheme token it is not, so a site
## reading `PLATE` can never mean a different slate than `UiTheme.SLATE_800`.

## The plate surface behind a name, terrain or capture row — the design system's
## raised dark surface. Drawn at `plate_p` while a plate is sliding in.
const PLATE := UiTheme.SLATE_800
## The stroke around everything the band prints, the rule under a plate, and the
## dark edge on a drawn silhouette: the design system's darkest ink, which is what
## an outline over moving art wants. Deliberately not called INK — UiTheme.INK is
## the body text on cream, a different colour with the same word on it.
const STROKE := UiTheme.HARD_BORDER
## Plate copy: not quite white, so the unit's name above it stays the loudest
## thing on the plate.
const PLATE_TEXT := Color(1.0, 1.0, 1.0, 0.88)

## The band's gold: the capture cut-in's meter, its chips and banner, the CAPTURE
## tag, a lit window and a filled defence star. Brighter than UiTheme.AMMO on
## purpose and kept as the cut-in's own — it is read over a dimmed, letterboxed
## frame, and it is the capture plan's `--gc-gold` reference toned to the board's
## palette. The HUD's amber stays UiTheme.AMMO.
const GOLD := Color(0.969, 0.788, 0.282)
## The unlit defence star beside it.
const STAR_OFF := Color(1.0, 1.0, 1.0, 0.22)

## The sky both dioramas grade between, top to horizon.
const SKY_TOP := Color(0.290, 0.486, 0.667)
const SKY_HORIZON := Color(0.749, 0.902, 0.949)

## The letterbox bars, and the board dimmed behind the band (drawn at
## CutscenePlayback.DIM_ALPHA as the cut-in opens).
const BAR := Color(0.055, 0.063, 0.078)
const DIM := Color(0.078, 0.086, 0.118)

## The flattened contact shadow a figure, a building or a piece of scenery casts
## on the diorama's ground. Each site sets its own alpha.
const GROUND_SHADOW := Color(0.078, 0.102, 0.133)
## The hard offset shadow under a figure's own art, at the alpha the figure fades
## through.
const FIGURE_SHADOW := UiTheme.SLATE_900
