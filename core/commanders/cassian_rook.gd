class_name CassianRook
extends CommanderType
## Aurora Compact. Deployment: his light units outrun everyone and his heavy
## ones hit softer, so he wins by being where the fight is not. Rapid
## Redeployment is the largest movement swing on the roster and deliberately
## costs him the turn's damage to use it — it repositions an army, it does not
## win a fight.

@export var light_ids: Array[StringName] = [&"recon", &"apc"]
@export var light_move_bonus: int = 1
@export var heavy_ids: Array[StringName] = [&"tank", &"md_tank"]
## Negative on purpose: the price of the mobility above.
@export var heavy_attack_pct: int = -10
@export var redeploy_move_bonus: int = 2
## Negative on purpose: a repositioning turn, not an attacking one.
@export var redeploy_attack_pct: int = -20
## Build-list places his fast units are pulled up. Counted from the end of
## build_priority for the recon, which is on no tier's list, so it moved with the
## list's length when rockets joined — see Orin Flux's scout_build_bias.
@export var light_build_bias: int = -4


func attack_bonus(state: GameState, fight: Engagement) -> int:
	var bonus := 0
	if fight.attacker.type.id in heavy_ids:
		bonus += heavy_attack_pct
	if _is_active(state, fight.attacker.team):
		bonus += redeploy_attack_pct
	return bonus


func move_bonus(state: GameState, unit: Unit) -> int:
	var bonus := light_move_bonus if unit.type.id in light_ids else 0
	if _is_active(state, unit.team):
		bonus += redeploy_move_bonus
	return bonus


## Redeployment pays in position and charges the turn's damage for it, so the
## default offensive read fired it on exactly the turn it penalises — a fight,
## with nothing for the movement to buy. It fires for ground instead, like
## every power measured in something other than damage: a capture the army can
## stand on this turn, counted with the power's own move bonus. Deliberately
## not gated on the fight being absent: an army in constant contact would then
## bank the meter all match, and a banked meter never spent is the failure the
## toolkit exists to avoid.
func wants_power(state: GameState, team: int) -> bool:
	return _can_reach_capture(state, team, redeploy_move_bonus)


## Production advice: the units his doctrine speeds up are the ones he fields.
func build_bias(_state: GameState, _team: int, unit_type: UnitType) -> int:
	return light_build_bias if unit_type.id in light_ids else 0
