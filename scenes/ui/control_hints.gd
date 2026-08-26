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
## Two tables, one per hand: a build played with a finger has no ENTER to name, so
## `TOUCH_LEGENDS` says what a tap does and leaves to the dock what the dock says.
## `legend_for` and `chip_for` are the two ways to ask, and which table they read
## is `MobileProfile`'s answer rather than a caller's.
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

## The next-ready-unit key's chip, stated here for the same reason R's is: N does
## the same thing in every board context it answers in, and IDLE's legend is
## already exactly MAX_CHARS with nowhere to put it. It has no lit state — a jump
## is not a way of looking at the board — so the bar prints it unlit throughout.
const NEXT_CHIP := "N · NEXT"

## Every chip the top bar may print, so the two rules they are held to — each fits
## beside a legend already running at MAX_CHARS, each is ASCII — are checked over
## the set rather than over a list a new chip has to be remembered into.
const CHIPS: Array[String] = [THREAT_CHIP, RANGE_CHIP, OBJECTIVES_CHIP, NEXT_CHIP]

## What each chip says on a touch build, where naming the key is naming something
## the device has not got. A chip is a button, so what is left is the word it does
## — and an empty word takes the chip off the bar entirely, which is what NEXT
## asks for: the dock already carries that control, and a strip of chrome saying
## the same thing twice is the room the shorter touch legends were freed to buy.
const TOUCH_CHIPS: Dictionary = {
	THREAT_CHIP: "THREAT",
	RANGE_CHIP: "RANGE",
	OBJECTIVES_CHIP: "MISSION",
	NEXT_CHIP: "",
	END_TURN_CHIP: "END TURN",
}

## End Turn's key, printed on the bottom bar's button rather than in a legend —
## the button is already the thing that says what the key does, so a legend entry
## would say it twice and IDLE's has no room for it either way. It wears the same
## chip grammar as the four above so the two bars name a key the same way, and it
## is stated here for the reason they are: a key named anywhere else is a key that
## eventually names a binding the InputMap no longer has.
##
## Not in CHIPS: that set is what the *top* bar may print, and each of its members
## is held to fitting beside a legend this one never sits next to. Its touch copy
## is in TOUCH_CHIPS with the rest, so `chip_for` is the one way to print any of
## them and the button drops the key a finger has not got.
const END_TURN_CHIP := "E · END TURN"

## The touch dock's copy (mobile plan MB3). Its own block because the dock is a
## row of buttons rather than a legend: each chip says what it *does* instead of
## naming a key, since the key it dispatches is one a phone does not have. Still
## this file's, for the reason every chip above is — a control named anywhere
## else is a control that eventually names a binding the InputMap no longer has.
const DOCK_BACK := "BACK"
const DOCK_MENU := "MENU"
const DOCK_PAUSE := "PAUSE"
const DOCK_RESUME := "RESUME"
const DOCK_STEP := "STEP"
const DOCK_ZOOM_OUT := "-"
const DOCK_ZOOM_IN := "+"
const DOCK_NEXT := "NEXT"

## Every word the dock may print, held to the same ASCII rule the chips above are.
const DOCK_CHIPS: Array[String] = [
	DOCK_BACK,
	DOCK_MENU,
	DOCK_PAUSE,
	DOCK_RESUME,
	DOCK_STEP,
	DOCK_ZOOM_OUT,
	DOCK_ZOOM_IN,
	DOCK_NEXT,
]

