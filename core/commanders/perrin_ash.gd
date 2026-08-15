class_name PerrinAsh
extends CommanderType
## Aurora Compact. Ash owns the air and leaves every other domain untouched.
## Air Superiority stays up through the opposing turn, covering both the strike
## and the flight home that make air warfare distinct.

## The always-on half is "his air units", so it stays keyed to AIR whatever the
## power reaches.
@export var air_attack_pct: int = 10
@export var superiority_attack_pct: int = 10
## The domain Air Superiority actually reaches, for the bonus and for the
## wants_power gate alike. A ground-only army gains nothing from it, so the meter
## is worth more banked than spent.
@export var superiority_domain: StringName = UnitType.AIR


func attack_bonus(state: GameState, fight: Engagement) -> int:
	var domain: StringName = fight.attacker.type.domain
	var bonus := air_attack_pct if domain == UnitType.AIR else 0
	if domain == superiority_domain and _is_active(state, fight.attacker.team):
		bonus += superiority_attack_pct
	return bonus


func wants_power(state: GameState, team: int) -> bool:
	return _has_air_unit(state, team) and super(state, team)


## Deliberately not ready-only: the power lasts a ROUND, so an aircraft that has
## already acted still collects the bonus on its counters through the opposing
## turn.
func _has_air_unit(state: GameState, team: int) -> bool:
	for unit in state.units_of(team):
		if unit.carrier == null and unit.type.domain == superiority_domain:
			return true
	return false
