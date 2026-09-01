extends GutTest
## The battle cut-in's beat sheet — where every window of one exchange lands on
## the clock, and how long the whole thing runs.
##
## In scope despite living beside the cut-in: CombatBeats is a RefCounted with no
## `Node` in it and `plan` is a pure function of a CombatResult, two BattleStyles
## and two floats, so this is timing arithmetic rather than drawing. Same terms
## `BattleStyle` and `BattleStyleDB` already earn in docs/testing_exceptions.md,
## and the first time the sheet has been checkable without staging a scene.
##
## Worth pinning because every failure here is quiet. A sheet that ran 0.4 s long
## still plays; a wind-up that collapsed under the streak lever still fires; a
## counter that opened while the last figure was in the air still finishes. The
## budgets below are the design record's own table, and they are pinned at
## `rate = 1.0` on purpose — the aim stretch deliberately grows the *sheet clock*
## at high rates while real time holds, so an unpinned fence would read the
## mechanism working as a regression.

## Half the fence width the budget rows are held to, in seconds.
const BUDGET_SLOP := 0.02
## The two rates the stretch is read at: the ceiling itself, and the Quick tier
## on the fourth cut-in of a streak (1.5 x 1.44).
const CEILING_RATE := 1.5
const STREAK_RATE := 2.16

## Every shipped signature, so a rule that must hold for all of them says so.
const STYLE_IDS: Array[StringName] = [
	&"small_arms",
	&"cannon",
	&"artillery",
	&"autocannon",
	&"rocket",
	&"bomb",
	&"torpedo",
	&"pintle",
	&"bazooka",
	&"unarmed",
]

var styles: BattleStyleDB


func before_each() -> void:
	styles = BattleStyleDB.load_default()


# --- shapes -------------------------------------------------------------------


func test_the_windows_run_forward_and_the_total_is_the_closing_wipe() -> void:
	var beats := CombatBeats.plan(_counter(), _style(&"cannon"), _style(&"cannon"), 1.0, 1.0)
	var ordered: Array[Vector2] = [
		beats.wipe_in,
		beats.arrive,
		beats.atk_ready,
		beats.atk_travel,
		beats.def_impact,
		beats.ctr_ready,
		beats.def_travel,
		beats.atk_impact,
		beats.wipe_out,
	]
	var last := 0.0
	for window in ordered:
		assert_gte(window.y, window.x, "%s runs backward" % window)
		assert_gte(window.x, last - 0.001, "%s opens before the beat before it" % window)
		last = window.x
	assert_almost_eq(beats.total, beats.wipe_out.y, 0.0001)


func test_an_unanswered_volley_has_no_counter_beats() -> void:
	var beats := CombatBeats.plan(_clean(), _style(&"cannon"), _style(&"cannon"), 1.0, 1.0)
	for window: Vector2 in [beats.ctr_ready, beats.def_recoil, beats.def_travel, beats.atk_impact]:
		assert_eq(window, Vector2.ZERO, "an exchange with no counter planned %s" % window)
	assert_eq(beats.def_fire, 0.0)


## A dead defender never answers, whatever the flag says: the blast beat takes
## over from the impact and the counter branch is never reached.
func test_a_dead_defender_has_no_counter_even_when_the_flag_says_countered() -> void:
	var result := _counter()
	result.defender_died = true
	var beats := CombatBeats.plan(result, _style(&"cannon"), _style(&"cannon"), 1.0, 1.0)
	assert_eq(beats.ctr_ready, Vector2.ZERO)
	assert_eq(beats.def_travel, Vector2.ZERO)
	assert_eq(beats.atk_impact, Vector2.ZERO)
	assert_gt(beats.def_death.y, beats.def_death.x, "but it does have a death")


func test_a_longer_travel_scale_hangs_the_volley_longer() -> void:
	var quick := CombatBeats.plan(_clean(), _style(&"small_arms"), _style(&"cannon"), 1.0, 1.0)
	var slow := CombatBeats.plan(_clean(), _style(&"torpedo"), _style(&"cannon"), 1.0, 1.0)
	assert_gt(_span(slow.atk_travel), _span(quick.atk_travel))


# --- the arrive and the wind-up ------------------------------------------------


