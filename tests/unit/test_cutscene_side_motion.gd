extends GutTest
## The cut-in squad's motion: the roll-in, the wind-up pose, the scuff and the
## casualty's knock-back, all as pure functions of the pose scalars CombatBeats
## sizes and CombatCutscene writes.
##
## Outside core/ and ai/ on the same terms PathArrow.segments and
## CaptureBackdrop.light_shaft_wedge already earn: these are static arithmetic on
## a scalar and a figure index, with no Node, no clock and no state, so the shape
## the frame is drawn from is checkable without staging a cut-in
## (docs/testing_exceptions.md carries the entry).
##
## The load-bearing assertion is `arrive_offset(1.0, ...) == Vector2.ZERO`: every
## posed smoke frame sits after the arrive beat has closed, so a posted squad an
## eighth of a pixel off its slot moves a dozen baselines for nothing.

const LAND := UnitType.LAND
const AIR := UnitType.AIR
const SEA := UnitType.SEA
## An arbitrary clock, so the sea's swell and the trudge are read off a phase
## that is neither zero nor a multiple of anything.
const CLOCK := 0.37


func _domains() -> Array[StringName]:
	return [LAND, AIR, SEA] as Array[StringName]


func _offset(p: float, slot: int = 0, domain: StringName = LAND, foot: bool = true) -> Vector2:
	return CutsceneSide.arrive_offset(p, 1.0, domain, slot, CLOCK, foot)


func test_a_squad_starts_its_roll_in_outward_of_its_slot() -> void:
	# Positive x points at the seam, so a squad still arriving is at negative x.
	assert_lt(_offset(0.0).x, -20.0)


func test_a_posted_squad_is_exactly_where_it_was_before_the_arrive_beat() -> void:
	for domain in _domains():
		for slot in CutsceneSide.MAX_FIGURES:
			for foot in [true, false]:
				assert_eq(
					CutsceneSide.arrive_offset(1.0, 1.0, domain, slot, CLOCK, foot),
					Vector2.ZERO,
					"%s slot %d (foot %s) is not posted at exactly zero" % [domain, slot, foot]
				)


func test_the_roll_in_closes_monotonically_until_the_settle() -> void:
	var previous := absf(_offset(0.0, 0, LAND, false).x)
	var steps := int((1.0 - CutsceneSide.SETTLE_BAND) * 100.0)
	for i in range(1, steps + 1):
		var at := i * 0.01
		var reach := absf(_offset(at, 0, LAND, false).x)
		assert_lt(reach, previous, "the roll-in stalled or grew again at %f" % at)
		previous = reach


func test_the_settle_carries_the_squad_past_its_slot_and_back() -> void:
	# Inside the declared band the offset crosses zero — the halt has weight.
	var dip := _offset(1.0 - CutsceneSide.SETTLE_BAND * 0.5, 0, LAND, false)
	assert_almost_eq(dip.x, CutsceneSide.SETTLE_PX, 0.2)


func test_a_marching_rank_arrives_raggedly_and_still_lands_together() -> void:
	var front := _offset(0.5, 0)
	var back := _offset(0.5, 4)
	assert_lt(back.x, front.x, "the rear figure should still be further out at half-way")
	assert_eq(_offset(1.0, 0), Vector2.ZERO)
	assert_eq(_offset(1.0, 4), Vector2.ZERO)


func test_a_hull_arrives_as_one_block() -> void:
	assert_eq(_offset(0.5, 0, LAND, false).x, _offset(0.5, 4, LAND, false).x)


func test_only_a_marching_rank_trudges() -> void:
	assert_ne(_offset(0.3, 0, LAND, true).y, 0.0)
	assert_eq(_offset(0.3, 0, LAND, false).y, 0.0)


func test_an_aircraft_banks_with_height_and_never_with_rotation() -> void:
	# The bank is a vertical offset only: these are three-quarter-view cells, and
	# rolling one reads as a rendering fault (plan R3).
	assert_lt(_offset(0.0, 0, AIR, false).y, 0.0)
	assert_eq(_offset(1.0, 0, AIR, false).y, 0.0)


func test_a_hull_rides_a_swell_no_wider_than_its_own_amplitude() -> void:
	for i in 20:
		assert_lte(absf(_offset(i * 0.05, 0, SEA, false).y), CutsceneSide.SWELL_PX)


