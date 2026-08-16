extends GutTest
## The difficulty tier seam (plan DF1): the tiers load, Normal is the planner's
## own defaults, an unknown id still plays, and the wiring is not inert — Easy's
## and Brutal's profiles must each provably reach a different command than
## Normal's.

## Our HQ at (0,0) with an enemy infantry standing on it, our tank one tile away,
## and a fatter target — an enemy tank — the same distance the other way.
const HQ_SIEGE := "[terrain]\nQ....\n.....\n[owners]\n1 0 0\n[units]\n1 t 1 1\n2 i 0 0\n2 t 2 1"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var db: DifficultyDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	db = DifficultyDB.load_default()


func test_every_tier_loads() -> void:
	assert_eq(db.size(), 4, "data/difficulty should hold easy, normal, hard and brutal")
	for id: StringName in [&"easy", &"normal", &"hard", &"brutal"]:
		assert_true(db.has(id), "missing difficulty tier '%s'" % id)
		assert_not_null(db.by_id(id).ai_profile, "tier '%s' has no AI profile" % id)


func test_tiers_are_listed_gentlest_first() -> void:
	var ids: Array[StringName] = []
	for tier in db.all():
		ids.append(tier.id)
	assert_eq(ids, [&"easy", &"normal", &"hard", &"brutal"] as Array[StringName])


func test_difficult_is_the_label_for_the_hard_id() -> void:
	# The UI says "Difficult"; the id stays short for flags and saves.
	assert_eq(db.by_id(&"hard").display_name, "Difficult")


## The pin that keeps Normal honest: the tier is the planner's own defaults, so
## an install whose profile file is missing plays the same game. The weights
## named here are the pre-difficulty set; parity across every field, including
## the ones added since, is test_ai_profile.gd's.
func test_normal_is_the_planner_defaults() -> void:
	var normal := db.by_id(&"normal").profile()
	var defaults := AIProfile.new()
	assert_almost_eq(normal.kill_bonus, defaults.kill_bonus, 0.0001)
	assert_almost_eq(normal.counter_weight, defaults.counter_weight, 0.0001)
	assert_almost_eq(normal.capture_score, defaults.capture_score, 0.0001)
	assert_almost_eq(normal.hq_capture_multiplier, defaults.hq_capture_multiplier, 0.0001)
	assert_almost_eq(normal.capture_progress_bonus, defaults.capture_progress_bonus, 0.0001)
	assert_almost_eq(normal.step_cost_penalty, defaults.step_cost_penalty, 0.0001)
	assert_almost_eq(normal.min_useful_score, defaults.min_useful_score, 0.0001)
	assert_almost_eq(normal.advance_score, defaults.advance_score, 0.0001)
	assert_eq(normal.retreat_hp, defaults.retreat_hp)
	assert_eq(normal.capture_unit_target, defaults.capture_unit_target)
	assert_eq(normal.build_priority, defaults.build_priority)


## Every Difficult-tier capability is off at Normal, so none of that code runs
## there. The AI Judgement dials are a separate set and Normal carries two of
## them live — docs/difficulty_check.md §4c, never this list.
func test_normal_leaves_every_capability_off() -> void:
	var normal := db.by_id(&"normal").profile()
	assert_almost_eq(normal.threat_aversion, 0.0, 0.0001)
	assert_almost_eq(normal.advance_threat_tiles, 0.0, 0.0001)
	assert_almost_eq(normal.focus_fire_bonus, 0.0, 0.0001)
	assert_almost_eq(normal.build_reactivity, 0.0, 0.0001)


## Difficult has to differ from Normal in the planner, not just on the label.
## focus_fire_bonus is deliberately 0: it measured negative on the DF4 ladder and
## is benched rather than deleted (docs/difficulty_check.md), so this pins both
## which capabilities carry the tier and which one is knowingly switched off.
func test_difficult_turns_the_capabilities_on() -> void:
	var hard := db.by_id(&"hard").profile()
	assert_gt(hard.threat_aversion, 0.0, "Difficult must actually weigh threat")
	assert_gt(hard.build_reactivity, 0.0, "Difficult must actually counter-build")
	# A weight this dial cannot act on is the same as no dial: below ~1.6 it
	# cannot buy a single tile away from a full-strength artillery shot, which is
	# how the tier once shipped a kill-zone refusal that never refused anything.
	assert_gt(
		hard.advance_threat_tiles,
		1.6,
		"Difficult's advance must be able to give up a whole tile, not just break ties"
	)
	assert_almost_eq(
		hard.focus_fire_bonus,
		0.0,
		0.0001,
		"focus fire is benched by measurement; switching it back on is a DF4 decision"
	)


