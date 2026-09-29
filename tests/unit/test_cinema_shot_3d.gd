extends GutTest
## CinemaShot3D and CinemaPose3D: where the 3D board's story scenes stand the
## lens for each shot, and how it moves between them. Pure arithmetic over four
## numbers a pose, so every framing rule is checked without a scene.

const POST := Vector3(4.5, 0.0, 6.5)
const EYES := 0.5


func _assert_same_pose(got: CinemaPose3D, want: CinemaPose3D, why: String) -> void:
	assert_almost_eq(got.target.distance_to(want.target), 0.0, 0.0001, why + ": target")
	assert_almost_eq(got.reach, want.reach, 0.0001, why + ": reach")
	assert_almost_eq(angle_difference(got.yaw, want.yaw), 0.0, 0.0001, why + ": yaw")
	assert_almost_eq(got.pitch, want.pitch, 0.0001, why + ": pitch")


## Where `point` sits across the frame of `pose`: negative left of the middle.
func _across(pose: CinemaPose3D, point: Vector3) -> float:
	return (point - pose.target).dot(pose.across())


func test_a_shot_opens_on_its_start_and_settles_on_its_end() -> void:
	var shot := CinemaShot3D.actor(POST, EYES, 0.0, 1, false)
	_assert_same_pose(shot.pose_at(0.0), shot.start, "the first frame")
	_assert_same_pose(shot.pose_at(shot.drift_seconds * 12.0), shot.end, "long after")


## An untimed line holds for as long as the player reads, so the drift must
## still be moving — slowly — well past its settling time, never stopped dead.
func test_the_drift_keeps_moving_while_a_line_is_held() -> void:
	var shot := CinemaShot3D.actor(POST, EYES, 0.0, 1, false)
	var later := shot.pose_at(shot.drift_seconds * 2.0)
	var much_later := shot.pose_at(shot.drift_seconds * 3.0)
	assert_gt(later.reach - much_later.reach, 0.0, "still pushing in")
	assert_gt(later.reach, shot.end.reach, "and not yet arrived")


func test_a_glide_runs_from_one_pose_to_the_next() -> void:
	var from := CinemaPose3D.new(Vector3(1, 0, 1), 20.0, 0.0, 0.9)
	var to := CinemaPose3D.new(Vector3(15, 0, 9), 7.0, 0.5, 0.3)
	_assert_same_pose(CinemaPose3D.glide(from, to, 0.0, 0.12), from, "the glide's start")
	_assert_same_pose(CinemaPose3D.glide(from, to, 1.0, 0.12), to, "the glide's end")


## A flight across the board pulls back in the middle, on a crane's arc; a
## move that goes nowhere has nothing to fly over and does not.
func test_a_long_glide_cranes_up_and_a_short_one_does_not() -> void:
	var from := CinemaPose3D.new(Vector3(1, 0, 1), 7.0, 0.0, 0.3)
	var far := CinemaPose3D.new(Vector3(21, 0, 1), 7.0, 0.0, 0.3)
	var here := CinemaPose3D.new(Vector3(1, 0, 1), 7.0, 0.4, 0.3)
	assert_gt(CinemaPose3D.glide(from, far, 0.5, 0.12).reach, 7.0 + 2.0, "the arc over 20 cells")
	assert_almost_eq(CinemaPose3D.glide(from, here, 0.5, 0.12).reach, 7.0, 0.0001)


## Two voices trade sides like a shot and its reverse: each stands on the third
## of the frame its side names, the other third left open — in the medium shot
## a speaker is introduced in and in the closer one after it.
func test_an_actor_shot_stands_its_speaker_on_the_named_third() -> void:
	for near: bool in [false, true]:
		for side: int in [1, -1]:
			var shot := CinemaShot3D.actor(POST, EYES, 0.0, side, near)
			for pose: CinemaPose3D in [shot.start, shot.end]:
				var where := _across(pose, POST)
				assert_true(where * side < 0.0, "side %d puts the speaker on its third" % side)


