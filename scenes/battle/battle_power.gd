class_name BattlePower
extends RefCounted
## Why a press of Fire cannot fire the Command Power, in the chip's words.
##
## PowerCommand stays the one authority on whether a power may fire — this asks
## it, then reads its answer back off the same commander state, because the
## command's own strings are written for a log rather than for a chip beside the
## cursor. *Who is at the keyboard* is the one thing the command cannot answer,
## so the seat is asked first.
##
## The bar hides its Fire button until the meter fills, so the shortcut key is the
## only route to most of these — and a dead key reads as a broken one. Node-free
## and pure, the same shape as BattleLegend and ReadyUnits.

const AI_SEAT := "The computer has this seat."
const NO_POWER := "No Command Power."
const RUNNING := "Power already running."
const CHARGING := "Power charging: %d/%d."
const MATCH_OVER := "The match is over."
## What a board with a move half-made answers instead: there the meter is not the
## refusal, the timing is.
const MID_ACTION := "Finish this move first."


## "" when the power may fire.
static func refusal_for(state: GameState, ai_teams: Array[int]) -> String:
	if state.current_team in ai_teams:
		return AI_SEAT
	if PowerCommand.new().validate(state) == "":
		return ""
	var co_state := state.commander_state(state.current_team)
	if not co_state.type.has_power():
		return NO_POWER
	if co_state.power_active:
		return RUNNING
	if co_state.charge < co_state.type.power_cost:
		return CHARGING % [co_state.charge, co_state.type.power_cost]
	return MATCH_OVER
