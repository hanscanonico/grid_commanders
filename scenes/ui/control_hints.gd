class_name ControlHints
extends RefCounted
## The key legend the top bar prints: one line per interaction context, naming
## the keys that actually do something *right now* (UX recovery plan U-08 — "no
## surface ever says that Enter/Z confirms, Esc/X cancels").
##
## The legend is permanent chrome, unlike the mission strip beside it: the strip
## retires once the loop has been performed, the legend never does, because the
## keys are still the keys on day forty.
##
## Copy only, and one authority for it. `Battle` maps its own `State` to a
## context key and the bar prints what comes back; nothing here knows what a
## state is, and nothing else in the tree spells a key name. The strings quote
## the *first* binding of each action in `project.godot` — ENTER for `confirm`
## (Space and Z also), ESC for `cancel` (X and Backspace also) — because a legend
## that listed every alternative would be longer than the bar.
##
## ASCII only, deliberately. Silkscreen carries no arrow glyphs, so a "↑↓" would
## fall through to whatever system face the machine happens to have and print at
## a different size than the rest of the line.

## The width past which the legend starts pushing the top bar's doctrine label
## out of the frame. An editorial ruler like TutorialHints.MAX_BODY_CHARS, held
## by the same test; the bar clips rather than overflows either way.
const MAX_CHARS := 40

const IDLE := &"idle"
const UNIT_SELECTED := &"unit_selected"
const PREVIEW := &"preview"
const MENU := &"menu"
const TARGETING := &"targeting"
const DROP_TARGETING := &"drop_targeting"
const ANIMATING := &"animating"
const AI_TURN := &"ai_turn"
const HANDOFF := &"handoff"
const VICTORY := &"victory"
const INFO := &"info"
const END_TURN_GUARD := &"end_turn_guard"

## Context -> the keys that do something in it. IDLE carries the zoom keys
## because that is the only context with room for them and the only one a player
## sits in long enough to want them.
const LEGENDS: Dictionary = {
	IDLE: "ENTER · SELECT   ESC · MENU   +/- · ZOOM",
	UNIT_SELECTED: "ENTER · MOVE   R · RANGE   ESC · BACK",
	PREVIEW: "R · RANGE   ESC · BACK",
	MENU: "UP/DOWN · PICK   ENTER · OK   ESC · BACK",
	TARGETING: "ENTER · FIRE   ESC · BACK",
	DROP_TARGETING: "ENTER · DROP   ESC · BACK",
	ANIMATING: "ANY KEY · SKIP",
	AI_TURN: "CPU IS PLAYING",
	HANDOFF: "ENTER · READY",
	VICTORY: "UP/DOWN · PICK   ENTER · OK",
	INFO: "ESC · CLOSE",
	# The one context whose two arrow axes do different things: the ready-unit
	# list scrolls under up/down while the two actions sit side by side.
	END_TURN_GUARD: "L/R · PICK   UP/DN · SCROLL   ENTER · OK",
}


## The legend for a context. An unknown key falls back to IDLE's rather than
## blanking the bar: a legend is a promise about the keyboard, and the resting
## one is true in more places than an empty line is useful.
static func legend_for(context: StringName) -> String:
	return LEGENDS.get(context, LEGENDS[IDLE])