## Brutal is a measurement rather than a tuning, so the sixteen dials the arena's
## first campaign moved off Normal are pinned here by value: an edit to any of
## them stops being a balance tweak and starts being a claim the campaign did not
## make. docs/ai_arena_results.md is the vector; a later campaign replaces this
## list wholesale rather than nudging an entry.
##
## It is the sixteen and no more: Brutal also carries capture_units_per_property,
## goal_engageability and spend_ceiling_turns, which were 0 throughout that
## campaign and are seated here at Normal's values by a different measurement
## (docs/causeway_measure.md's V4, read in docs/difficulty_check.md §4e), a higher
## tier not being allowed to be less capable than the middle one. They are
## deliberately absent from this list, which pins the search's own answer.
func test_brutal_is_the_searched_champion_verbatim() -> void:
	var brutal := db.by_id(&"brutal").profile()
	var searched := {
		"kill_bonus": 1.2,
		"counter_weight": 0.4,
		"capture_progress_bonus": 75.0,
		"step_cost_penalty": 0.0,
		"capture_unit_target": 0,
		"duplicate_priority_cost": 1,
		"save_up_turns": 0,
		"threat_aversion": 0.175,
		"advance_threat_tiles": 0.5,
		"build_reactivity": 0.6,
		"cohesion_tiles": 2.125,
		"cohesion_radius": 1,
		"capture_claim_depth": 1,
		"production_capture_multiplier": 2.0,
		"cover_tiles": 0.125,
		"condition_weight": 0.25,
	}
	var defaults := AIProfile.new()
	for field: String in searched:
		assert_eq(brutal.get(field), searched[field], "brutal.tres: %s" % field)
		assert_ne(brutal.get(field), defaults.get(field), "%s is not a searched dial" % field)


## The three dials the search was allowed to buy and declined stay switched off,
## the same remedy Difficult's benched focus fire gets: a capability measured
## worthless is zeroed rather than deleted, so re-trying it is one edit.
func test_brutal_leaves_the_refused_dials_off() -> void:
	var brutal := db.by_id(&"brutal").profile()
	for field: String in ["withdraw_weight", "join_weight", "focus_fire_bonus"]:
		assert_almost_eq(float(brutal.get(field)), 0.0, 0.0001, "brutal.tres: %s" % field)


## Guards against inert wiring the same way Easy's build test does, from the
## other end of the ladder: Brutal keeps no dedicated capture roster, so where
## Normal buys its third infantry Brutal spends the same funds on the hammer.
func test_brutal_reaches_a_different_command_than_normal() -> void:
	var map_text := "[terrain]\nB...\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0"

	var state := Fixture.state(map_text)
	state.funds[1] = 20000
	for unit in state.units:
		unit.acted = true
	var pick := AIController.new(unit_db, db.by_id(&"brutal").profile()).plan_next_command(state)
	assert_true(pick is BuildCommand, "expected a build, got %s" % pick)
	assert_eq(
		(pick as BuildCommand).unit_type.id,
		&"md_tank",
		"Brutal wants no capture roster, so the funds Normal spends on infantry buy armour"
	)
	assert_eq(pick.validate(state), "")


func _defends_its_hq(tier: StringName) -> bool:
	var state := Fixture.state(HQ_SIEGE)
	state.capture_progress[Vector2i(0, 0)] = 5
	var command := AIController.new(unit_db, db.by_id(tier).profile()).plan_next_command(state)
	return command is AttackCommand and (command as AttackCommand).target_cell == Vector2i(0, 0)


## What test_ai_defence.gd pins at a chosen weight, pinned here at the weights
## players actually get: the dial has to be large enough on Normal and Difficult
## to outbid an ordinary rival, because a defence that loses to any tank on the
## board is the reported defect it went live to answer. Easy declines on purpose
## — rushing its headquarters is a beginner's affordance, not an oversight.
## docs/difficulty_check.md §4c is the measured boundary, Rockets included.
func test_normal_and_difficult_defend_a_headquarters_being_taken() -> void:
	assert_true(_defends_its_hq(&"normal"), "Normal must answer a capture of its own HQ")
	assert_true(_defends_its_hq(&"hard"), "Difficult must answer it too")
	assert_false(_defends_its_hq(&"easy"), "Easy leaves its HQ open on purpose")


