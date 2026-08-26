class_name BattleLegend
extends RefCounted
## Which key legend context the top bar prints, once the two facts a state alone
## cannot carry are folded in: whether the board is a recording being watched, and
## whether the open menu has rows left and right step.
##
## Battle owns the state -> context table (the enum is its own) and the bar owns
## the words (they are ControlHints'); what is left over is this — a pure answer
## the suite checks without a scene, the same shape as ReadyUnits and
## TransitionInput. Battle's state setter is still the one caller, so a context is
## overridden in one place rather than at each of the sites that assign a state.
##
## The touch dock reads the same context through the same call, which is why the
## three answers below are here: what a chip may do is a fact about the context,
## and a dock that judged the turn for itself would be the second opinion this
## class exists to prevent.

const _REPLAY_CONTEXTS: Dictionary = {
	ControlHints.AI_TURN: ControlHints.REPLAY,
	ControlHints.PAUSED: ControlHints.REPLAY_PAUSED,
}

## The contexts whose own surface owns the input, so no dock chip may act in them.
const _DOCK_DEAD_CONTEXTS: Array[StringName] = [
	ControlHints.ANIMATING,
	ControlHints.HANDOFF,
	ControlHints.VICTORY,
	ControlHints.MENU,
	ControlHints.VALUE_MENU,
	ControlHints.INFO,
	ControlHints.END_TURN_GUARD,
]


## `base` is the context the state maps to. A replay borrows AI_TURN and the
## PAUSED it can be interrupted into — somebody else is playing and you are
## watching — so only the words differ, and a paused replay names one key a paused
## turn cannot: the step. A menu with a value row names left and right, which the
## board's action menus have no use for.
static func context_for(base: StringName, replaying: bool, value_menu: bool) -> StringName:
	if replaying and _REPLAY_CONTEXTS.has(base):
		return _REPLAY_CONTEXTS[base]
	if value_menu and base == ControlHints.MENU:
		return ControlHints.VALUE_MENU
	return base


## Whether the board in this context is the player's to command — the two rest
## states, where nothing is in hand and nobody else is on turn. The bottom bar's
## End Turn button reads it, so the button and the legend answer off one context
## rather than off two opinions about whose turn it is.
static func commands_board(context: StringName) -> bool:
	return context == ControlHints.IDLE or context == ControlHints.PREVIEW


## Whether the touch dock's chips may be pressed in this context. False in exactly
## the contexts that already swallow board input — a banner or cut-in, the handoff
## blackout, the victory lockup, an open menu, the end-turn guard and the commander
## sheet — and true in `AI_TURN` and `PAUSED`, which is the point of the bar. The
## dock is disabled rather than hidden there: its height is part of the chrome the
## board is framed against, and a chip that cannot be pressed is also what keeps one
## physical tap from both acting and skipping the banner it landed on.
static func dock_live(context: StringName) -> bool:
	return context not in _DOCK_DEAD_CONTEXTS


## Whether the board is a turn parked between commands — a paused computer turn or
## a paused replay. The dock's Resume chip dispatches `confirm`, which at rest
## selects whatever the cursor is on, so it answers here and nowhere else.
static func paused_in(context: StringName) -> bool:
	return context == ControlHints.PAUSED or context == ControlHints.REPLAY_PAUSED


## Whether one more command is already written down and can be taken on its own.
## Only a paused replay: a paused computer turn has no next command yet.
static func steppable(context: StringName) -> bool:
	return context == ControlHints.REPLAY_PAUSED