func test_the_wind_up_pose_is_nothing_until_the_beat_opens() -> void:
	assert_eq(CutsceneSide.aim_offset(0.0, 6.0), Vector2.ZERO)
	assert_eq(CutsceneSide.aim_tilt(0.0, -0.06), 0.0)


func test_a_style_that_neither_lifts_nor_tips_holds_its_posted_pose() -> void:
	assert_eq(CutsceneSide.aim_offset(1.0, 0.0), Vector2.ZERO)
	assert_eq(CutsceneSide.aim_tilt(1.0, 0.0), 0.0)


func test_the_weapon_rises_and_drifts_off_the_seam() -> void:
	var held := CutsceneSide.aim_offset(1.0, 6.0)
	assert_almost_eq(held.y, -6.0, 0.001)
	assert_almost_eq(held.x, -6.0 * CutsceneSide.AIM_DRIFT, 0.001)


func test_the_wind_up_is_held_once_it_has_eased_out() -> void:
	assert_eq(
		CutsceneSide.aim_offset(CutsceneSide.AIM_EASE, 4.0), CutsceneSide.aim_offset(1.0, 4.0)
	)
	assert_eq(
		CutsceneSide.aim_tilt(CutsceneSide.AIM_EASE, -0.05), CutsceneSide.aim_tilt(1.0, -0.05)
	)


func test_a_pitch_past_the_cap_is_a_data_error_rather_than_a_pose() -> void:
	assert_almost_eq(CutsceneSide.aim_tilt(1.0, 0.9), CutsceneSide.AIM_PITCH_MAX, 0.0001)
	assert_almost_eq(CutsceneSide.aim_tilt(1.0, -0.9), -CutsceneSide.AIM_PITCH_MAX, 0.0001)


## Shoelace area. A polygon whose points land on one float triangulates to
## nothing and the frame logs an error, which is what MIN_FLARE_REACH is for.
func _area(points: PackedVector2Array) -> float:
	var sum := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


func test_every_scuff_puff_is_a_polygon_the_triangulator_accepts() -> void:
	for i in 101:
		var at := i * 0.01
		for outward in [1.0, -1.0]:
			for index in CutsceneSide.SCUFF_PUFFS:
				var puff := CutsceneSide.scuff_polygon(Vector2(40.0, 90.0), outward, at, index)
				assert_gt(_area(puff), 0.5, "scuff %d is degenerate at %f" % [index, at])


func test_the_scuff_steps_outward_puff_by_puff() -> void:
	var near := CutsceneSide.scuff_polygon(Vector2.ZERO, 1.0, 0.5, 0)
	var far := CutsceneSide.scuff_polygon(Vector2.ZERO, 1.0, 0.5, 2)
	assert_gt(far[0].x, near[0].x)


func test_a_casualty_is_knocked_back_before_it_tips() -> void:
	var knock := 0.2
	assert_eq(CutsceneSide.topple_fall(knock * 0.5, knock), 0.0)
	assert_gt(CutsceneSide.topple_jerk(knock * 0.5, knock), 0.9)
	assert_eq(CutsceneSide.topple_jerk(knock, knock), 0.0, "the jerk is over once the fall starts")
	assert_almost_eq(CutsceneSide.topple_fall(1.0, knock), 1.0, 0.0001)


func test_a_standing_figure_is_neither_knocked_nor_falling() -> void:
	assert_eq(CutsceneSide.topple_fall(0.0, 0.2), 0.0)
	assert_eq(CutsceneSide.topple_jerk(0.0, 0.2), 0.0)


## The defence row's one decision: the tile keeps its own stars, so the word is
## what tells a player the unit standing over them is not getting any. A bare
## zero beside MOUNTAIN would trade one misread for another.
func test_the_defence_row_qualifies_stars_the_unit_does_not_get() -> void:
	assert_eq(CutsceneSide.terrain_note(0, 4), CutsceneSide.NO_COVER_NOTE, "a flier over a peak")
	assert_eq(CutsceneSide.terrain_note(4, 4), "", "a footsoldier on the same peak")
	assert_eq(CutsceneSide.terrain_note(0, 0), "", "bare ground gives everyone nothing")
