class_name IonaVance
extends CommanderType
## Meridian Coalition. The even hand: every unit she fields hits a little harder
## and is a little harder to hurt, in every domain and every exchange, and
## nothing anywhere is paid for it.
##
## Tip the Scales is that same evenness at the scale of the whole board — a pip
## onto her army, a pip off every hostile one, in a single command. It never
## takes a unit off the board: both halves are clamped, so nothing leaves and
## GameState.remove_unit is never called.

@export var steady_attack_pct: int = 3
## Read as (200 - def) / 100, so a point here is worth a point of attack: +3 is
## x0.97 taken exactly as +3 attack is x1.03 dealt. Both terms count equally,
## which is the even hand written as arithmetic.
@export var steady_defense_pct: int = 3
## Internal HP the swing moves on each side — 10 is one displayed pip.
@export var scales_heal_hp: int = 10
@export var scales_harm_hp: int = 10
## The internal HP the harm may never take a unit below: one pip, still standing.
@export var scales_floor_hp: int = 10


func attack_bonus(_state: GameState, _fight: Engagement) -> int:
	return steady_attack_pct


func defense_bonus(_state: GameState, _fight: Engagement) -> int:
	return steady_defense_pct


## The two halves take two questions to two authorities. Health is
## infrastructure, so the heal stops at her own army — an ally's workshop does
## not mend her tanks — while the harm is hostile and stops at the side boundary,
## exactly as Signal Jam does, so a four-seat board is three opponents at once.
func on_power_activated(state: GameState, team: int, _target: Vector2i = Vector2i.ZERO) -> void:
	for unit in state.units_of(team):
		unit.hp += _heal_hp(unit)
	for unit in state.units:
		if not state.allied(unit.team, team):
			unit.hp -= _harm_hp(unit)


## Worth firing when the swing has pips to move and the armies are in contact: an
## army already at full health earns nothing from the heal and an opponent
## already on the floor nothing from the harm, and pips only become won exchanges
## where there are exchanges to win. Contact is read both ways round, because the
## swing wins her the fights she starts and the ones started on her alike.
func wants_power(state: GameState, team: int) -> bool:
	if _swing_hp(state, team) <= 0:
		return false
	return super(state, team) or _opponents_can_strike(state, team, false)


## The internal HP firing would actually move, both halves in the one currency
## the power is written in — so the gate and the effect cannot disagree about
## what a firing is worth. Enemies are read through the sight authority, like
## every other doctrine gate.
func _swing_hp(state: GameState, team: int) -> int:
	var moved := 0
	for unit in state.units_of(team):
		moved += _heal_hp(unit)
	for unit in state.units:
		if state.allied(unit.team, team) or Vision.is_hidden_from(state, team, unit):
			continue
		moved += _harm_hp(unit)
	return moved


func _heal_hp(unit: Unit) -> int:
	return mini(scales_heal_hp, 100 - unit.hp)


## A floor rather than a level: a unit standing on its last pip keeps it, and one
## already below the floor is left where it is instead of being topped up to it.
func _harm_hp(unit: Unit) -> int:
	return maxi(0, mini(scales_harm_hp, unit.hp - scales_floor_hp))
