class_name OrinFlux
extends CommanderType
## Aurora Compact. Intelligence: he sees further than anyone and, for a round,
## makes sure nobody else moves or sees properly. Signal Jam is the only power
## that reaches across the table, and both of its halves are ongoing debuffs on
## the enemy — a movement point and a tile of sight — rather than a one-shot
## strip.
##
## The strip it used to be (10 fuel, 1 shell) was measurably nothing: land units
## carry 50-99 fuel and spend two or three a turn, and a shell off a pool of six
## to nine is not a turn anyone plans around. A movement point is, and it is
## felt by a human and by the planner alike, since the planner reads the same
## `move_budget` the board does.
##
## ROUND duration, so "until their next turn" means what it says: it has to still
## be running while the opponent plays.

@export var scout_ids: Array[StringName] = [&"recon", &"apc"]
@export var scout_vision_bonus: int = 1
@export var jam_vision_penalty: int = -1
@export var jam_move_penalty: int = -1
## Build-list places his scouts are pulled up — the smallest bias on the
## roster, honestly: the AI's targeting is omniscient-except-hidden, so extra
## sight buys its fog-limited *pathing* something and its aim nothing.
##
## Counted from the end of build_priority, because a recon is on no tier's list.
## So it is the list's *length* this is calibrated against, and it moved by one
## when rockets joined: -2 became a recon he banks past rather than buys.
@export var scout_build_bias: int = -3


func vision_bonus(_state: GameState, unit: Unit) -> int:
	return scout_vision_bonus if unit.type.id in scout_ids else 0


## Asked of *his* commander about an enemy unit, which is what makes this the
## one hook a doctrine uses to reach the other side of the board. Vision floors
## the total at 0, so a jammed scout goes blind rather than inside-out.
func enemy_vision_bonus(state: GameState, team: int, _unit: Unit) -> int:
	return jam_vision_penalty if _is_active(state, team) else 0


## The other half of the same jam, and it asks nothing this one does not:
## MovementResolver.move_budget runs the hostile-commander loop Vision's sight
## loop runs, so both halves stop at the same side boundary and agree about who
## the enemy is without either restating it.
func enemy_move_bonus(state: GameState, team: int, _unit: Unit) -> int:
	return jam_move_penalty if _is_active(state, team) else 0


## A debuff is at its best going off *before* the exchange, so this asks whether
## the two armies are in contact at all rather than whether he personally has a
## shot: a movement point and a tile of sight change what the opponent can do
## next turn whichever side is closing the distance.
func wants_power(state: GameState, team: int) -> bool:
	if _can_strike_an_opponent(state, team, false):
		return true
	return _opponents_can_strike(state, team, false)


## Production advice: the units his doctrine gives eyes are the ones he fields.
func build_bias(_state: GameState, _team: int, unit_type: UnitType) -> int:
	return scout_build_bias if unit_type.id in scout_ids else 0