const IDLE := &"idle"
const UNIT_SELECTED := &"unit_selected"
const PREVIEW := &"preview"
const MENU := &"menu"
const VALUE_MENU := &"value_menu"
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
##
## The vertical pair is spelled "UP/DN" wherever it appears, checked by the suite.
## It used to be "UP/DOWN" in two of the four legends that name it and "UP/DN" in
## the other two, so opening the pause menu over the board's action menu respelled
## the same key one keypress apart. The abbreviation is the spelling that fits:
## MAX_CHARS is what forced it on the two crowded legends, and a rule only some
## lines can keep is not a rule.
const LEGENDS: Dictionary = {
	IDLE: "ENTER · SELECT   ESC · MENU   +/- · ZOOM",
	UNIT_SELECTED: "ENTER · MOVE   ESC · BACK",
	PREVIEW: "ESC · BACK",
	MENU: "UP/DN · PICK   ENTER · OK   ESC · BACK",
	# A menu carrying rows left and right step in place — the pause menu's device
	# settings. Its own words rather than an addition to MENU's, because the board's
	# action menus have no value to step and would be advertising a dead key. ESC is
	# the entry that gives way, as it does in END_TURN_GUARD below: a menu with value
	# rows carries a Cancel row of its own, and no other line here can be spared —
	# all four entries are 53 characters against a 40-character bar, and ENTER is
	# what every row that is not a value row is taken with.
	VALUE_MENU: "UP/DN · PICK   L/R · CHANGE   ENTER · OK",
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
	VICTORY: "UP/DN · PICK   ENTER · OK",
	INFO: "ESC · CLOSE",
	# The one context whose two arrow axes do different things: the ready-unit
	# list scrolls under up/down while the two actions sit side by side.
	END_TURN_GUARD: "L/R · PICK   UP/DN · SCROLL   ENTER · OK",
}

## The same table for a build played with a finger, which has no ENTER to press
## and no ESC to leave with. Every line is what a *finger* does, and a line the
## dock already states is empty rather than restated — the two thumbs' bar is one
## row below, so BACK, RESUME, STEP and the zoom are named there and nowhere else.
## What is left is the board, where the gesture is the thing a legend can teach: a
## tap acts on the cell under it, and a pinch steps the zoom ladder.
##
## Its own table rather than a rewrite of the one above, because both ship: the
## desktop legend is untouched, and a key legend on a phone and a gesture legend
## on a desktop are equally wrong.
const TOUCH_LEGENDS: Dictionary = {
	IDLE: "TAP · SELECT   PINCH · ZOOM",
	UNIT_SELECTED: "TAP · MOVE",
	PREVIEW: "",
	MENU: "TAP · PICK",
	# A tap on a value row steps it where it stands, exactly as confirm does — see
	# ActionMenu.choose — so the words say stepping rather than picking.
	VALUE_MENU: "TAP · PICK   TAP A VALUE · STEP",
	TARGETING: "TAP · FIRE",
	DROP_TARGETING: "TAP · DROP",
	POWER_TARGETING: "TAP · STRIKE",
	ANIMATING: "TAP · SKIP",
	AI_TURN: "CPU PLAYING",
	REPLAY: "REPLAY",
	REPLAY_PAUSED: "PAUSED",
	PAUSED: "PAUSED",
	HANDOFF: "TAP · READY",
	VICTORY: "TAP · PICK",
	INFO: "TAP · CLOSE",
	END_TURN_GUARD: "TAP · PICK",
}

## Context -> the leading chip's word. A context with no row rests at MENU, which
## is what `cancel` does in every state that is not listed here.
const DOCK_BACK_WORDS: Dictionary = {
	UNIT_SELECTED: DOCK_BACK,
	PREVIEW: DOCK_BACK,
	TARGETING: DOCK_BACK,
	DROP_TARGETING: DOCK_BACK,
	POWER_TARGETING: DOCK_BACK,
	AI_TURN: DOCK_PAUSE,
	REPLAY: DOCK_PAUSE,
}


## The legend for a context, in the vocabulary of the hand playing. An unknown key
## falls back to IDLE's rather than blanking the bar: a legend is a promise about
## the controls, and the resting one is true in more places than an empty line is
## useful. `touch` is handed in so the copy is checkable without a process to
## launch, MobileProfile's own idiom.
static func legend_for(context: StringName, touch := MobileProfile.active()) -> String:
	var table: Dictionary = TOUCH_LEGENDS if touch else LEGENDS
	return table.get(context, table[IDLE])


## What a chip says to the hand playing. Empty means the bar leaves it off.
static func chip_for(chip: String, touch := MobileProfile.active()) -> String:
	return TOUCH_CHIPS.get(chip, chip) if touch else chip


## What the dock's leading chip says in this context. One chip and one action —
## `cancel` — because that key is already "get me out of here" everywhere: it
## aborts a targeting state, asks for the pause during a computer turn, and opens
## the map menu at rest. The word is what changes, so the chip reads as the thing
## it is about to do rather than as three controls that happen to share a slot.
static func dock_back_for(context: StringName) -> String:
	return DOCK_BACK_WORDS.get(context, DOCK_MENU)
