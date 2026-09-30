extends GutTest
## CombatShots3D: the 3D combat cut-in's shot list — where the lens stands at
## every moment of one exchange, cut on CombatBeats' own windows. Pure, so the
## framing rules hold for every sheet and a still posed at any moment is the
## same picture every run.

const ATK := Vector3(-4.0, 0.3, 0.0)
const DEF := Vector3(4.0, 0.3, 0.0)

var styles: BattleStyleDB


func before_each() -> void:
	styles = BattleStyleDB.load_default()


func _result(countered: bool, defender_died: bool = false) -> CombatSnapshot.CombatResult:
	var result := CombatSnapshot.CombatResult.new()
	result.attacker_hp_before = 10
	result.attacker_hp_after = 10
	result.defender_hp_before = 10
	result.defender_hp_after = 0 if defender_died else 6
	result.defender_died = defender_died
	result.countered = countered and not defender_died
	return result


func _beats(countered: bool, defender_died: bool = false) -> CombatBeats:
	var cannon := styles.by_id(&"cannon")
	return CombatBeats.plan(_result(countered, defender_died), cannon, cannon, 1.0, 1.0)


func _kinds(shots: CombatShots3D) -> Array:
	return shots.kinds.map(func(kind: CombatShots3D.Shot) -> int: return kind)


func test_a_countered_exchange_is_six_shots_in_order() -> void:
	var shots := CombatShots3D.plan(_beats(true), ATK, DEF)
	var want := [
		CombatShots3D.Shot.OPEN,
		CombatShots3D.Shot.ATTACKER_FIRES,
		CombatShots3D.Shot.DEFENDER_HIT,
		CombatShots3D.Shot.DEFENDER_FIRES,
		CombatShots3D.Shot.ATTACKER_HIT,
		CombatShots3D.Shot.CLOSE,
	]
	assert_eq(_kinds(shots), want)
	for i in range(1, shots.starts.size()):
		assert_gt(shots.starts[i], shots.starts[i - 1], "shot %d starts after the one before" % i)


func test_an_unanswered_shot_has_no_mirror_pair() -> void:
	for died in [false, true]:
		var shots := CombatShots3D.plan(_beats(false, died), ATK, DEF)
		assert_false(_kinds(shots).has(CombatShots3D.Shot.DEFENDER_FIRES), "died %s" % died)
		assert_eq(shots.kinds[shots.kinds.size() - 1], CombatShots3D.Shot.CLOSE)


func test_the_cuts_fall_on_the_beat_sheet() -> void:
	var beats := _beats(true)
	var shots := CombatShots3D.plan(beats, ATK, DEF)
	assert_between(shots.starts[1], beats.atk_ready.x, beats.atk_ready.y, "fires in the wind-up")
	assert_between(shots.starts[2], beats.atk_travel.x, beats.atk_travel.y, "cuts mid-flight")
	assert_eq(shots.starts[3], maxf(beats.def_impact.y, beats.def_casualty.y), "after the falls")
	assert_lt(shots.starts[5], beats.wipe_out.x, "the close is up before the bars leave")
	assert_eq(shots.shot_at(beats.total), shots.starts.size() - 1, "ends on the close")


func test_over_the_shoulder_stands_behind_the_firer_and_looks_at_the_target() -> void:
	var beats := _beats(true)
	var shots := CombatShots3D.plan(beats, ATK, DEF)
	var attacker := shots.pose_at(shots.starts[1] + 0.01)
	assert_lt(attacker[0].x, ATK.x, "behind the attacker, on its outer side")
	assert_gt(attacker[1].x, ATK.x, "looking across at the foe")
	var counter := shots.pose_at(shots.starts[3] + 0.01)
	assert_gt(counter[0].x, DEF.x, "the mirror stands behind the defender")
	assert_lt(counter[1].x, DEF.x)


func test_the_hit_shot_frames_the_side_taking_it_from_the_firing_side() -> void:
	var shots := CombatShots3D.plan(_beats(true), ATK, DEF)
	var hit := shots.pose_at(shots.starts[2] + 0.01)
	assert_lt(hit[0].x, DEF.x, "stands on the attacker's side of the defender")
	assert_lt(hit[1].distance_to(DEF), 1.0, "and looks at it")
	assert_gt(hit[0].z, DEF.z, "from the lens's side of the stage")


func test_the_wides_take_in_both_squads() -> void:
	var shots := CombatShots3D.plan(_beats(true), ATK, DEF)
	for at in [0.0, shots.starts[5] + 0.05]:
		var pose := shots.pose_at(at)
		var mid := (ATK + DEF) * 0.5
		assert_lt(pose[1].distance_to(mid), 0.01, "looks at the middle at %s" % at)
		assert_gt(pose[0].distance_to(mid), DEF.x - ATK.x, "stands back far enough at %s" % at)


func test_a_lob_is_watched_landing_from_further_back() -> void:
	var beats := _beats(false)
	var flat := CombatShots3D.plan(beats, ATK, DEF, 0.0)
	var lobbed := CombatShots3D.plan(beats, ATK, DEF, 2.0)
	var at := flat.starts[2] + 0.01
	assert_gt(lobbed.pose_at(at)[1].y, flat.pose_at(at)[1].y, "looks up for the fall")
	assert_gt(lobbed.pose_at(at)[0].z, flat.pose_at(at)[0].z, "and stands back")


func test_the_lens_is_a_pure_function_of_the_clock_and_shakes_on_a_hit() -> void:
	var beats := _beats(true)
	var shots := CombatShots3D.plan(beats, ATK, DEF)
	var at := beats.def_impact.x + 0.02
	assert_eq(shots.pose_at(at), shots.pose_at(at), "the same moment, the same picture")
	assert_gt(shots.jolt(at), 0.0, "a landing volley shakes it")
	assert_eq(shots.jolt(beats.arrive.x), 0.0, "nothing shakes it before")
