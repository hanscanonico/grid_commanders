extends GutTest
## The AIProfile seam: the shipped file and the class defaults must agree field
## for field, so an install missing its profile file plays the same game, and
## the planner must actually read the profile it was handed rather than a
## hardcoded copy.

const TIER_DIR := "res://data/ai"

## Every dial that reads zero on all four shipped tiers, with why it ships that
## way — the AIProfile side of test_commander_ai_advice.gd's ADVICE_COVERAGE.
## Under the AI Judgement D1 contract an inert dial skips its capability
## entirely, so each of these is code no shipped match runs, and seating one is
## a balance change. Listed here, it is a change this file names.
##
## A reason is read off the design record, never invented — docs/difficulty_check.md,
## docs/ai_arena_results.md, docs/causeway_measure.md and ai/ai_profile.gd's own
## fields — and a dial nobody has measured says so. bank_scope and bank_rank_margin
## are inert by nature rather than by verdict: zero is the shipped planner's own
## answer, and what each does when moved is
## tests/unit/test_ai_production_cadence.gd's.
const DARK_DIALS := {
	"focus_fire_bonus": "worthless on three refutations (docs/difficulty_check.md)",
	"withdraw_weight": "negative at every value tried, then the arena left it at zero",
	"join_weight": "AR6c's dial, declined through four arena waves (docs/ai_arena_results.md)",
	"capture_goal_value_tiles": "inert from AE1-AE3; the arena's search never stepped off zero",
	"capture_threat_aversion": "changed nothing on the free-for-all, never carried to the 2v2",
	"standoff_band_tolerance": "no recorded measurement; a content gun is easier to close on",
	"bank_scope": "zero is BANK_SCOPE_BOARD, one banking answer for the whole board",
	"bank_rank_margin": "zero banks for a one-place improvement, which is the shipped planner",
}

var unit_db: UnitDB


func before_each() -> void:
	unit_db = Fixture.unit_db()


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
## at least one of the four dials that read it. Which dials those are is
## `builds_threat_map`'s answer, asked rather than restated here: a guardrail
## that re-derived the list would fail on the day a tier seats only the dial it
## had forgotten, and pass a tier that builds no map at all.
func test_normal_is_the_only_tier_that_weighs_no_threat_dial() -> void:
	var db := DifficultyDB.load_default()
	var tiers := db.all()
	assert_gt(tiers.size(), 2, "the ladder should ship more than a pair of tiers")
	for tier in tiers:
		var profile := tier.profile()
		var weighs_threat := profile.builds_threat_map()
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


## What a .tres can hold that this file can call inert: a number at zero. An
## array or a StringName has no dark value, so the sweep below never asks.
func _is_dark(value: Variant) -> bool:
	var kind := typeof(value)
	if kind != TYPE_INT and kind != TYPE_FLOAT:
		return false
	return value == 0


func _tier_profiles() -> Array[AIProfile]:
	var profiles: Array[AIProfile] = []
	for tier in DifficultyDB.load_default().all():
		profiles.append(tier.profile())
	return profiles


## Every dial DARK_DIALS names really is inert wherever it ships, so the
## inventory cannot go stale by a tier seating one quietly.
func test_every_listed_dark_dial_is_inert_on_every_tier() -> void:
	var fields := _stored_fields()
	for dial: String in DARK_DIALS:
		assert_true(fields.has(dial), "%s: DARK_DIALS should name a stored field" % dial)
		for profile in _tier_profiles():
			assert_true(_is_dark(profile.get(dial)), "%s: listed as dark, seated instead" % dial)


## The converse, and the half that makes the inventory a gate: a dial that is
## zero everywhere and unlisted fails until somebody writes down why it ships
## dark. Together with the test above, seating a listed dial or darkening an
## unlisted one is a failure naming the dial rather than a silent balance move.
func test_no_unlisted_dial_is_inert_on_every_tier() -> void:
	var profiles := _tier_profiles()
	assert_gt(profiles.size(), 2, "the ladder should ship more than a pair of tiers")
	for field in _stored_fields():
		var dark_everywhere := true
		for profile in profiles:
			dark_everywhere = dark_everywhere and _is_dark(profile.get(field))
		if dark_everywhere:
			assert_true(DARK_DIALS.has(field), "%s: inert on every tier and unlisted" % field)
