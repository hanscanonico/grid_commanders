class_name DaneFerrow
extends CommanderType
## Iron Dominion. Ferrow gets paid for wrecks: each kill steals from the victim
## rather than minting funds, and Collect doubles that same transfer for a turn.

@export var bounty_pct: int = 10
@export var defense_pct: int = -10
## Displayed HP at or below which a target is worth doubling the rate for. A kill
## is what pays, and a full-health unit is rarely one this turn.
@export var collect_want_hp: int = 6
## Funds a hostile treasury must hold before the theft is worth the meter: the
## steal is clamped to what the victim can pay (ChargeLedger's transfer), so a
## broke opponent yields nothing however many wrecks he makes.
@export var collect_want_funds: int = 1000


func kill_bounty_pct(state: GameState, team: int, _victim: Unit) -> int:
	return bounty_pct * 2 if _is_active(state, team) else bounty_pct


func defense_bonus(_state: GameState, _fight: Engagement) -> int:
	return defense_pct


## The base gate asks only whether anyone is in reach, and Collect pays nothing
## for contact: the bounty needs a lethal blow and is clamped to the victim's
## purse, so an army in a healthy slugging match against a broke opponent fires
## it for provably zero. This waits on a target that could die and an owner who
## could pay for it.
func wants_power(state: GameState, team: int) -> bool:
	return _has_a_payday(state, team)


## A visible, solvent enemy already hurt enough to finish, that a unit which has
## not acted could really open fire on. Who counts as a shooter is the base
## _is_striker and whether the shot is there at all is the base _unit_can_strike,
## so this grades the same board the base gate does over a narrower target list;
## whether the shot actually kills is the forecast's, never asked here.
func _has_a_payday(state: GameState, team: int) -> bool:
	var paydays: Array[Unit] = []
	for victim in _hostile_targets(state, team):
		if victim.displayed_hp() > collect_want_hp:
			continue
		if state.funds.get(victim.team, 0) < collect_want_funds:
			continue
		paydays.append(victim)
	if paydays.is_empty():
		return false
	var shooters: Array[int] = [team]
	for unit in state.units:
		if not _is_striker(state, team, unit, shooters, true):
			continue
		if _unit_can_strike(state, unit, paydays):
			return true
	return false
