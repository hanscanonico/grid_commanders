extends GutTest
## The balance levers COM-182 moved out of core/ constants and into
## RulesConfig / data/rules.tres: load_default() promises the shipped values,
## a state built with no config plays them unchanged, a custom config steers
## the rules that used to read the constants, and a missing file falls back
## to the same numbers.

var terrain_db: TerrainDB
var unit_db: UnitDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()


func test_default_config_loads() -> void:
	var config := RulesConfig.load_default()
	assert_not_null(config, "res://data/rules.tres should load")


## The shipped file has to carry the numbers that used to be the core/
## constants this ticket replaced, or an install with the file in place would
## play a different game from one without it.
func test_default_config_matches_shipped_values() -> void:
	var config := RulesConfig.load_default()
	assert_eq(config.capture_points, GameState.CAPTURE_POINTS)
	assert_eq(config.income_per_property, GameState.INCOME_PER_PROPERTY)
	assert_eq(config.repair_hp, 20)
	assert_eq(config.property_vision, 2)
	assert_eq(config.charge_pct_lost, 100)
	assert_eq(config.charge_pct_dealt, 50)
	assert_eq(config.min_price, 500)
	assert_eq(config.price_step, 100)
	assert_eq(config.luck_min, CommanderType.LUCK_MIN)
	assert_eq(config.luck_max, CommanderType.LUCK_MAX)
	assert_eq(config.max_stars, CommanderType.MAX_STARS)


## load_default() falls back to a bare RulesConfig.new() the moment load()
## cannot produce one -- a missing or broken data/rules.tres -- so proving the
## two agree field by field is proving that fallback plays today's game. The
## same tripwire test_ai_profile.gd holds AIProfile's own default to.
func test_missing_file_fallback_matches_the_shipped_defaults() -> void:
	var shipped := RulesConfig.load_default()
	var fallback := RulesConfig.new()
	var checked := 0
	for property in fallback.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var field: String = property.name
		assert_eq(shipped.get(field), fallback.get(field), "data/rules.tres: %s" % field)
		checked += 1
	assert_gt(checked, 5, "the config should expose its levers as script variables")


## A state built without naming a config -- every caller and fixture in the
## suite -- gets GameState.rules_config's own default and plays exactly as it
## did before this ticket.
func test_a_state_with_no_named_config_plays_the_defaults() -> void:
	var map := MapData.parse("[terrain]\nC\n[units]\n1 t 0 0", terrain_db)
	var state := GameState.create(map, unit_db)
	assert_not_null(state)
	state.set_owner(Vector2i(0, 0), 1)
	assert_eq(TurnRules.income_for(state, 1), GameState.INCOME_PER_PROPERTY)


## A custom config actually steers the rule that used to read the constant it
## replaced.
func test_a_custom_config_moves_income() -> void:
	var map := MapData.parse("[terrain]\nC\n[units]\n1 t 0 0", terrain_db)
	var config := RulesConfig.new()
	config.income_per_property = 5000
	var state := GameState.create(map, unit_db, null, {}, [], config)
	assert_not_null(state)
	state.set_owner(Vector2i(0, 0), 1)
	assert_eq(TurnRules.income_for(state, 1), 5000)
	assert_ne(TurnRules.income_for(state, 1), GameState.INCOME_PER_PROPERTY)


## And capture points: a lowered threshold lets one full-strength infantry
## finish a capture that the shipped 20 would only chip.
func test_a_custom_config_moves_capture_points() -> void:
	var map := MapData.parse("[terrain]\nC\n[units]\n1 i 0 0", terrain_db)
	var config := RulesConfig.new()
	config.capture_points = 5
	var state := GameState.create(map, unit_db, null, {}, [], config)
	assert_not_null(state)
	var infantry := state.units[0]
	var command := CaptureCommand.new(infantry, [Vector2i(0, 0)])
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(command.result.captured, "a full-HP infantry's strength clears a 5-point property")
