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


func test_a_longer_beat_holds_the_speech_card_longer() -> void:
	var normal := GameSpeed.default_speed()
	assert_gt(
		normal.speech_seconds(160),
		normal.speech_seconds(20),
		"two generals arguing get more time than a five-word order"
	)
	assert_gte(
		normal.speech_seconds(1),
		normal.power_banner_seconds(),
		"and the shortest order still holds at least the power card's beat"
	)
	assert_gt(
		normal.speech_seconds(160),
		normal.power_banner_seconds(),
		"which a beat with words in it clears outright"
	)


func test_the_speech_card_reads_at_one_speed_on_every_playing_tier() -> void:
	assert_eq(
		GameSpeed.by_id(&"quick").speech_seconds(120),
		GameSpeed.default_speed().speech_seconds(120),
		"words are information, so only Instant tightens them"
	)


func test_a_long_exchange_cannot_park_the_board() -> void:
	assert_eq(
		GameSpeed.default_speed().speech_seconds(100000),
		GameSpeed.SPEECH_MAX_SECONDS,
		"capped; a reader who is done presses on"
	)


func test_instant_tightens_the_speech_card_like_a_banner() -> void:
	assert_eq(
		GameSpeed.by_id(&"instant").speech_seconds(400),
		GameSpeed.INSTANT_BANNER_SECONDS,
		"the tier that shows results rather than playing them out"
	)


func test_the_board_moments_scale_with_the_tier_they_are_played_at() -> void:
	var normal := GameSpeed.default_speed()
	var quick := GameSpeed.by_id(&"quick")
	assert_almost_eq(
		normal.build_rise_seconds(),
		GameSpeed.BASE_BUILD_RISE_SECONDS * 3.0,
		0.001,
		"a built unit rises over the gentlest tier's own scale"
	)
	assert_almost_eq(
		normal.flag_flip_seconds(),
		GameSpeed.BASE_FLAG_FLIP_SECONDS * 3.0,
		0.001,
		"and a pennant flashes on it too"
	)
	assert_lt(
		quick.build_rise_seconds(), normal.build_rise_seconds(), "a brisker tier plays both shorter"
	)
	assert_lt(quick.flag_flip_seconds(), normal.flag_flip_seconds(), "by the same scale")


func test_the_board_moments_are_shorter_than_a_death() -> void:
	var normal := GameSpeed.default_speed()
	assert_lt(
		normal.build_rise_seconds(),
		normal.death_fade_seconds(),
		"a badge arriving is not a hit landing"
	)
	assert_lt(normal.flag_flip_seconds(), normal.death_fade_seconds(), "nor is a flag catching one")


func test_instant_leaves_the_board_moments_nothing_to_play() -> void:
	var instant := GameSpeed.by_id(&"instant")
	assert_eq(instant.build_rise_seconds(), 0.0, "a zero-length rise is skipped outright")
	assert_eq(instant.flag_flip_seconds(), 0.0, "and so is the flip flash")
