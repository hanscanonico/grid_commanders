class_name ChargeLedger
extends RefCounted
## What one army losing HP is worth: Command Power charge to both sides, and —
## for a kill — the bounty a doctrine steals out of the loser's purse.
##
## Both are priced off the same loss, so they are settled in one place and behind
## one gate: every charge the economy ever banks and every fund a kill moves comes
## through `bank_losses`. The meter itself still belongs to the state
## (`GameState.add_charge` caps it) and so does the purse.

## Charge is a percentage of the value destroyed in an exchange
## (`state.rules_config.charge_pct_lost` / `charge_pct_dealt`): the side that
## *loses* the HP banks the first, the side that dealt it banks the second.
## Asymmetric on purpose — the aggressor cannot out-charge the defender on the
## same trade, so a player winning the field does not run away with the meter as
## well.


## Banks both sides' share of one unit losing `hp_lost` internal HP. Value is the
## victim's cost prorated by the HP taken off it — halving a 7 000 Tank is 3 500
## points — and all of it is integer math so replays stay exact.
##
## A lethal loss takes the victim's cargo with it, each passenger banked at its
## own remaining HP exactly as if it had been killed in the open. That has to be
## settled here rather than by the caller, because a transport's loss *is* its
## cargo's: called any later the passengers are already erased, and called by hand
## it is one more thing an exchange can forget. The fuel-crash death in
## `TurnRules` erases cargo without a fight and deliberately banks nothing.
##
## Base cost is deliberate: purchase discounts change what an army pays, not what
## a unit is worth once it is on the board (pricing plan D1).
static func bank_losses(state: GameState, victim: Unit, hp_lost: int, dealer_team: int) -> void:
	if hp_lost <= 0:
		return
	var lethal := hp_lost >= victim.hp
	if lethal:
		_transfer_bounty(state, victim, dealer_team)
	var value := victim.type.cost * hp_lost / Unit.MAX_HP
	state.add_charge(victim.team, value * state.rules_config.charge_pct_lost / 100)
	state.add_charge(dealer_team, value * state.rules_config.charge_pct_dealt / 100)
	if lethal:
		# Recurses because GameState.remove_unit's erase does — an old save may
		# nest transports even though the load commands now refuse it.
		for passenger in state.cargo_of(victim):
			bank_losses(state, passenger, passenger.hp, dealer_team)


## A kill steals rather than mints: the victim can never pay below zero, and a
## broke army yields nothing. Behind the same gate as the charge above, so direct
## shots, counters and cargo sunk with a transport all price a kill alike.
static func _transfer_bounty(state: GameState, victim: Unit, dealer_team: int) -> void:
	var pct := state.commander_of(dealer_team).kill_bounty_pct(state, dealer_team, victim)
	if pct <= 0:
		return
	var wanted := victim.type.cost * pct / 100
	var stolen := mini(wanted, state.funds.get(victim.team, 0))
	if stolen <= 0:
		return
	state.funds[victim.team] -= stolen
	state.funds[dealer_team] += stolen
