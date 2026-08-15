extends GutTest
## The speed tier table and the clock rate the cut-ins run on.
##
## GameSpeed is Node-free and its table is static and pure — the same terms the
## volume ladder beside it is checked on — so nothing here needs a scene, and
## nothing here writes the preference file.


func test_the_ladder_is_normal_quick_instant_gentlest_first() -> void:
	var ids: Array[StringName] = []
	for tier in GameSpeed.ordered():
		ids.append(tier.id)
	assert_eq(
		ids,
		[&"normal", &"quick", &"instant"] as Array[StringName],
		"three tiers, gentlest first — Slow was folded into Normal (COM-226)"
	)


func test_normal_is_the_default_and_carries_the_old_slow_numbers() -> void:
	var normal := GameSpeed.default_speed()
	assert_eq(normal.id, &"normal", "a fresh install plays at Normal")
	assert_eq(normal.anim_scale, 3.0, "Normal animates at what Slow used to")
	assert_eq(normal.pace_scale, 1.5, "and thinks at what Slow used to")


func test_quick_carries_the_old_normal_numbers() -> void:
	var quick := GameSpeed.by_id(&"quick")
	assert_eq(quick.anim_scale, 2.0, "Quick animates at what Normal used to")
	assert_eq(quick.pace_scale, 1.0, "and thinks at what Normal used to")


func test_a_stored_slow_preference_resolves_to_normal() -> void:
	assert_false(GameSpeed.has_id(&"slow"), "Slow is gone from the table")
	assert_eq(
		GameSpeed.by_id(&"slow").id,
		&"normal",
		"and an older install's stored preference lands on the tier holding its numbers"
	)


func test_cycling_wraps_through_every_tier() -> void:
	var id: StringName = GameSpeed.DEFAULT_ID
	var walked: Array[StringName] = []
	for _i in GameSpeed.ordered().size():
		walked.append(id)
		id = GameSpeed.next(id).id
	assert_eq(walked.size(), GameSpeed.ordered().size(), "the walk visits every tier once")
	assert_eq(id, GameSpeed.DEFAULT_ID, "and comes back round to where it started")


func test_the_cut_in_clock_runs_at_the_authored_pace_on_the_default_tier() -> void:
	assert_eq(
		GameSpeed.default_speed().cutscene_rate(),
		1.0,
		"beat sheets are written in the default tier's seconds"
	)


func test_a_brisker_tier_runs_the_cut_in_clock_faster() -> void:
	assert_almost_eq(
		GameSpeed.by_id(&"quick").cutscene_rate(), 1.5, 0.001, "Quick, half again as fast"
	)


func test_instant_answers_a_rate_rather_than_dividing_by_its_zero_scale() -> void:
	var instant := GameSpeed.by_id(&"instant")
	assert_true(instant.instant, "Instant is still an explicit branch")
	assert_eq(instant.cutscene_rate(), 1.0, "and never reaches a cut-in to scale one")
