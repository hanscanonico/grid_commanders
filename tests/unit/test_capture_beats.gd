extends GutTest
## The capture cut-in's beat sheet — where the mashes and the flip land on the
## clock, and the chips each mash knocks off the meter.
##
## In scope despite living beside the cut-in: CaptureBeats is a RefCounted with no
## `Node` in it and `plan` is a pure function of a CaptureResult and one float, on
## the terms CombatBeats already earns in docs/testing_exceptions.md. Both the flat
## cut-in and the 3D stage read it, so a drift here moves both at once.

const SLOP := 0.0001


func _result(before: int, after: int, captured: bool) -> CaptureCommand.CaptureResult:
	var result := CaptureCommand.CaptureResult.new()
	result.points_before = before
	result.points_after = after
	result.captured = captured
	return result


func _sum(chips: PackedInt32Array) -> int:
	var total := 0
	for chip in chips:
		total += chip
	return total


# --- chips --------------------------------------------------------------------


func test_split_is_largest_first_and_sums_to_the_drop() -> void:
	assert_eq(CaptureBeats.split(10, 3), PackedInt32Array([4, 3, 3]))
	assert_eq(CaptureBeats.split(12, 3), PackedInt32Array([4, 4, 4]))
	assert_eq(CaptureBeats.split(1, 1), PackedInt32Array([1]))
	assert_eq(CaptureBeats.split(2, 2), PackedInt32Array([1, 1]))


func test_plan_caps_the_mashes_at_three() -> void:
	var beats := CaptureBeats.plan(_result(20, 8, false), 1.0)
	assert_eq(beats.hops.size(), CaptureBeats.MAX_HOPS)
	assert_eq(_sum(beats.chips), 12, "the chips are the committed delta")


func test_a_small_drop_mashes_once_per_point() -> void:
	var beats := CaptureBeats.plan(_result(2, 0, true), 1.0)
	assert_eq(beats.hops.size(), 2)
	assert_eq(beats.chips, PackedInt32Array([1, 1]))


func test_a_zero_drop_still_mashes_once_for_nothing() -> void:
	var beats := CaptureBeats.plan(_result(20, 20, false), 1.0)
	assert_eq(beats.hops.size(), 1)
	assert_eq(beats.chips, PackedInt32Array([0]))


# --- windows ------------------------------------------------------------------


func test_the_mashes_follow_the_march_end_to_end() -> void:
	var beats := CaptureBeats.plan(_result(20, 10, false), 1.0)
	assert_almost_eq(beats.hops[0].x, beats.march.y, SLOP)
	for i in beats.hops.size():
		assert_almost_eq(beats.lands[i], beats.hops[i].y, SLOP, "hop %d lands at its end" % i)
		if i > 0:
			assert_almost_eq(beats.hops[i].x - beats.hops[i - 1].y, CaptureBeats.HOP_GAP, SLOP)


func test_a_partial_has_no_flip() -> void:
	var beats := CaptureBeats.plan(_result(20, 10, false), 1.0)
	assert_eq(beats.flip, Vector2.ZERO)
	assert_almost_eq(beats.banner.x, beats.lands[beats.lands.size() - 1] + 0.05, SLOP)


func test_a_completion_flips_before_its_banner() -> void:
	var beats := CaptureBeats.plan(_result(10, 0, true), 1.0)
	assert_gt(beats.flip.y, beats.flip.x)
	assert_gt(beats.banner.x, beats.flip.x)
	assert_lt(beats.banner.x, beats.flip.y, "the banner opens mid-flip")


func test_the_budgets_hold_the_two_tempos() -> void:
	var complete := CaptureBeats.plan(_result(10, 0, true), 1.0)
	var partial := CaptureBeats.plan(_result(20, 10, false), 1.0)
	assert_almost_eq(complete.total, 2.46, 0.02, "a completing capture runs ~2.4 s")
	assert_almost_eq(partial.total, 2.34, 0.02, "three mashes, no flip")
	assert_almost_eq(complete.total, complete.wipe_out.y, SLOP)


func test_the_tail_trims_only_the_hold_and_wipe() -> void:
	var full := CaptureBeats.plan(_result(10, 0, true), 1.0)
	var cut := CaptureBeats.plan(_result(10, 0, true), 0.0)
	assert_eq(cut.lands, full.lands)
	assert_eq(cut.flip, full.flip)
	assert_eq(cut.banner, full.banner)
	assert_almost_eq(cut.wipe_out.x, full.banner.y, SLOP, "no hold left")
	assert_almost_eq(
		cut.wipe_out.y - cut.wipe_out.x,
		CaptureBeats.WIPE_OUT * CaptureBeats.MIN_WIPE_SCALE,
		SLOP,
		"the wipe keeps its floor"
	)


# --- the meter ----------------------------------------------------------------


func test_the_meter_drops_a_chip_as_each_mash_lands() -> void:
	var beats := CaptureBeats.plan(_result(20, 10, false), 1.0)
	assert_eq(beats.points_at(20, 0.0), 20)
	assert_eq(beats.points_at(20, beats.lands[0] - 0.001), 20)
	assert_eq(beats.points_at(20, beats.lands[0]), 16)
	assert_eq(beats.points_at(20, beats.lands[1]), 13)
	assert_eq(beats.points_at(20, beats.total), 10, "the meter ends on points_after")
