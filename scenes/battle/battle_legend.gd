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

const _REPLAY_CONTEXTS: Dictionary = {
	ControlHints.AI_TURN: ControlHints.REPLAY,
	ControlHints.PAUSED: ControlHints.REPLAY_PAUSED,
}


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