## The squad is posted before anything winds up. Nothing here overlaps the two:
## the arrive is the roll-in and the aim is what happens once it has halted.
func test_the_arrive_closes_before_any_wind_up_opens() -> void:
	for id in STYLE_IDS:
		var beats := CombatBeats.plan(_clean(), _style(id), _style(&"cannon"), 1.0, 1.0)
		assert_lte(beats.arrive.y, beats.atk_ready.x, "%s winds up before it has arrived" % id)


func test_the_wind_up_is_the_style_s_own_length_on_both_sides() -> void:
	var beats := CombatBeats.plan(_counter(), _style(&"rocket"), _style(&"small_arms"), 1.0, 1.0)
	assert_almost_eq(_span(beats.atk_ready), 0.24, 0.0001, "the rocket's wind-up")
	assert_almost_eq(_span(beats.ctr_ready), 0.06, 0.0001, "the counter's, off the defender")
	assert_almost_eq(beats.atk_fire, beats.atk_ready.y, 0.0001)
	assert_almost_eq(beats.def_fire, beats.ctr_ready.y, 0.0001)


## Under the ceiling the sheet is exactly as authored — the default tier and the
## Quick tier play the same wind-ups.
func test_the_sheet_is_unchanged_at_and_below_the_rate_ceiling() -> void:
	var authored := CombatBeats.plan(_counter(), _style(&"cannon"), _style(&"rocket"), 1.0, 1.0)
	var quick := CombatBeats.plan(
		_counter(), _style(&"cannon"), _style(&"rocket"), 1.0, CEILING_RATE
	)
	assert_eq(quick.atk_ready, authored.atk_ready)
	assert_eq(quick.ctr_ready, authored.ctr_ready)
	assert_almost_eq(quick.total, authored.total, 0.0001)


## Above it the window is stretched by exactly rate / ceiling, which is what
## holds the *real* wind-up at `aim_seconds / 1.5` however fast the clock runs.
func test_a_streak_stretches_the_wind_up_rather_than_collapsing_it() -> void:
	var stretch := STREAK_RATE / CEILING_RATE
	var cannon := CombatBeats.plan(_clean(), _style(&"cannon"), _style(&"cannon"), 1.0, STREAK_RATE)
	var howitzer := CombatBeats.plan(
		_clean(), _style(&"artillery"), _style(&"cannon"), 1.0, STREAK_RATE
	)
	assert_almost_eq(_span(cannon.atk_ready), 0.16 * stretch, 0.0001)
	assert_almost_eq(_span(howitzer.atk_ready), 0.28 * stretch, 0.0001)
	var cannon_real := _span(cannon.atk_ready) / STREAK_RATE
	var howitzer_real := _span(howitzer.atk_ready) / STREAK_RATE
	assert_gte(cannon_real, 0.105, "a cannon's wind-up in real seconds")
	assert_gte(howitzer_real, 0.180, "a howitzer's wind-up in real seconds")
	assert_gte(howitzer_real - cannon_real, 0.075, "the spread the two are told apart by")
	var answered := CombatBeats.plan(
		_counter(), _style(&"cannon"), _style(&"rocket"), 1.0, STREAK_RATE
	)
	assert_almost_eq(_span(answered.ctr_ready), 0.24 * stretch, 0.0001, "the counter's too")


## The floor is what keeps a short wind-up's recoil from vanishing, and the ramp
## is allowed to open before the wind-up does — a hull settling back as it
## finishes rolling in is the correct read.
func test_every_style_gets_a_recoil_ramp_long_enough_to_see() -> void:
	for id in STYLE_IDS:
		var beats := CombatBeats.plan(_clean(), _style(id), _style(&"cannon"), 1.0, 1.0)
		assert_gte(_span(beats.atk_recoil), CombatBeats.RECOIL_FLOOR - 0.0001, "%s recoil" % id)
		assert_almost_eq(
			beats.atk_recoil.y, beats.atk_fire, 0.0001, "%s recoil ends on the shot" % id
		)


func test_a_short_wind_up_lets_its_recoil_open_inside_the_arrive() -> void:
	var beats := CombatBeats.plan(_clean(), _style(&"small_arms"), _style(&"cannon"), 1.0, 1.0)
	assert_lt(beats.atk_recoil.x, beats.atk_ready.x, "small arms' ramp overlaps the arrive")
	assert_gt(beats.atk_recoil.x, beats.arrive.x, "but it does not open before the arrive does")


# --- the casualty beat and its gate --------------------------------------------


