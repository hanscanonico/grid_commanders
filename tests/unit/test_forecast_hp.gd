extends GutTest
## The HP fields on CombatResolver.Forecast that exist for the damage preview and
## for nothing else (UX recovery plan D4 — forecasts speak HP first).
##
## The sibling of test_combat_snapshot.gd, and for the same reason: this is not
## the formula, it is the record the presentation layer is allowed to replay.
## The preview used to print the raw percentages and let the player convert;
## now it prints HP, and a wrong bound here is invisible in play — the panel
## would promise a kill it cannot land and still look perfectly plausible.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return state


## Displayed HP, like every other HP the player is shown — not the internal
## 0-100 the formula subtracts in.
func test_forecast_snapshots_displayed_hp_for_both_sides() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	var attacker := state.units[0]
	var defender := state.units[1]
	attacker.hp = 55  # 6 displayed
	defender.hp = 74  # 8 displayed
	var forecast := CombatResolver.forecast(state, attacker, attacker.cell, defender)
	assert_true(forecast.can_attack)
	assert_eq(forecast.attacker_hp_before, 6)
	assert_eq(forecast.defender_hp_before, 8)


## The bounds are the luck range, and the luck-free percentage is its floor: the
## best the defender walks away with is exactly what the percentage alone says.
func test_defender_bounds_span_the_luck_range() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	var attacker := state.units[0]
	var defender := state.units[1]
	var forecast := CombatResolver.forecast(state, attacker, attacker.cell, defender)
	assert_eq(
		forecast.defender_hp_after_max,
		ceili((defender.hp - forecast.attack_damage) / 10.0),
		"the unluckiest roll leaves the luck-free HP standing"
	)
	assert_eq(
		forecast.defender_hp_after_min,
		ceili((defender.hp - forecast.attack_damage - CommanderType.LUCK_MAX) / 10.0),
		"the luckiest roll takes the ceiling of the range off"
	)
	assert_lte(forecast.defender_hp_after_min, forecast.defender_hp_after_max)


## The one thing a forecast may never do is promise more than the roll can take:
## every damage the resolver can actually roll has to land inside the bounds.
func test_bounds_contain_every_roll_the_resolver_can_produce() -> void:
	for seed_value in range(40):
		var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
		state.rng.seed = seed_value
		var attacker := state.units[0]
		var defender := state.units[1]
		var forecast := CombatResolver.forecast(state, attacker, attacker.cell, defender)
		var attacker_before := attacker.displayed_hp()
		CombatResolver.resolve(state, attacker, defender)
		var defender_left := defender.displayed_hp() if defender.hp > 0 else 0
		var attacker_left := attacker.displayed_hp() if attacker.hp > 0 else 0
		assert_between(
			defender_left,
			forecast.defender_hp_after_min,
			forecast.defender_hp_after_max,
			"defender landed outside the forecast on seed %d" % seed_value
		)
		assert_between(
			attacker_left,
			forecast.attacker_hp_after_min,
			forecast.attacker_hp_after_max,
			"attacker landed outside the forecast on seed %d" % seed_value
		)
		assert_eq(forecast.attacker_hp_before, attacker_before)


## The same containment where the opening roll decides whether a counter happens
## at all: a lucky shot kills the defender and the attacker takes nothing, which
## the counter's own spread alone can never account for.
func test_attacker_bounds_survive_a_shot_that_may_kill_the_counter() -> void:
	for seed_value in range(40):
		var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 T 1 0")
		state.rng.seed = seed_value
		var attacker := state.units[0]
		var defender := state.units[1]
		defender.hp = 5  # one lucky point of damage from dead
		var forecast := CombatResolver.forecast(state, attacker, attacker.cell, defender)
		assert_true(forecast.can_attack)
		assert_eq(
			forecast.attacker_hp_after_max,
			forecast.attacker_hp_before,
			"a roll that kills the target leaves no counter to take"
		)
		CombatResolver.resolve(state, attacker, defender)
		assert_between(
			attacker.displayed_hp() if attacker.hp > 0 else 0,
			forecast.attacker_hp_after_min,
			forecast.attacker_hp_after_max,
			"attacker landed outside the forecast on seed %d" % seed_value
		)


## A counter that cannot happen leaves the attacker's three numbers equal, so the
## preview has nothing to draw a range from and says "no counter" off the
## percentage flag it always has.
func test_no_counter_leaves_the_attacker_untouched() -> void:
	# An artillery firing from range 2: the infantry cannot shoot back.
	var state := _state("[terrain]\n...\n[units]\n1 a 0 0\n2 i 2 0")
	var attacker := state.units[0]
	var forecast := CombatResolver.forecast(state, attacker, attacker.cell, state.units[1])
	assert_true(forecast.can_attack)
	assert_eq(forecast.counter_damage, -1)
	assert_eq(forecast.attacker_hp_after_min, forecast.attacker_hp_before)
	assert_eq(forecast.attacker_hp_after_max, forecast.attacker_hp_before)


## A counter that can happen gets its own spread, from the *defending* side's
## commander — the counter's attacker is the unit shooting back.
func test_counter_bounds_come_from_the_countering_side() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0")
	var attacker := state.units[0]
	var forecast := CombatResolver.forecast(state, attacker, attacker.cell, state.units[1])
	assert_gt(forecast.counter_damage, 0)
	assert_eq(
		forecast.attacker_hp_after_min,
		ceili((attacker.hp - forecast.counter_damage - CommanderType.LUCK_MAX) / 10.0),
		"the unluckiest exchange is the luck-free counter rolling its own ceiling"
	)
	assert_gte(
		forecast.attacker_hp_after_max,
		ceili((attacker.hp - forecast.counter_damage) / 10.0),
		"a lucky shot only ever weakens the counter, so the best case is no worse"
	)
	assert_lt(forecast.attacker_hp_after_min, forecast.attacker_hp_before)


## Lyra Quill's floor is the case the luck-free percentage alone gets wrong: her
## rolls never come up short, so the HP bounds must start above it.
func test_a_lucky_floor_raises_the_defender_bounds() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	var lyra: LyraQuill = CommanderDB.load_default().by_id(&"lyra_quill")
	state.set_commander(1, lyra)
	var attacker := state.units[0]
	var defender := state.units[1]
	var forecast := CombatResolver.forecast(state, attacker, attacker.cell, defender)
	assert_eq(
		forecast.defender_hp_after_max,
		ceili((defender.hp - forecast.attack_damage - lyra.lucky_floor) / 10.0),
		"even her worst roll takes lucky_floor off"
	)
	assert_lte(forecast.defender_hp_after_min, forecast.defender_hp_after_max)
