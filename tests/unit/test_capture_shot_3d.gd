extends GutTest
## The 3D capture cut-in's arithmetic: when the stage holds the lens, how the two
## flags run, when the building flips, and where the lens and the confetti are.
##
## In scope despite living under `scenes/`: CaptureShot3D is a RefCounted of
## statics over a `CaptureBeats` sheet and a time, the terms CinemaShot3D earns in
## docs/testing_exceptions.md. Every rule here is one a posed still cannot show:
## that a skip lands the stage off the air, that a partial never lowers the
## owner's flag, that the two flags are never both up at once.

const SLOP := 0.0001
const SQUAD := Vector3(-1.0, 0.25, 0.0)
const DOOR := Vector3(2.0, 0.0, -2.0)
const TOP := Vector3(3.0, 3.0, -1.5)


func _beats(captured: bool) -> CaptureBeats:
	var result := CaptureCommand.CaptureResult.new()
	result.points_before = 8 if captured else 20
	result.points_after = 0 if captured else 10
	result.captured = captured
	return CaptureBeats.plan(result, 1.0)


func test_the_stage_holds_the_lens_between_the_two_wipes() -> void:
	var beats := _beats(true)
	assert_false(CaptureShot3D.on_air(beats, 0.0), "the board, as the bars close")
	assert_true(CaptureShot3D.on_air(beats, CaptureShot3D.cut_in()))
	assert_true(CaptureShot3D.on_air(beats, beats.banner.y))
	assert_false(CaptureShot3D.on_air(beats, beats.total), "a skip lands on the board")
	assert_gt(CaptureShot3D.cut_in(), 0.0)
	assert_lte(CaptureShot3D.cut_in(), CaptureBeats.WIPE_IN, "the bars are shut first")
	assert_gt(CaptureShot3D.cut_out(beats), beats.wipe_out.x)
	assert_lt(CaptureShot3D.cut_out(beats), beats.wipe_out.y)


func test_each_cut_is_under_a_flash() -> void:
	var beats := _beats(false)
	assert_almost_eq(CaptureShot3D.flash(beats, false, CaptureShot3D.cut_in()), 1.0, SLOP)
	assert_almost_eq(CaptureShot3D.flash(beats, false, CaptureShot3D.cut_out(beats)), 1.0, SLOP)
	assert_almost_eq(CaptureShot3D.flash(beats, false, beats.march.y), 0.0, SLOP)


func test_the_flip_blooms_at_its_peak_and_only_on_a_completion() -> void:
	var done := _beats(true)
	assert_almost_eq(CaptureShot3D.bloom(done, true, CaptureShot3D.flip_at(done)), 1.0, SLOP)
	assert_gt(CaptureShot3D.flash(done, true, CaptureShot3D.flip_at(done)), 0.0, "a softer wash")
	assert_false(CaptureShot3D.flipped(done, true, CaptureShot3D.flip_at(done) - 0.01))
	assert_true(CaptureShot3D.flipped(done, true, CaptureShot3D.flip_at(done)))
	var partial := _beats(false)
	assert_false(CaptureShot3D.flipped(partial, false, partial.total))
	assert_almost_eq(CaptureShot3D.bloom(partial, false, partial.banner.x), 0.0, SLOP)


func test_the_flags_swap_and_are_never_both_up() -> void:
	var beats := _beats(true)
	assert_almost_eq(CaptureShot3D.old_flag(beats, true, 0.0), 1.0, SLOP)
	assert_almost_eq(CaptureShot3D.new_flag(beats, true, 0.0), 0.0, SLOP)
	assert_almost_eq(CaptureShot3D.old_flag(beats, true, CaptureShot3D.flip_at(beats)), 0.0, SLOP)
	assert_almost_eq(CaptureShot3D.new_flag(beats, true, beats.total), 1.0, SLOP)
	var t := 0.0
	while t <= beats.total:
		var both := (
			CaptureShot3D.old_flag(beats, true, t) > 0.0
			and CaptureShot3D.new_flag(beats, true, t) > 0.0
		)
		assert_false(both, "both flags up at %.2f" % t)
		t += 0.01


func test_a_partial_leaves_the_owner_flying() -> void:
	var beats := _beats(false)
	assert_almost_eq(CaptureShot3D.old_flag(beats, false, beats.total), 1.0, SLOP)
	assert_almost_eq(CaptureShot3D.new_flag(beats, false, beats.total), 0.0, SLOP)
	assert_almost_eq(CaptureShot3D.cheer(beats, false, beats.total - 0.3), 0.0, SLOP)
	assert_almost_eq(CaptureShot3D.confetti_life(beats, false, beats.banner.x + 0.2), 0.0, SLOP)


func test_the_squad_hops_on_each_mash_and_lands_on_its_beat() -> void:
	var beats := _beats(true)
	for span in beats.hops:
		var middle := (span.x + span.y) * 0.5
		assert_almost_eq(CaptureShot3D.hop(beats, middle), CaptureShot3D.HOP_HEIGHT, SLOP)
		assert_almost_eq(CaptureShot3D.hop(beats, span.y), 0.0, SLOP)
		assert_almost_eq(CaptureShot3D.jolt(beats, span.y), 1.0, SLOP, "the landing jolts")


func test_the_building_rests_at_its_own_size_outside_the_beats() -> void:
	var beats := _beats(true)
	assert_eq(CaptureShot3D.building_scale(beats, true, 0.0), Vector3.ONE)
	assert_eq(CaptureShot3D.building_scale(beats, true, beats.total), Vector3.ONE)


func test_the_confetti_is_the_same_every_run_and_rises_first() -> void:
	for i in CaptureShot3D.CONFETTI:
		var early := CaptureShot3D.confetti_offset(i, 0.2)
		assert_eq(early, CaptureShot3D.confetti_offset(i, 0.2), "piece %d is hashed" % i)
		assert_gt(early.y, 0.0, "piece %d is thrown up" % i)
	assert_ne(CaptureShot3D.confetti_offset(0, 0.3), CaptureShot3D.confetti_offset(1, 0.3))


func test_the_lens_looks_at_the_set_from_above_its_ground() -> void:
	for captured in [true, false]:
		var beats := _beats(captured)
		var t := CaptureShot3D.cut_in()
		while t < CaptureShot3D.cut_out(beats):
			var lens := CaptureShot3D.lens(beats, captured, t, SQUAD, SQUAD, DOOR, TOP)
			assert_gt(lens[0].y, 0.1, "the lens stays off the ground at %.2f" % t)
			assert_gt(lens[0].z, lens[1].z, "the lens looks into the set at %.2f" % t)
			t += 0.05
