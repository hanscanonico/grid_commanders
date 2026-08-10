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

## The threat lens's chip, which the top bar prints beside the legend rather than
## inside it. Its own line because the lens is not a key that does something *in a
## context* — it is a way of looking at the board that outlives every one of them,
## and the per-context legend is full: IDLE's is already exactly MAX_CHARS.
##
## Still ControlHints' copy, though. A key named anywhere else is a key that
## eventually names a binding the InputMap no longer has.
const THREAT_CHIP := "T · THREAT"

## The fire ring's chip, on the same terms and for the same reason. R used to be a
## legend entry in the two contexts that had a unit in hand, and now answers for
## whatever the cursor is on in every board context including rest — where the
## legend has no room for it. A key that does the same thing everywhere is a way of
## looking at the board, so it is stated once beside T rather than three times in a
## rotation that would still be missing it somewhere.
const RANGE_CHIP := "R · RANGE"

## The mission card's chip, on the same terms as the two lenses above: O raises and
## lowers the campaign card in every board context, so it is a way of looking at the
## board rather than a key that does something in one interaction. The bar prints it
## only while a mission is being fought — a key that would do nothing must not be
## advertised — which is the one thing it does not share with T and R.
const OBJECTIVES_CHIP := "O · MISSION"

## Every chip the top bar may print, so the two rules they are held to — each fits
## beside a legend already running at MAX_CHARS, each is ASCII — are checked over
## the set rather than over a list a new chip has to be remembered into.
const CHIPS: Array[String] = [THREAT_CHIP, RANGE_CHIP, OBJECTIVES_CHIP]

const IDLE := &"idle"
const UNIT_SELECTED := &"unit_selected"
const PREVIEW := &"preview"
const MENU := &"menu"
const TARGETING := &"targeting"
const DROP_TARGETING := &"drop_targeting"
const POWER_TARGETING := &"power_targeting"
const ANIMATING := &"animating"
const AI_TURN := &"ai_turn"
const REPLAY := &"replay"
const REPLAY_PAUSED := &"replay_paused"
const PAUSED := &"paused"
const HANDOFF := &"handoff"
const VICTORY := &"victory"
const INFO := &"info"
const END_TURN_GUARD := &"end_turn_guard"

## Context -> the keys that do something in it. IDLE carries the zoom keys
## because that is the only context with room for them and the only one a player
## sits in long enough to want them.
const LEGENDS: Dictionary = {
	IDLE: "ENTER · SELECT   ESC · MENU   +/- · ZOOM",
	UNIT_SELECTED: "ENTER · MOVE   ESC · BACK",
	PREVIEW: "ESC · BACK",
	MENU: "UP/DOWN · PICK   ENTER · OK   ESC · BACK",
	TARGETING: "ENTER · FIRE   ESC · BACK",
	DROP_TARGETING: "ENTER · DROP   ESC · BACK",
	# An aimed Command Power. Its own word rather than the attack's FIRE, because
	# the meter is spent on the square whether or not anything was standing in it
	# — and nothing about a unit's shot has ever cost the player anything to miss.
	POWER_TARGETING: "ENTER · STRIKE   ESC · BACK",
	ANIMATING: "ANY KEY · SKIP",
	# The computer's turn is not a dead end: the one key that works in it is the
	# one that takes the board back, so the legend names it rather than only
	# saying whose turn it is.
	AI_TURN: "CPU PLAYING   ESC · PAUSE",
	# A replay borrows AI_TURN's state — somebody else is playing and you are
	# watching — so it needs its own words to say that nobody is playing at all.
	REPLAY: "REPLAY   ESC · PAUSE",
	# A paused replay has one key a paused computer turn does not: the next command
	# is already written down, so it can be taken one at a time.
	REPLAY_PAUSED: "ENTER · RESUME  S · STEP  ESC · MENU",
	PAUSED: "PAUSED   ENTER · RESUME   ESC · MENU",
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