## Easy's timidity is mechanical, not cosmetic: over-weighting danger is what the
## ladder found actually makes this planner weak, so Easy turns the same threat
## dial Difficult uses, the opposite way.
func test_easy_is_timid_rather_than_handicapped() -> void:
	var easy := db.by_id(&"easy").profile()
	var hard := db.by_id(&"hard").profile()
	assert_gt(
		easy.threat_aversion, hard.threat_aversion, "Easy should flinch harder than Difficult"
	)
	assert_gt(
		easy.advance_threat_tiles,
		hard.advance_threat_tiles,
		"Easy should hang back further than Difficult too"
	)
	assert_gt(easy.retreat_hp, db.by_id(&"normal").profile().retreat_hp, "Easy runs home earlier")


## No tier may touch anything but the AI's judgement — no tier resource carries a
## combat, economy or vision lever, because none exists to carry (D2/D3).
func test_a_tier_is_only_a_profile_and_a_label() -> void:
	var fields: Array[String] = []
	for property in Difficulty.new().get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields.append(String(property["name"]))
	assert_eq(fields, ["id", "display_name", "ai_profile"])


func test_unknown_id_falls_back_to_normal() -> void:
	var tier := db.by_id(&"nightmare")
	assert_eq(tier.id, &"normal", "an id that is not a tier must still play")


## A tier whose profile file went missing plays with the shipped defaults rather
## than taking the AI out entirely.
func test_a_tier_without_a_profile_still_yields_one() -> void:
	var orphan := Difficulty.new()
	assert_null(orphan.ai_profile)
	assert_not_null(orphan.profile())


## Guards against inert wiring: a tier that is loaded but never reaches the
## planner would pass every test above. Easy drops md_tank from its build list,
## so with the funds for one the two tiers must buy different units.
func test_easy_reaches_a_different_command_than_normal() -> void:
	var map_text := "[terrain]\nB....\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 i 3 0\n1 i 4 0"

	var normal_state := Fixture.state(map_text)
	normal_state.funds[1] = 20000
	for unit in normal_state.units:
		unit.acted = true
	var normal_pick := AIController.new(unit_db, db.by_id(&"normal").profile()).plan_next_command(
		normal_state
	)
	assert_true(normal_pick is BuildCommand, "expected a build, got %s" % normal_pick)
	assert_eq((normal_pick as BuildCommand).unit_type.id, &"md_tank")

	var easy_state := Fixture.state(map_text)
	easy_state.funds[1] = 20000
	for unit in easy_state.units:
		unit.acted = true
	var easy_pick := AIController.new(unit_db, db.by_id(&"easy").profile()).plan_next_command(
		easy_state
	)
	assert_true(easy_pick is BuildCommand)
	assert_eq(
		(easy_pick as BuildCommand).unit_type.id,
		&"tank",
		"Easy fields no md_tank, so the same funds buy the lesser hammer"
	)
	assert_eq(easy_pick.validate(easy_state), "")


## Easy under-staffs a property race: it is satisfied with two capture units
## while Normal still buys its third.
func test_easy_stops_buying_capture_units_before_normal() -> void:
	var map_text := "[terrain]\nB...\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0"

	var easy_state := Fixture.state(map_text)
	easy_state.funds[1] = 20000
	for unit in easy_state.units:
		unit.acted = true
	var easy_pick := AIController.new(unit_db, db.by_id(&"easy").profile()).plan_next_command(
		easy_state
	)
	assert_true(easy_pick is BuildCommand)
	assert_eq((easy_pick as BuildCommand).unit_type.id, &"tank")

	var normal_state := Fixture.state(map_text)
	normal_state.funds[1] = 20000
	for unit in normal_state.units:
		unit.acted = true
	var normal_pick := AIController.new(unit_db, db.by_id(&"normal").profile()).plan_next_command(
		normal_state
	)
	assert_true(normal_pick is BuildCommand)
	assert_eq((normal_pick as BuildCommand).unit_type.id, &"infantry")
