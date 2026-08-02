class_name PerrinAsh
extends CommanderType
## Aurora Compact. Ash owns the air and leaves every other domain untouched.
## Air Superiority stays up through the opposing turn, covering both the strike
## and the flight home that make air warfare distinct.

@export var air_attack_pct: int = 10
@export var superiority_attack_pct: int = 10


func attack_bonus(state: GameState, fight: Engagement) -> int:
	if fight.attacker.type.domain != UnitType.AIR:
		return 0
	var bonus := air_attack_pct
	if _is_active(state, fight.attacker.team):
		bonus += superiority_attack_pct
	return bonus
