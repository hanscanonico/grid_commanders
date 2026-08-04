class_name OrinFlux
extends CommanderType
## Aurora Compact. Intelligence: he sees further than anyone and, for a round,
## makes sure nobody else does. Signal Jam is the only power that reaches across
## the table, and it uses both halves of the power machinery — a one-shot strip
## of fuel and ammo, and an ongoing debuff that lasts until the jamming lifts.
##
## ROUND duration, so "enemy vision -1 until their next turn" means what it says:
## it has to still be running while the opponent plays.

@export var scout_ids: Array[StringName] = [&"recon", &"apc"]
@export var scout_vision_bonus: int = 1
@export var jam_vision_penalty: int = -1
@export var jam_fuel_loss: int = 10
@export var jam_ammo_loss: int = 1
## Build-list places his scouts are pulled up — the smallest bias on the
## roster, honestly: the AI's targeting is omniscient-except-hidden, so extra
## sight buys its fog-limited *pathing* something and its aim nothing.
@export var scout_build_bias: int = -2


func vision_bonus(_state: GameState, unit: Unit) -> int:
	return scout_vision_bonus if unit.type.id in scout_ids else 0


## Asked of *his* commander about an enemy unit, which is what makes this the
## one hook a doctrine uses to reach the other side of the board. Vision floors
## the total at 0, so a jammed scout goes blind rather than inside-out.
func enemy_vision_bonus(state: GameState, team: int, _unit: Unit) -> int:
	return jam_vision_penalty if _is_active(state, team) else 0


## A jam is a hostile effect, so it stops at the side boundary rather than at his
## own army: asked of the allegiance authority, which is what keeps the power's
## two halves agreeing about who the enemy is — the ongoing debuff already asks it
## through Vision's sight loop and enemy_vision_bonus.
func on_power_activated(state: GameState, team: int, _target: Vector2i = Vector2i.ZERO) -> void:
	for unit in state.units:
		if state.allied(unit.team, team):
			continue
		unit.fuel = maxi(0, unit.fuel - jam_fuel_loss)
		if unit.type.max_ammo > 0:
			unit.ammo = maxi(0, unit.ammo - jam_ammo_loss)


## A debuff is at its best going off *before* the exchange, so this asks whether
## the two armies are in contact at all rather than whether he personally has a
## shot: a tile of sight and a turn of fuel and ammo change what the opponent
## can do next turn whichever side is closing the distance.
func wants_power(state: GameState, team: int) -> bool:
	if _can_strike_an_opponent(state, team, false):
		return true
	return _opponents_can_strike(state, team, false)


## Production advice: the units his doctrine gives eyes are the ones he fields.
func build_bias(_state: GameState, _team: int, unit_type: UnitType) -> int:
	return scout_build_bias if unit_type.id in scout_ids else 0
