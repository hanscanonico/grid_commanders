extends GutTest
## The search space: which dials a block moves, over what range, and what the
## table is not allowed to get wrong.
##
## Three of these are the harness's honesty rather than its convenience. A dial
## that fell off the shelf makes the search explore a smaller space than it
## reports and nothing downstream can see that it did; a range that cannot
## express a shipped tier cannot reproduce the known answer AR5 is calibrated
## against; and a range wider than the `@export` declares is a sampler licensed
## to invert the valuation the export exists to bound.

const TIERS: Array[String] = ["easy", "default", "hard"]
## Floating point, over a lattice stated in tenths and eighths.
const TOLERANCE := 1e-6


func test_every_dial_is_a_number_on_the_profile() -> void:
	for field: StringName in ArenaBlocks.DIALS:
		assert_true(ArenaBlocks.numeric(field), "%s is a number AIProfile carries" % field)


func test_every_dial_belongs_to_a_block() -> void:
	var claimed: Dictionary = {}
	for name: String in ArenaBlocks.names():
		for field: StringName in ArenaBlocks.fields_of(name):
			claimed[field] = true
	for field: StringName in ArenaBlocks.DIALS:
		assert_true(claimed.has(field), "%s is declared and never searched" % field)


func test_every_live_weight_is_searched_or_excluded_with_a_reason() -> void:
	# The check that catches a dial nobody listed, and it has now paid twice. It
	# found defend_weight — in neither the plan's §5a table nor the ticket's, and
	# live at 2.0 on Normal and 2.5 on Difficult — and then COM-65's supply_weight
	# / supply_unit_target, which landed after the first campaign was measured and
	# went to the exclusion ledger as unsearched.
	for property: Dictionary in AIProfile.new().get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var field := StringName(property["name"])
		if not ArenaBlocks.numeric(field):
			continue  # build_priority and air_answer_ids: permutations, plan D9
		assert_true(
			ArenaBlocks.DIALS.has(field) or ArenaBlocks.EXCLUDED.has(field),
			"%s is a live weight in no block and on no exclusion list" % field
		)


func test_the_two_permutations_are_out_by_their_type() -> void:
	# D9: a permutation move and a step along an axis do not belong in one
	# proposal distribution, and nothing here can propose an array.
	assert_false(ArenaBlocks.numeric(&"build_priority"))
	assert_false(ArenaBlocks.numeric(&"air_answer_ids"))


func test_a_range_holds_every_shipped_tier_on_its_lattice() -> void:
	for tier: String in TIERS:
		var profile: AIProfile = load("res://data/ai/%s.tres" % tier)
		for field: StringName in ArenaBlocks.DIALS:
			var dial := ArenaBlocks.dial(field)
			var value := float(profile.get(field))
			assert_between(value, float(dial["low"]), float(dial["high"]), "%s.%s" % [tier, field])
			assert_true(_on_lattice(value, dial), "%s.%s sits on the lattice" % [tier, field])


func test_both_bounds_sit_on_the_lattice() -> void:
	# A bound off the lattice is a value the search can reach by clamping and
	# never by stepping, so two waves could name one vector two ways.
	for field: StringName in ArenaBlocks.DIALS:
		var dial := ArenaBlocks.dial(field)
		assert_true(_on_lattice(float(dial["low"]), dial), "%s low" % field)
		assert_true(_on_lattice(float(dial["high"]), dial), "%s high" % field)
		assert_gt(float(dial["min_step"]), 0.0, "%s has a precision" % field)
		assert_gte(float(dial["step"]), float(dial["min_step"]), "%s starts no finer" % field)


func test_no_dial_widens_the_range_its_export_declares() -> void:
	var declared := 0
	for field: StringName in ArenaBlocks.DIALS:
		var bounds := ArenaBlocks.declared_range(field)
		if bounds.is_empty():
			continue
		declared += 1
		var dial := ArenaBlocks.dial(field)
		assert_gte(float(dial["low"]), bounds[0], "%s low is inside the export's range" % field)
		assert_lte(float(dial["high"]), bounds[1], "%s high is inside the export's range" % field)
	assert_gt(declared, 0, "condition_weight declares one, so the check has something to check")


func test_a_coupled_dial_names_the_block_it_comes_home_to() -> void:
	for name: String in ArenaBlocks.names():
		var couples: Dictionary = ArenaBlocks.block(name)["couples"]
		for field: StringName in couples:
			var home := String(couples[field])
			assert_ne(home, name, "%s does not borrow from itself" % name)
			assert_true(
				field in ArenaBlocks.block(home)["fields"],
				"%s borrows %s from %s, which owns it" % [name, field, home]
			)


func test_a_block_searches_its_own_dials_then_the_ones_it_borrows() -> void:
	var fields := ArenaBlocks.fields_of("economy_map")
	assert_eq(fields[0], &"capture_units_per_property")
	assert_true(&"capture_unit_target" in fields, "the Production floor it raises comes with it")
	assert_true(&"cohesion_tiles" in fields, "the only tax a spreading capture line pays")
	assert_eq(fields.size(), 6, "four of its own and two borrowed, each once")
	assert_eq(ArenaBlocks.fields_of("nowhere").size(), 0)


func test_applying_a_vector_writes_it_in_the_profile_s_own_types() -> void:
	var profile := AIProfile.new()
	assert_eq(ArenaBlocks.apply(profile, {&"kill_bonus": 2.4, &"cohesion_radius": 3.0}), "")
	assert_eq(profile.kill_bonus, 2.4)
	assert_eq(profile.cohesion_radius, 3, "an int dial is written as an int")


func test_applying_refuses_what_would_not_be_a_candidate() -> void:
	var profile := AIProfile.new()
	assert_ne(ArenaBlocks.apply(profile, {&"build_priority": 1.0}), "", "not a number")
	assert_ne(ArenaBlocks.apply(profile, {&"no_such_dial": 1.0}), "", "not a dial")
	assert_ne(ArenaBlocks.apply(profile, {&"kill_bonus": "high"}), "", "not a value")
	assert_ne(
		ArenaBlocks.apply(profile, {&"condition_weight": 2.0}),
		"",
		"past 1.0 the interpolation prices a wounded unit below nothing"
	)
	assert_eq(profile.kill_bonus, AIProfile.new().kill_bonus, "a refusal writes nothing")


func _on_lattice(value: float, dial: Dictionary) -> bool:
	var steps: float = (value - float(dial["low"])) / float(dial["min_step"])
	return absf(steps - roundf(steps)) < TOLERANCE
