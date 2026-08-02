class_name DaneFerrow
extends CommanderType
## Iron Dominion. Ferrow gets paid for wrecks: each kill steals from the victim
## rather than minting funds, and Collect doubles that same transfer for a turn.

@export var bounty_pct: int = 10
@export var defense_pct: int = -10


func kill_bounty_pct(state: GameState, team: int, _victim: Unit) -> int:
	return bounty_pct * 2 if _is_active(state, team) else bounty_pct


func defense_bonus(_state: GameState, _fight: Engagement) -> int:
	return defense_pct
