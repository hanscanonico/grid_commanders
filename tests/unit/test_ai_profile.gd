extends GutTest
## The AIProfile seam: the shipped file and the class defaults must agree field
## for field, so an install missing its profile file plays the same game, and
## the planner must actually read the profile it was handed rather than a
## hardcoded copy.

const TIER_DIR := "res://data/ai"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


## Every profile the game ships, discovered rather than listed, so a tier added
## later is held to the same rule without anyone remembering to name it here.
func _tier_paths() -> Array[String]:
	var paths: Array[String] = []
	for file_name in DirAccess.get_files_at(TIER_DIR):
		if file_name.get_extension() == "tres":
			paths.append("%s/%s" % [TIER_DIR, file_name])
	paths.sort()
	return paths


## The fields a .tres can actually store: an @export carries STORAGE, a plain
## script var does not, and demanding one of those in data would be unfixable.
func _stored_fields() -> Array[String]:
	var fields: Array[String] = []
	for property in AIProfile.new().get_property_list():
		var usage := int(property.usage)
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_STORAGE):
			continue
		var field: String = property.name
		fields.append(field)
	return fields


func test_default_profile_loads() -> void:
	var profile := AIProfile.load_default()
	assert_not_null(profile, "res://data/ai/default.tres should load")


## The shipped file and the script's own defaults have to be the same numbers.
## ai_profile.gd promises exactly that, and load_default() leans on it: a match
## played with the file missing must be the match the file would have produced,
## or a broken install quietly plays a different game.
##
## Compared field by field off the property list rather than value by value, so
## tuning a weight means one edit to the .tres and one to the default beside it —
## and forgetting either is what fails here. That makes it the tripwire the
## hand-written version was, without being a chore every time a weight is added.
func test_default_profile_matches_the_built_in_defaults() -> void:
	var shipped := AIProfile.load_default()
	var defaults := AIProfile.new()
	var checked := 0
	for property in defaults.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var field: String = property.name
		assert_eq(shipped.get(field), defaults.get(field), "data/ai/default.tres: %s" % field)
		checked += 1
	assert_gt(checked, 10, "the profile should expose its weights as script variables")


## Every tier owns every balance value explicitly. Otherwise changing an
## AIProfile code default silently retunes only the tiers that omitted it.
func test_every_tier_explicitly_writes_every_profile_field() -> void:
	var fields := _stored_fields()
	assert_gt(fields.size(), 10, "the profile should export its weights")

	var paths := _tier_paths()
	assert_false(paths.is_empty(), "no profile found under %s to check" % TIER_DIR)
	for path in paths:
		var source: String = FileAccess.get_file_as_string(path)
		for field in fields:
			assert_true(
				source.contains("\n%s =" % field), "%s must explicitly write %s" % [path, field]
			)


## ai/threat_map.gd and the ranking block in ai_profile.gd both say the threat
## map is not one tier's smart. That is a claim about the shipped tiers, so it is
## checked rather than asserted in prose: Normal is the only tier that builds no
## threat map at all, and every other tier — gentler and harsher alike — weighs
## at least one of the three dials that read it.
func test_normal_is_the_only_tier_that_weighs_no_threat_dial() -> void:
	var db := DifficultyDB.load_default()
	var tiers := db.all()
	assert_gt(tiers.size(), 2, "the ladder should ship more than a pair of tiers")
	for tier in tiers:
		var profile := tier.profile()
		var weighs_threat := (
			profile.threat_aversion > 0.0
			or profile.advance_threat_tiles > 0.0
			or profile.withdraw_weight > 0.0
		)
		if tier.id == Difficulty.DEFAULT_ID:
			assert_false(weighs_threat, "%s: Normal is the threat-blind baseline" % tier.id)
		else:
			assert_true(weighs_threat, "%s: should weigh at least one threat dial" % tier.id)


## A controller built without a profile must behave exactly like one built with
## the shipped profile — that is what keeps every existing caller unchanged.
func test_omitted_profile_falls_back_to_the_default() -> void:
	var implicit := AIController.new(unit_db)
	var explicit := AIController.new(unit_db, AIProfile.load_default())
	var map_text := "[terrain]\n....\n[units]\n1 t 1 0\n2 i 0 0\n2 g 2 0"
	var from_implicit := implicit.plan_next_command(Fixture.state(map_text))
	var from_explicit := explicit.plan_next_command(Fixture.state(map_text))
	assert_true(from_implicit is AttackCommand)
	assert_eq(
		(from_implicit as AttackCommand).target_cell, (from_explicit as AttackCommand).target_cell
	)


## Proves the profile is wired through rather than stored and ignored: an
## infantry one step from a city normally captures it, but a profile that
## values capturing at nothing must make it do something else.
func test_profile_actually_drives_the_decision() -> void:
	var map_text := "[terrain]\n.C\n[units]\n1 i 0 0"

	var default_ai := AIController.new(unit_db)
	assert_true(
		default_ai.plan_next_command(Fixture.state(map_text)) is CaptureCommand,
		"the shipped profile should capture an adjacent city"
	)

	var indifferent := AIProfile.new()
	indifferent.capture_score = 0.0
	indifferent.hq_capture_multiplier = 0.0
	indifferent.capture_progress_bonus = 0.0
	var tuned_ai := AIController.new(unit_db, indifferent)
	assert_false(
		tuned_ai.plan_next_command(Fixture.state(map_text)) is CaptureCommand,
		"a profile that scores captures at zero should not choose one"
	)


## The HQ multiplier is what makes the AI walk past a city to reach the enemy
## HQ. Neutralising it should flip that preference to the nearer property.
func test_hq_preference_comes_from_the_profile() -> void:
	var map_text := "[terrain]\nQC.\n[owners]\n2 0 0\n[units]\n1 i 2 0"

	var default_pick := AIController.new(unit_db).plan_next_command(Fixture.state(map_text))
	assert_true(default_pick is CaptureCommand)
	var hq_path: Array[Vector2i] = (default_pick as CaptureCommand).path
	assert_eq(hq_path[hq_path.size() - 1], Vector2i(0, 0), "shipped profile should prefer the HQ")

	var no_hq_bias := AIProfile.new()
	no_hq_bias.hq_capture_multiplier = 1.0
	var flat_pick := AIController.new(unit_db, no_hq_bias).plan_next_command(
		Fixture.state(map_text)
	)
	assert_true(flat_pick is CaptureCommand)
	var flat_path: Array[Vector2i] = (flat_pick as CaptureCommand).path
	assert_eq(
		flat_path[flat_path.size() - 1],
		Vector2i(1, 0),
		"without the HQ multiplier the closer city wins on step cost"
	)
