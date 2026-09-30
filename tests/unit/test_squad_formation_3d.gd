extends GutTest
## SquadFormation3D: where a 3D cut-in squad's figures stand and how they move,
## as arithmetic of the pose fields a director sets off its clock — so a still
## posed at any moment is the same still every run.


func test_a_squad_is_centred_on_its_anchor_whatever_its_size() -> void:
	assert_eq(SquadFormation3D.slot_point(0, 1, 1.0, 1.0).x, 0.0, "a lone figure stands on it")
	var first := SquadFormation3D.slot_point(0, 5, 1.2, 1.0)
	var last := SquadFormation3D.slot_point(4, 5, 1.2, 1.0)
	assert_almost_eq(first.x, -last.x, 0.0001, "five span it evenly")
	assert_lt(first.x, last.x, "the outermost first, the foremost last")


func test_spread_staggers_the_squad_in_depth_or_lines_it_up() -> void:
	var depths := {}
	for slot in 5:
		depths[SquadFormation3D.slot_point(slot, 5, 1.0, 1.0).z] = true
		assert_eq(SquadFormation3D.slot_point(slot, 5, 1.0, 0.0).z, 0.0, "a deck lines it up")
	assert_gt(depths.size(), 2, "a cluster, not a rank")


func test_a_foot_rank_sets_off_in_order_and_lands_together() -> void:
	assert_gt(
		SquadFormation3D.march_progress(0.5, 0, true),
		SquadFormation3D.march_progress(0.5, 4, true),
		"the last man is behind mid-way"
	)
	for slot in 5:
		assert_eq(SquadFormation3D.march_progress(1.0, slot, true), 1.0, "all home at the end")
	assert_eq(SquadFormation3D.march_progress(0.5, 4, false), 0.5, "a hull arrives as one")


func test_an_entrance_starts_outward_and_ends_exactly_on_the_slot() -> void:
	var reach := SquadFormation3D.arrive_reach(UnitType.LAND)
	var start := SquadFormation3D.arrive_offset(0.0, reach, UnitType.LAND, false)
	assert_almost_eq(start.x, -reach, 0.0001, "the whole run out, away from the foe")
	assert_eq(SquadFormation3D.arrive_offset(1.0, reach, UnitType.LAND, false), Vector3.ZERO)
	assert_gt(
		SquadFormation3D.arrive_reach(UnitType.AIR), reach, "an aircraft sweeps in from further"
	)
	assert_gt(
		SquadFormation3D.arrive_offset(0.2, reach, UnitType.AIR, false).y, 0.0, "descending in"
	)


func test_the_kick_waits_for_the_shot_and_settles_back() -> void:
	assert_eq(SquadFormation3D.kick(0.0, 1.0), 0.0, "nothing before the round leaves")
	assert_lt(SquadFormation3D.kick(SquadFormation3D.KICK_SNAP, 1.0), 0.0, "thrown back")
	assert_eq(SquadFormation3D.kick(2.0, 1.0), 0.0, "home again")
	assert_eq(SquadFormation3D.kick(0.02, 0.0), 0.0, "a weapon that earns no recoil")
	assert_gt(
		SquadFormation3D.kick(0.03, 0.5), SquadFormation3D.kick(0.03, 1.0), "a machine gun twitches"
	)


func test_a_howitzer_raises_its_nose_and_a_bomber_drops_its() -> void:
	assert_gt(SquadFormation3D.aim_pitch(1.0, -0.06), 0.0, "barrel up")
	assert_lt(SquadFormation3D.aim_pitch(1.0, 0.06), 0.0, "nose down into the run")
	assert_eq(SquadFormation3D.aim_pitch(0.0, -0.06), 0.0, "not before the wind-up")
	assert_lte(absf(SquadFormation3D.aim_pitch(1.0, 5.0)), SquadFormation3D.AIM_PITCH_MAX)


func test_survivors_never_fall_and_the_lost_go_down_one_after_another() -> void:
	for slot in 3:
		assert_eq(SquadFormation3D.casualty_run(0.7, slot, 3, 5), 0.0, "slot %d stands" % slot)
	var first := SquadFormation3D.casualty_run(0.3, 3, 3, 5)
	var second := SquadFormation3D.casualty_run(0.3, 4, 3, 5)
	assert_gt(first, second, "the nearest goes first")
	assert_eq(SquadFormation3D.casualty_run(1.0, 4, 3, 5), 1.0, "every fall finishes in the window")


func test_a_casualty_is_knocked_back_then_falls_and_fades() -> void:
	for domain: StringName in [UnitType.LAND, UnitType.AIR, UnitType.SEA]:
		var still := SquadFormation3D.topple(0.0, domain)
		assert_eq(still, Vector4(0.0, 0.0, 0.0, 1.0), "%s untouched before its run" % domain)
		var knocked := SquadFormation3D.topple(SquadFormation3D.KNOCK_SHARE * 0.5, domain)
		assert_gt(knocked.x, 0.0, "%s thrown back first" % domain)
		var gone := SquadFormation3D.topple(1.0, domain)
		assert_eq(gone.w, 0.0, "%s gone by the end" % domain)
		assert_gt(gone.y, 0.0, "%s dropped" % domain)
	assert_gt(
		SquadFormation3D.topple(1.0, UnitType.AIR).y,
		SquadFormation3D.topple(1.0, UnitType.LAND).y,
		"an aircraft falls out of the sky"
	)


func test_the_hover_and_the_swell_are_functions_of_the_clock() -> void:
	assert_eq(SquadFormation3D.cruise_height(1.3, 2), SquadFormation3D.cruise_height(1.3, 2))
	assert_ne(
		SquadFormation3D.cruise_height(1.3, 1),
		SquadFormation3D.cruise_height(1.3, 2),
		"a flight does not bob in unison"
	)
	assert_eq(SquadFormation3D.attitude(UnitType.LAND, 1.0, 0, 1.0), Vector2.ZERO)
	assert_ne(SquadFormation3D.attitude(UnitType.SEA, 1.0, 0, 1.0), Vector2.ZERO, "a hull rolls")


func test_scatter_is_a_stable_number_in_the_unit_interval() -> void:
	for i in 50:
		var value := SquadFormation3D.scatter(i, 7)
		assert_true(value >= 0.0 and value < 1.0)
		assert_eq(value, SquadFormation3D.scatter(i, 7))