func test_the_casualty_tail_is_flat_and_capped_at_two_steps() -> void:
	var impact := Vector2(1.0, 1.34)
	assert_almost_eq(CombatBeats.casualty_window(impact, 0).y, 1.34, 0.0001, "nothing lost")
	assert_almost_eq(CombatBeats.casualty_window(impact, 1).y, 1.44, 0.0001, "one figure")
	assert_almost_eq(CombatBeats.casualty_window(impact, 2).y, 1.54, 0.0001, "two figures")
	assert_almost_eq(CombatBeats.casualty_window(impact, 4).y, 1.54, 0.0001, "four, the same cap")
	assert_almost_eq(CombatBeats.casualty_window(impact, 4).x, 1.06, 0.0001)


## The counter cannot open until the last figure has landed. Ungated, a
## multi-figure topple is still in the air when the other side's muzzle lights.
func test_the_casualty_beat_gates_the_counter() -> void:
	var tails := {0: 0.0, 1: 0.10, 2: 0.20, 4: 0.20}
	for lost: int in tails:
		var tail: float = tails[lost]
		var beats := CombatBeats.plan(
			_counter_losing(lost), _style(&"cannon"), _style(&"cannon"), 1.0, 1.0
		)
		var settled := maxf(beats.def_impact.y, beats.def_casualty.y)
		assert_almost_eq(
			beats.def_casualty.y, beats.def_impact.y + tail, 0.0001, "%s figures lost" % lost
		)
		assert_almost_eq(beats.ctr_ready.x, settled, 0.0001, "the counter opened early")


## A dying side loses nothing: the blast takes the squad whole, so the casualty
## window never gates the death beat.
func test_a_dying_side_topples_nothing_and_gates_nothing() -> void:
	var result := _counter_losing(4)
	result.defender_died = true
	var beats := CombatBeats.plan(result, _style(&"cannon"), _style(&"cannon"), 1.0, 1.0)
	assert_almost_eq(beats.def_casualty.y, beats.def_impact.y, 0.0001)
	assert_almost_eq(beats.def_death.x, beats.def_impact.y - CombatBeats.DEATH_LEAD, 0.0001)


# --- the budgets ---------------------------------------------------------------


## The design record's own table, every row pinned at `rate = 1.0`. See the
## header for why the pin is load-bearing.
func test_the_sheet_holds_its_budgets() -> void:
	_assert_budget("cannon, no casualty", _clean(), _style(&"cannon"), 1.53)
	_assert_budget("cannon, one casualty", _losing(1), _style(&"cannon"), 1.63)
	_assert_budget("small arms, no casualty", _clean(), _style(&"small_arms"), 1.35)
	_assert_budget("howitzer, no casualty", _clean(), _style(&"artillery"), 1.76)
	_assert_budget("torpedo, no casualty", _clean(), _style(&"torpedo"), 1.67)


func test_a_kill_and_a_counter_hold_theirs_too() -> void:
	var killed := _clean()
	killed.defender_died = true
	_assert_budget("a kill", killed, _style(&"cannon"), 1.83)
	var typical := CombatBeats.plan(
		_counter_losing(1, 1), _style(&"cannon"), _style(&"cannon"), 1.0, 1.0
	)
	assert_almost_eq(typical.total, 2.55, BUDGET_SLOP, "the typical counter")
	var worst := CombatBeats.plan(
		_counter_losing(2, 2), _style(&"rocket"), _style(&"cannon"), 1.0, 1.0
	)
	assert_lte(worst.total, 2.90, "the worst exchange the roster can produce")


# --- the frames the smoke sweep takes ------------------------------------------


## The three posed stills sit in the beats their doc comments claim. Get one
## wrong and the sweep keeps photographing a frame that no longer shows what it
## was taken for, with nothing failing.
func test_the_posed_stills_land_in_the_beats_they_claim() -> void:
	var hit := CombatBeats.plan(_counter_losing(2), _style(&"cannon"), _style(&"cannon"), 1.0, 1.0)
	_assert_inside("cutin", BattleCutsceneScenario.CUT_IN_POSE, hit.def_impact)
	var killed := _clean()
	killed.defender_died = true
	var ko := CombatBeats.plan(killed, _style(&"cannon"), _style(&"cannon"), 1.0, 1.0)
	_assert_inside("cutin_ko", BattleCutsceneScenario.KO_POSE, ko.def_death)


