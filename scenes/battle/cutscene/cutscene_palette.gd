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

## The pale of a landing's kicked-up specks, and of the haze hanging over a
## skyline: the same off-white, drawn at each site's own alpha.
const DUST := Color(0.941, 0.925, 0.886)

## The flattened contact shadow a figure, a building or a piece of scenery casts
## on the diorama's ground. Each site sets its own alpha.
const GROUND_SHADOW := Color(0.078, 0.102, 0.133)
## The hard offset shadow under a figure's own art, at the alpha the figure fades
## through.
const FIGURE_SHADOW := UiTheme.SLATE_900

## The board's own stone and snow: four rungs off the rock ramp the sprite
## generator paints a massif with, and two off its snow ramp
## (generators/sprites/spritegen/palette.py, ROCK_RAMP / SNOW_RAMP). The cut-in's
## ridge is drawn rather than blitted, so these are what keep it the same
## mountain the board shows. The ramp's own split is warm stone in the light and
## cool stone in the shade, under the tile's sun — up and to the left. The rim is
## the ramp's top rung and belongs to the crest alone: a whole flank painted
## there leaves nothing for the snow above it to be brighter than.
const ROCK_RIM := Color(0.643, 0.639, 0.624)
const ROCK_BODY := Color(0.478, 0.459, 0.439)
const ROCK_SHADE := Color(0.353, 0.373, 0.431)
const ROCK_SCREE := Color(0.247, 0.259, 0.298)
const SNOW_LIT := Color(0.659, 0.678, 0.698)
const SNOW_SHADE := Color(0.525, 0.549, 0.604)
