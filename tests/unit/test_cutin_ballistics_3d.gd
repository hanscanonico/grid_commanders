extends GutTest
## CutinBallistics3D: when each round of a 3D cut-in volley leaves and lands,
## the path each kind flies and the scatter a burst throws — pure, so a volley
## posed mid-flight is the same volley every run.

const FROM := Vector3(-3.0, 0.3, 0.0)
const TO := Vector3(3.0, 0.3, 0.0)


func test_the_first_round_lands_exactly_when_the_volley_does() -> void:
	var p := CutinBallistics3D.round_progress(0.8, 0.5, 0.3, 0, 0, 0.05, false)
	assert_almost_eq(p, 1.0, 0.0001, "leaves at the fire beat, lands a flight later")
	assert_lt(CutinBallistics3D.round_progress(0.49, 0.5, 0.3, 0, 0, 0.05, false), 0.0)


func test_later_figures_and_later_rounds_leave_later() -> void:
	var first := CutinBallistics3D.round_progress(0.6, 0.5, 0.3, 0, 0, 0.05, false)
	assert_gt(first, CutinBallistics3D.round_progress(0.6, 0.5, 0.3, 2, 0, 0.05, false))
	assert_gt(first, CutinBallistics3D.round_progress(0.6, 0.5, 0.3, 0, 1, 0.05, true))
	var end := CutinBallistics3D.volley_end(0.5, 0.3, 3, 2, 0.05, true)
	assert_almost_eq(
		CutinBallistics3D.round_progress(end, 0.5, 0.3, 2, 1, 0.05, true), 1.0, 0.0001, "the last"
	)


func test_every_path_runs_from_the_barrel_to_the_target() -> void:
	for kind: StringName in BattleStyle.PROJECTILES:
		assert_true(CutinBallistics3D.path(kind, FROM, TO, 0.0, 1.0).is_equal_approx(FROM), kind)
		assert_true(CutinBallistics3D.path(kind, FROM, TO, 1.0, 1.0).is_equal_approx(TO), kind)


func test_a_lob_rises_to_its_peak_and_a_flat_round_does_not() -> void:
	var top := CutinBallistics3D.path(BattleStyle.SHELL, FROM, TO, 0.5, 2.0)
	assert_almost_eq(top.y, FROM.y + 2.0, 0.0001, "the peak at the middle")
	assert_almost_eq(
		CutinBallistics3D.path(BattleStyle.TRACER, FROM, TO, 0.5, 0.0).y, FROM.y, 0.0001
	)
	var artillery := BattleStyleDB.load_default().by_id(&"artillery")
	assert_gt(
		CutinBallistics3D.peak_of(artillery, true), CutinBallistics3D.peak_of(artillery, false)
	)


func test_a_bomb_is_tossed_then_plunges_and_a_torpedo_runs_under_the_water() -> void:
	var high := Vector3(-1.0, 2.0, 0.0)
	var toss := CutinBallistics3D.path(BattleStyle.BOMB, high, TO, CutinBallistics3D.BOMB_TOSS, 0.0)
	assert_gt(toss.y, high.y, "tossed up over the belly first")
	var mid := CutinBallistics3D.path(BattleStyle.BOMB, high, TO, 0.7, 0.0)
	var late := CutinBallistics3D.path(BattleStyle.BOMB, high, TO, 0.9, 0.0)
	assert_gt(mid.y - late.y, 0.0, "falling")
	var early_drop := toss.y - CutinBallistics3D.path(BattleStyle.BOMB, high, TO, 0.6, 0.0).y
	assert_gt(mid.y - late.y, early_drop, "faster and faster")
	var run := CutinBallistics3D.path(BattleStyle.TORPEDO, FROM, TO, 0.5, 0.0)
	assert_lt(run.y, FROM.y, "under the surface mid-run")


func test_a_heading_points_along_the_flight() -> void:
	var dir := CutinBallistics3D.heading(BattleStyle.SHELL, FROM, TO, 0.2, 2.0)
	assert_gt(dir.x, 0.0)
	assert_gt(dir.y, 0.0, "climbing early in a lob")
	assert_lt(
		CutinBallistics3D.heading(BattleStyle.SHELL, FROM, TO, 0.8, 2.0).y, 0.0, "falling late"
	)


func test_a_hit_lands_on_one_of_the_targets() -> void:
	var targets := PackedVector3Array([Vector3(3, 0.3, -0.4), Vector3(4, 0.3, 0.4)])
	for i in 20:
		var at := CutinBallistics3D.hit_point(targets, i)
		var nearest := minf(at.distance_to(targets[0]), at.distance_to(targets[1]))
		assert_lt(nearest, CutinBallistics3D.SPREAD, "round %d" % i)
		assert_eq(at, CutinBallistics3D.hit_point(targets, i), "the same round, the same spot")
	assert_eq(CutinBallistics3D.hit_point(PackedVector3Array(), 3), Vector3.ZERO)


func test_debris_and_smoke_leave_the_burst_and_come_back_down_or_rise() -> void:
	var origin := Vector3(1.0, 0.2, 0.0)
	assert_true(CutinBallistics3D.debris(origin, 3, 0.0, 1.0).is_equal_approx(origin))
	assert_gt(CutinBallistics3D.debris(origin, 3, 0.5, 1.0).y, origin.y, "thrown up")
	assert_lt(
		CutinBallistics3D.debris(origin, 3, 1.0, 1.0).y,
		CutinBallistics3D.debris(origin, 3, 0.5, 1.0).y,
		"and falling"
	)
	assert_gt(CutinBallistics3D.puff(origin, 3, 1.0, 1.0).y, origin.y, "smoke climbs")
