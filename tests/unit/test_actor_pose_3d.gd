extends GutTest
## ActorPose3D: a commander figure's body language as pure functions of one
## clock. Every clip names every part, moves smoothly, and a gesture opens on
## idle's own pose so a director can cut into it without the figure popping.

const STEP := 1.0 / 60.0
## The most a part may turn, or the figure move, in one frame at 60 fps: a
## fist thrown overhead in a third of a second stays under it, a pop to a
## gesture's full offset (over two radians) is far past it.
const MAX_TURN := 0.25
const MAX_SHIFT := 0.02
const SPAN := 6.0


func _assert_same(got: Dictionary, want: Dictionary, why: String) -> void:
	for part in ActorPose3D.PARTS:
		var gap: float = (got[part] as Vector3).distance_to(want[part] as Vector3)
		assert_almost_eq(gap, 0.0, 0.0001, "%s: %s" % [why, part])


func test_every_clip_poses_every_part() -> void:
	for clip in ActorPose3D.CLIPS:
		var pose := ActorPose3D.sample(clip, 0.7)
		for part in ActorPose3D.PARTS:
			assert_true(pose.has(part), "%s has no %s" % [clip, part])
			assert_typeof(pose.get(part), TYPE_VECTOR3, "%s.%s" % [clip, part])


func test_every_clip_is_continuous() -> void:
	for clip in ActorPose3D.CLIPS:
		var worst_turn := 0.0
		var worst_shift := 0.0
		var was := ActorPose3D.sample(clip, 0.0)
		var t := STEP
		while t < SPAN:
			var now := ActorPose3D.sample(clip, t)
			for part in ActorPose3D.PARTS:
				var gap: float = (now[part] as Vector3).distance_to(was[part] as Vector3)
				if part == &"root":
					worst_shift = maxf(worst_shift, gap)
				else:
					worst_turn = maxf(worst_turn, gap)
			was = now
			t += STEP
		assert_lt(worst_turn, MAX_TURN, "%s turns a part too far in one frame" % clip)
		assert_lt(worst_shift, MAX_SHIFT, "%s moves the figure too far in one frame" % clip)


func test_loops_repeat() -> void:
	for clip in ActorPose3D.LOOPS:
		assert_true(ActorPose3D.is_loop(clip), String(clip))
		for t: float in [0.0, 0.4, 1.3, 2.9]:
			var later := ActorPose3D.sample(clip, t + ActorPose3D.LOOP_SECONDS)
			_assert_same(later, ActorPose3D.sample(clip, t), "%s at %.1f" % [clip, t])


func test_a_gesture_opens_on_idle() -> void:
	var idle := ActorPose3D.sample(&"idle", 0.0)
	for clip in ActorPose3D.GESTURES:
		assert_false(ActorPose3D.is_loop(clip), String(clip))
		_assert_same(ActorPose3D.sample(clip, 0.0), idle, String(clip))


func test_a_gesture_holds_with_some_life_in_it() -> void:
	for clip: StringName in [&"point", &"fist", &"salute", &"shrug"]:
		var a := ActorPose3D.sample(clip, 2.0)
		var b := ActorPose3D.sample(clip, 2.4)
		var moved := 0.0
		for part in ActorPose3D.PARTS:
			moved += (a[part] as Vector3).distance_to(b[part] as Vector3)
		assert_gt(moved, 0.001, "%s froze" % clip)


func test_every_clip_is_listed_once() -> void:
	var listed: Array[StringName] = []
	listed.append_array(ActorPose3D.LOOPS)
	listed.append_array(ActorPose3D.GESTURES)
	assert_eq(listed.size(), ActorPose3D.CLIPS.size())
	for clip in ActorPose3D.CLIPS:
		assert_true(listed.has(clip), String(clip))


func test_an_unknown_clip_is_idle() -> void:
	for t: float in [0.0, 1.1, 3.7]:
		var got := ActorPose3D.sample(&"moonwalk", t)
		_assert_same(got, ActorPose3D.sample(&"idle", t), "moonwalk at %.1f" % t)
	assert_false(ActorPose3D.is_loop(&"moonwalk"))
