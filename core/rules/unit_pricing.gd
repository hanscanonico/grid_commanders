class_name UnitPricing
extends RefCounted
## The one purchase-price authority. A UnitType's cost remains its strategic
## value for combat charge, repairs, target scoring and army valuation; only an
## actual production purchase asks this rule.


## The commander's percentage is applied to the base value, rounded down to
## `state.rules_config.price_step` and floored at `min_price` so even the
## smallest unit always costs something.
static func cost_for(state: GameState, team: int, unit_type: UnitType) -> int:
	if state == null or unit_type == null:
		return 0
	var pct := maxi(0, state.commander_of(team).build_cost_pct(state, team, unit_type))
	@warning_ignore("integer_division")
	var scaled: int = unit_type.cost * pct / 100
	var step := state.rules_config.price_step
	@warning_ignore("integer_division")
	var rounded: int = scaled / step * step
	return maxi(state.rules_config.min_price, rounded)
