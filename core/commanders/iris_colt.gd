class_name IrisColt
extends CommanderType
## Meridian Coalition. Colt's army gives up raw combat power for tempo. Second
## Wind refreshes only units whose committed action did not attack; builds and
## attackers remain exhausted.

@export var combat_pct: int = -10


func attack_bonus(_state: GameState, _fight: Engagement) -> int:
	return combat_pct


func defense_bonus(_state: GameState, _fight: Engagement) -> int:
	return combat_pct


func on_power_activated(state: GameState, team: int, _target: Vector2i = Vector2i.ZERO) -> void:
	for unit in state.units_of(team):
		if unit.carrier == null and unit.acted and unit.refreshable:
			unit.acted = false
			unit.refreshable = false


## Fire only when some refreshed unit's second action can produce something the
## rules recognise: a shot it can actually take, or ground it can actually take.
##
## The loose "any refreshable unit" gate this replaces was true on essentially
## every full meter, because Colt fires AFTER_ACTIONS — by then the planner has
## already spent every unit, so the condition only asked whether the army had
## moved. One analysed match fired 43 times and bought nothing 24 of them.
##
## A second *advance* is deliberately refused, even though the power grants one:
## a unit the planner had nothing better for than a walk is exactly what those 24
## firings bought, and a full meter is worth more than a second walk. The failure
## this errs toward is now banking rather than over-firing, and the analyser's
## banked_power is what would measure it.
func wants_power(state: GameState, team: int) -> bool:
	for unit in state.units_of(team):
		if unit.carrier != null or not unit.acted or not unit.refreshable:
			continue
		if _can_open_fire(state, team, unit) or _unit_can_reach_capture(state, team, unit):
			return true
	return false


## True when this unit could bring a visible enemy under fire once refreshed.
## AttackRange.threat_cells is the union over every cell it can fire from, so
## "walk into range and shoot" is one question to one authority; can_fire is the
## same authority on whether the weapon can touch that target at all.
func _can_open_fire(state: GameState, team: int, unit: Unit) -> bool:
	var covered: Dictionary[Vector2i, bool] = {}
	for cell in AttackRange.threat_cells(state, unit):
		covered[cell] = true
	for target in state.units:
		if state.allied(target.team, team) or target.carrier != null:
			continue
		if not covered.has(target.cell) or Vision.is_hidden_from(state, team, target):
			continue
		if AttackRange.can_fire(state, unit, target):
			return true
	return false
