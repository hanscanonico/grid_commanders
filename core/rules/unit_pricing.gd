class_name UnitPricing
extends RefCounted
## The one purchase-price authority. A UnitType's cost remains its strategic
## value for combat charge, repairs, target scoring and army valuation; only an
## actual production purchase asks this rule.

const MIN_PRICE := 500
const PRICE_STEP := 100


## The commander's percentage is applied to the base value, rounded down to a
## hundred and floored so even the smallest unit always costs something.
static func cost_for(state: GameState, team: int, unit_type: UnitType) -> int:
	if state == null or unit_type == null:
		return 0
	var pct := maxi(0, state.commander_of(team).build_cost_pct(state, team, unit_type))
	@warning_ignore("integer_division")
	var scaled: int = unit_type.cost * pct / 100
	@warning_ignore("integer_division")
	var rounded: int = scaled / PRICE_STEP * PRICE_STEP
	return maxi(MIN_PRICE, rounded)