func test_an_actor_shot_pushes_in_and_looks_at_the_face() -> void:
	var shot := CinemaShot3D.actor(POST, EYES, 0.0, 1, false)
	assert_lt(shot.end.reach, shot.start.reach)
	assert_lt(shot.end.pitch, shot.start.pitch)
	assert_almost_eq(shot.start.target.y, EYES * CinemaShot3D.LOOK_AT_EYES, 0.0001)


func test_the_closer_shot_is_closer() -> void:
	var medium := CinemaShot3D.actor(POST, EYES, 0.0, 1, false)
	var near := CinemaShot3D.actor(POST, EYES, 0.0, 1, true)
	assert_lt(near.start.reach, medium.start.reach)
	assert_lt(near.end.reach, medium.end.reach)


## The open third looks into the board, whichever side of it the camera is on.
func test_a_speaker_faces_into_the_board() -> void:
	var middle := Vector2(10, 7)
	var west := Vector3(1.5, 0, 7.5)
	var east := Vector3(18.5, 0, 7.5)
	assert_eq(CinemaShot3D.side_facing(west, middle, 0.0, -1), 1, "the board is to the right")
	assert_eq(CinemaShot3D.side_facing(east, middle, 0.0, 1), -1, "the board is to the left")
	assert_eq(CinemaShot3D.side_facing(west, middle, PI, -1), -1, "seen from the far side")
	var ahead := Vector3(10, 0, 1.5)
	assert_eq(CinemaShot3D.side_facing(ahead, middle, 0.0, -1), -1, "no side: the fallback")


func test_the_establishing_shot_takes_in_boards_of_every_size_within_bounds() -> void:
	assert_eq(CinemaShot3D.board_reach(Vector2i(4, 3)), CinemaShot3D.WIDE_REACH_MIN)
	assert_eq(CinemaShot3D.board_reach(Vector2i(200, 150)), CinemaShot3D.WIDE_REACH_MAX)
	var small := CinemaShot3D.board_reach(Vector2i(16, 10))
	var large := CinemaShot3D.board_reach(Vector2i(30, 20))
	assert_gt(large, small, "a bigger board stands the lens further back")
	var wide := CinemaShot3D.wide(POST, 20.0, 0.0)
	assert_gt(wide.start.pitch, wide.end.pitch, "it cranes down")
	assert_almost_eq(wide.end.reach, 20.0, 0.0001)


func test_a_subject_shot_backs_off_to_take_in_all_of_it() -> void:
	var one: Array[Vector2i] = [Vector2i(5, 5)]
	var spread: Array[Vector2i] = [Vector2i(2, 5), Vector2i(9, 5)]
	var huge: Array[Vector2i] = [Vector2i(0, 0), Vector2i(90, 60)]
	assert_almost_eq(CinemaShot3D.subject_reach(one), CinemaShot3D.SUBJECT_REACH_BASE, 0.0001)
	assert_gt(CinemaShot3D.subject_reach(spread), CinemaShot3D.subject_reach(one))
	assert_eq(CinemaShot3D.subject_reach(huge), CinemaShot3D.SUBJECT_REACH_MAX)
	assert_eq(CinemaShot3D.middle_of(spread), Vector2(6.0, 5.5))


## The limit break's orbit starts low at the general's boots on one side and
## climbs and pulls back round to the other, taking in the pillar.
func test_the_power_orbits_up_and_out_round_the_general() -> void:
	var shot := CinemaShot3D.limit(POST, EYES, 0.0)
	assert_gt(shot.end.reach, shot.start.reach, "it pulls back")
	assert_gt(shot.end.pitch, shot.start.pitch, "and climbs")
	assert_gt(absf(angle_difference(shot.start.yaw, shot.end.yaw)), deg_to_rad(45.0), "a swing")
	assert_true(_across(shot.end, POST) < 0.0, "it lands with the general on the left third")
