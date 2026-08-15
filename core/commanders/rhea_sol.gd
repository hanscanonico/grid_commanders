class_name RheaSol
extends CommanderType
## Meridian Coalition. Artillery doctrine: her indirect units hit harder and
## fold faster, so she wants a siege line with something else standing in front
## of it. Grid Saturation pushes that line one tile further out for a turn,
## which is the strongest tempo swing in wave 1 — a range her opponent set up
## against last turn is suddenly wrong.
##
## Keyed on being indirect rather than on unit ids: "artillery and rockets" is
## what the doctrine means today, and a future siege unit should inherit it.

@export var indirect_attack_pct: int = 10
## Negative on purpose: siege guns are soft, and this is what pays for the
## attack bonus above.
@export var indirect_defense_pct: int = -10
@export var saturation_attack_pct: int = 20
@export var saturation_range_bonus: int = 1
## Build-list places her indirects are pulled up: the siege line is the
## doctrine. Mild on purpose, and measured: at -4 the first full matrix with
## doctrine advice priced her at 34% — an army of guns the planner cannot
## move-and-fire — so the pull orders the cheap end of the list and leaves the
## top of it alone.
@export var indirect_build_bias: int = -2
## How many siege guns make a saturation. Below this the power buys a single
## unit's tile of range for a full meter, which is not what "saturation" means.
@export var saturation_want_guns: int = 1


## The base read — a fight to have this turn — plus the guns the power is for.
## Keyed on being indirect like the rest of the doctrine, so a future siege unit
## inherits the gate without an edit.
func wants_power(state: GameState, team: int) -> bool:
	return _ready_guns(state, team) >= saturation_want_guns and super(state, team)


func attack_bonus(state: GameState, fight: Engagement) -> int:
	if not AttackRange.is_indirect(fight.attacker):
		return 0
	var bonus := indirect_attack_pct
	if _is_active(state, fight.attacker.team):
		bonus += saturation_attack_pct
	return bonus


func defense_bonus(_state: GameState, fight: Engagement) -> int:
	return indirect_defense_pct if AttackRange.is_indirect(fight.defender) else 0


## The extra tile only reaches units that shoot over distance to begin with, so
## it never turns a direct unit into something that outranges a counter.
func range_bonus(state: GameState, unit: Unit) -> int:
	if not _is_active(state, unit.team) or not AttackRange.is_indirect(unit):
		return 0
	return saturation_range_bonus


## Production advice, keyed on being indirect like everything else here, so a
## future siege unit inherits the preference without an edit.
func build_bias(_state: GameState, _team: int, unit_type: UnitType) -> int:
	return indirect_build_bias if AttackRange.is_indirect_type(unit_type) else 0


func _ready_guns(state: GameState, team: int) -> int:
	var guns := 0
	for unit in state.units_of(team):
		if unit.carrier == null and not unit.acted and AttackRange.is_indirect(unit):
			guns += 1
	return guns