## One clock cannot sit inside six impact windows once the wind-up has pulled the
## firing times 0.18 s apart, so CUT_IN_POSE's comment states which split it
## picks. That split is the assertion: a signature that draws a burst is
## mid-impact at the pose, and the ones whose `impact_radius` is 0 — their hit is
## a spark stitch, not a burst — have settled past theirs. Without it the sweep
## keeps photographing frames that no longer show what the constant claims.
func test_the_impact_pose_splits_the_signatures_the_way_it_claims() -> void:
	for id in STYLE_IDS:
		var style := _style(id)
		var beats := CombatBeats.plan(_losing(1), style, _style(&"cannon"), 1.0, 1.0)
		var at := BattleCutsceneScenario.CUT_IN_POSE
		if style.impact_radius > 0.0:
			_assert_inside("cutin:%s" % id, at, beats.def_impact)
		else:
			assert_gt(at, beats.def_impact.y, "%s is still bursting at the impact pose" % id)


## Every signature that puts something on screen has it on screen at the volley
## pose. The silent one is skipped rather than held to it: nothing leaves an
## unarmed barrel at any moment of any sheet, and the roster's three transports
## can never be the attacker in the first place — holding a window nothing is
## ever drawn in would pin the pose against a frame that does not exist.
func test_every_signature_still_has_a_round_in_the_air_at_the_volley_pose() -> void:
	for id in STYLE_IDS:
		var style := _style(id)
		if not style.fires():
			continue
		var beats := CombatBeats.plan(_clean(), style, _style(&"cannon"), 1.0, 1.0)
		_assert_inside("cutin_volley:%s" % id, BattleCutsceneScenario.VOLLEY_POSE, beats.atk_travel)


## And the two fences that leave it only 26 ms to sit in, named so a style moved
## past either of them fails here rather than in a frame nobody looks at. The
## howitzer fires last, at 0.62; small arms' stream is the first gone, at 0.6465.
func test_the_volley_pose_sits_between_the_last_barrel_and_the_first_arrival() -> void:
	var latest := CombatBeats.plan(_clean(), _style(&"artillery"), _style(&"cannon"), 1.0, 1.0)
	var earliest := CombatBeats.plan(_clean(), _style(&"small_arms"), _style(&"cannon"), 1.0, 1.0)
	assert_gt(
		BattleCutsceneScenario.VOLLEY_POSE,
		latest.atk_fire,
		"the pose has to be after the last barrel in the roster lights"
	)
	assert_lt(
		BattleCutsceneScenario.VOLLEY_POSE,
		earliest.atk_travel.y,
		"and before the first volley in the roster has arrived"
	)


# --- helpers -------------------------------------------------------------------


func _assert_budget(
	what: String, result: CombatSnapshot.CombatResult, style: BattleStyle, want: float
) -> void:
	var beats := CombatBeats.plan(result, style, _style(&"cannon"), 1.0, 1.0)
	assert_almost_eq(beats.total, want, BUDGET_SLOP, what)


func _assert_inside(what: String, at: float, window: Vector2) -> void:
	var progress := (at - window.x) / (window.y - window.x)
	assert_gt(progress, 0.0, "%s poses before %s opens" % [what, window])
	assert_lt(progress, 1.0, "%s poses after %s closes" % [what, window])


func _style(id: StringName) -> BattleStyle:
	return styles.by_id(id)


## A hit the defender survives and does not answer, with its whole squad left.
func _clean() -> CombatSnapshot.CombatResult:
	var result := CombatSnapshot.CombatResult.new()
	result.attacker_hp_before = 10
	result.attacker_hp_after = 10
	result.defender_hp_before = 10
	result.defender_hp_after = 10
	return result


## The same, with `lost` of the defender's figures gone.
func _losing(lost: int) -> CombatSnapshot.CombatResult:
	var result := _clean()
	result.defender_hp_after = result.defender_hp_before - lost * 2
	return result


func _counter() -> CombatSnapshot.CombatResult:
	var result := _clean()
	result.countered = true
	return result


func _counter_losing(defender_lost: int, attacker_lost: int = 0) -> CombatSnapshot.CombatResult:
	var result := _losing(defender_lost)
	result.countered = true
	result.attacker_hp_after = result.attacker_hp_before - attacker_lost * 2
	return result


func _span(window: Vector2) -> float:
	return window.y - window.x
