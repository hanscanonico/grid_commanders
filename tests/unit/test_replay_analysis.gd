extends GutTest
## The analyser's end-of-turn detectors, one board apiece. The per-command ones and
## the report itself are test_replay_detectors.gd — the seam this file's section
## comments already drew, split when the one file crossed the gdlintrc
## max-public-methods ceiling. `missed_capture` is test_replay_capture_chance.gd,
## split off the same ceiling once it grew a family of cases. All three build their
## boards and read their reports through `ReplayFixture`.
##
## Each case stands exactly the units its detector is about and hands the walk a
## recording made by hand, so a finding here can only come from the thing the test
## is named after. A detector with no fixture is a detector nobody can trust: the
## whole instrument's value is that a report says something true about the match,
## and a false positive costs more than a miss — it sends the reader looking at a
## doctrine that was playing correctly.

var commander_db: CommanderDB


func before_each() -> void:
	commander_db = Fixture.commander_db()


func _run(state: GameState, entries: Array) -> ReplayAnalysis.Report:
	var report := ReplayFixture.run(state, entries)
	assert_eq(report.stopped, "", "the fixture recording must re-issue cleanly")
	return report


## `turns` full rounds of both sides doing nothing but ending their turn.
func _idle_rounds(turns: int) -> Array:
	var entries: Array = []
	for i in turns * 2:
		entries.append({"c": "end_turn"})
	return entries


# --- end-of-turn detectors -----------------------------------------------------


func test_hoarding_is_money_left_on_an_idle_factory() -> void:
	var state := ReplayFixture.board()
	state.funds[1] = 9000
	# Seat 2 opens broke, but its own properties earn over the three turns the floor
	# asks for, so the case reads seat 1 rather than the whole report.
	state.funds[2] = 0
	var report := _run(state, _idle_rounds(3))
	assert_eq(ReplayFixture.for_team(report, "hoarding", 1).size(), 1)
	var finding: ReplayAnalysis.Finding = ReplayFixture.for_team(report, "hoarding", 1)[0]
	assert_gte(finding.magnitude, 9000)
	assert_string_contains(finding.detail, str(finding.magnitude))


## The purse is measured against what this side is actually charged. A doctrine
## that marks production up leaves money on the table that buys nothing, and a
## detector reading the sticker price would send the reader after a build order
## that was already doing the only thing it could.
## The same 1100 opens the streak on day one at the sticker price and only on day
## two under Vale, whose 20% leaves it short of the board's one 1000 build. The
## streak's first day is what the case reads, because income carries any purse
## past any price if the walk is given enough turns — an absence of findings would
## be reporting the floor rather than the rule.
func test_a_purse_short_of_a_marked_up_price_is_not_hoarding() -> void:
	var marked_up := ReplayFixture.board()
	marked_up.set_commander(1, commander_db.by_id(&"konrad_vale"))
	marked_up.funds[1] = 1100
	marked_up.funds[2] = 0
	var short_report := ReplayFixture.for_team(_run(marked_up, _idle_rounds(4)), "hoarding", 1)
	assert_eq(short_report.size(), 1)
	assert_eq(short_report[0].day, 2, "day one's purse bought nothing at Vale's price")
	assert_string_contains(short_report[0].detail, "1200")
	var sticker := ReplayFixture.board()
	sticker.funds[1] = 1100
	sticker.funds[2] = 0
	var open_report := ReplayFixture.for_team(_run(sticker, _idle_rounds(4)), "hoarding", 1)
	assert_eq(open_report.size(), 1)
	assert_eq(open_report[0].day, 1, "the same purse covers the price nobody marks up")
	assert_string_contains(open_report[0].detail, "1000")


## A purse under everything on the board is not a turn spent hoarding, so the
## streak opens on the first turn income has carried it over the cheapest build.
func test_a_purse_too_small_for_anything_does_not_open_a_streak() -> void:
	var state := ReplayFixture.board()
	state.funds[1] = 100
	state.funds[2] = 100
	var report := ReplayFixture.for_team(_run(state, _idle_rounds(4)), "hoarding", 1)
	assert_eq(report.size(), 1)
	assert_eq(report[0].day, 2, "day one's 100 buys nothing at all")


## One streak, one finding. Said every turn it was more than half of everything
## the analyser printed on a real match, and five copies of one sentence tell the
## reader nothing the first did not.
##
## Seat 2 is counted separately and only reported once it has earned its way into
## a purse of its own, which is why every case here reads one side.
func test_a_standing_hoard_is_reported_once_for_the_whole_streak() -> void:
	var state := ReplayFixture.board()
	state.funds[1] = 9000
	state.funds[2] = 0
	var report := _run(state, _idle_rounds(5))
	assert_eq(ReplayFixture.for_team(report, "hoarding", 1).size(), 1)
	var finding: ReplayAnalysis.Finding = ReplayFixture.for_team(report, "hoarding", 1)[0]
	assert_string_contains(finding.detail, "5 turns")
	assert_eq(finding.day, 1, "the finding is about where the streak began")


## Peak funds, not the funds it happened to end on: what the streak cost the side
## is the most it ever had sitting idle. Seat 1's two properties earn every turn,
## so the purse the walk sees only climbs away from the one it opened with.
func test_a_hoard_carries_the_peak_of_the_streak() -> void:
	var state := ReplayFixture.board()
	state.funds[1] = 9000
	state.funds[2] = 0
	var finding: ReplayAnalysis.Finding = (
		ReplayFixture.for_team(_run(state, _idle_rounds(3)), "hoarding", 1)[0]
	)
	assert_gt(finding.magnitude, 9000, "the fixture must actually grow the purse")
	assert_string_contains(finding.detail, str(finding.magnitude))


## A side is allowed to save up for something better than the cheapest thing on
## the board, so a short hoard is the production planner playing as written. It was
## about half of everything the analyser printed on real recordings, nearly all of
## it one and two turn streaks.
func test_a_two_turn_hoard_is_the_planner_saving_up() -> void:
	var state := ReplayFixture.board()
	state.funds[1] = 9000
	state.funds[2] = 0
	assert_eq(ReplayFixture.count(_run(state, _idle_rounds(2)), "hoarding"), 0)


## A streak that ends is released there, and a later one is a second finding.
func test_a_hoard_that_ends_and_starts_again_is_reported_twice() -> void:
	var state := ReplayFixture.board()
	state.funds[1] = 9000
	state.funds[2] = 0
	var entries: Array = [
		{"c": "end_turn"},  # day 1: the streak opens
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "end_turn"},
		# A turn the side spent something on is not a hoarding turn: the streak ends.
		{"c": "build", "cell": [1, 0], "unit": "infantry"},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "move", "path": [[1, 0], [2, 0]]},  # off the base, and it is idle again
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "end_turn"},
	]
	assert_eq(ReplayFixture.for_team(_run(state, entries), "hoarding", 1).size(), 2)


## The case the detector exists for: a growing purse and nothing bought out of it,
## turn after turn. Both numbers the reader needs are in the one line — how long it
## went on and the most that sat there while it did.
func test_a_rich_side_that_buys_nothing_is_the_reported_case() -> void:
	var state := ReplayFixture.board()
	state.funds[1] = 13000
	state.funds[2] = 0
	var report := _run(state, _idle_rounds(4))
	assert_eq(ReplayFixture.for_team(report, "hoarding", 1).size(), 1)
	var finding: ReplayAnalysis.Finding = ReplayFixture.for_team(report, "hoarding", 1)[0]
	assert_string_contains(finding.detail, "4 turns")
	assert_string_contains(finding.detail, str(finding.magnitude))
	assert_gte(finding.magnitude, 13000)


## Spare capacity is not refusal to spend. A side holding more production than it
## can fill every turn always has a free property, so a detector reading "something
## stood idle" reports the sides that were buying hardest — which is what it did on
## every multi-base board it was measured on. Seat 1 buys every turn here and the
## far base is free and affordable throughout.
func test_a_side_that_builds_every_turn_is_not_hoarding() -> void:
	var state := ReplayFixture.board()
	state.funds[1] = 50000
	state.funds[2] = 0
	state.set_owner(Vector2i(6, 4), 1)
	var entries: Array = [
		{"c": "build", "cell": [1, 0], "unit": "infantry"},
		{"c": "end_turn"},
		{"c": "end_turn"},
	]
	var walked: Array = [[1, 0]]
	for step in 3:
		walked.append([2 + step, 0])
		entries.append({"c": "move", "path": walked.duplicate()})
		entries.append({"c": "build", "cell": [1, 0], "unit": "infantry"})
		entries.append({"c": "end_turn"})
		entries.append({"c": "end_turn"})
	var report := _run(state, entries)
	assert_eq(ReplayFixture.for_team(report, "hoarding", 1).size(), 0)


## Three of its owner's turns, not three end-turns: the streak is per side, and a
## detector that counted rounds would report a unit twice as fast as it says.
func test_idle_unit_needs_three_of_its_owners_turns() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(3, 1))
	ReplayFixture.stand(state, &"infantry", 2, Vector2i(4, 1))  # in reach, so there is something to do
	assert_eq(
		ReplayFixture.count(_run(state, _idle_rounds(2)), "idle_unit"), 0, "two turns is patience"
	)
	# Two, one per side: each infantry has the other in reach, so both are idle and
	# both are reported. What the case is about is the third turn, not the count.
	assert_eq(
		ReplayFixture.count(_run(state, _idle_rounds(3)), "idle_unit"), 2, "three is nobody playing"
	)


## Something in reach is not something to do. An infantry has no shot at a fighter
## at all — the damage chart has no row for it — so a detector reading a loaded
## weapon over an occupied cell reports a unit that was out of answers.
func test_a_unit_that_cannot_engage_what_is_in_reach_is_not_idle() -> void:
	var state := ReplayFixture.board()
	# The far corner, so no property is within the infantry's walk and the fighter
	# is the only thing it could be reported for.
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(0, 4))
	ReplayFixture.stand(state, &"fighter", 2, Vector2i(1, 4))
	assert_eq(ReplayFixture.for_team(_run(state, _idle_rounds(4)), "idle_unit", 1).size(), 0)


func test_a_unit_with_nothing_in_reach_is_not_idle() -> void:
	var state := ReplayFixture.board()
	# A lone tank: it cannot capture, and there is no enemy anywhere to shoot.
	ReplayFixture.stand(state, &"tank", 1, Vector2i(4, 1))
	assert_eq(ReplayFixture.count(_run(state, _idle_rounds(4)), "idle_unit"), 0)


func test_banked_power_counts_a_full_meter_nobody_fires() -> void:
	var state := ReplayFixture.board()
	var db := Fixture.commander_db()
	state.set_commander(1, db.by_id(&"alina_ward"))
	var co_state := state.commander_state(1)
	co_state.charge = co_state.type.power_cost
	assert_true(co_state.is_ready(), "the fixture must actually hold a charged power")
	assert_eq(ReplayFixture.count(_run(state, _idle_rounds(2)), "banked_power"), 0)
	var short_hold := _run(state, _idle_rounds(3))
	assert_eq(ReplayFixture.count(short_hold, "banked_power"), 1)
	assert_eq(ReplayFixture.first(short_hold, "banked_power").magnitude, 3)
	# One uninterrupted hold is one finding however long it runs: holding a meter
	# all match is what a benefit-gated doctrine does on purpose. The number it
	# reports is the length it ran to, released here by the recording ending.
	var long_hold := _run(state, _idle_rounds(9))
	assert_eq(ReplayFixture.count(long_hold, "banked_power"), 1)
	assert_eq(ReplayFixture.first(long_hold, "banked_power").magnitude, 9)
	assert_string_contains(ReplayFixture.first(long_hold, "banked_power").detail, "for 9 turns")


## Latched, not silenced: a hold that really breaks is a second finding. Firing
## is the only way a meter comes down, so the break here is the whole cycle —
## spent, then charged back up by what seat 2's bomber destroys.
func test_banked_power_reports_again_after_the_hold_breaks() -> void:
	var state := ReplayFixture.board()
	state.set_commander(1, commander_db.by_id(&"sera_lark"))
	var co_state := state.commander_state(1)
	co_state.charge = co_state.type.power_cost
	ReplayFixture.stand(state, &"tank", 1, Vector2i(4, 1))
	ReplayFixture.stand(state, &"tank", 1, Vector2i(4, 3))
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(0, 4))  # so the kills do not end the match
	ReplayFixture.stand(state, &"bomber", 2, Vector2i(4, 2))
	var entries := _idle_rounds(3)
	entries.append_array([{"c": "power", "target": [0, 0]}, {"c": "end_turn"}])
	# Two runs at the armour: seat 1 banks what it loses, which refills the meter.
	for target: Array in [[4, 1], [4, 3]]:
		entries.append({"c": "attack", "path": [[4, 2]], "target": target})
		entries.append({"c": "end_turn"})
		entries.append({"c": "end_turn"})
	entries.append_array(_idle_rounds(3))
	assert_eq(ReplayFixture.count(_run(state, entries), "banked_power"), 2)


func test_a_power_that_goes_off_resets_the_count() -> void:
	var state := ReplayFixture.board()
	var db := Fixture.commander_db()
	state.set_commander(1, db.by_id(&"alina_ward"))
	state.commander_state(1).charge = state.commander_state(1).type.power_cost
	var entries: Array = [{"c": "power", "target": [0, 0]}, {"c": "end_turn"}]
	entries.append_array(_idle_rounds(2))
	assert_eq(ReplayFixture.count(_run(state, entries), "banked_power"), 0)


func test_stranded_transport_is_cargo_nobody_puts_down() -> void:
	var state := ReplayFixture.board()
	var apc := ReplayFixture.stand(state, &"apc", 1, Vector2i(4, 1))
	var rider := ReplayFixture.stand(state, &"infantry", 1, Vector2i(4, 1))
	rider.carrier = apc
	assert_eq(ReplayFixture.count(_run(state, _idle_rounds(2)), "stranded_transport"), 0)
	assert_eq(ReplayFixture.count(_run(state, _idle_rounds(3)), "stranded_transport"), 1)


func test_an_empty_transport_is_not_stranded() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"apc", 1, Vector2i(4, 1))
	assert_eq(ReplayFixture.count(_run(state, _idle_rounds(4)), "stranded_transport"), 0)


func test_undefended_hq_is_an_enemy_in_reach_of_home_with_no_answer() -> void:
	var state := ReplayFixture.board()
	# Seat 2's infantry a step from seat 1's home HQ at (0, 0); seat 1 has nothing
	# anywhere near it.
	ReplayFixture.stand(state, &"infantry", 2, Vector2i(1, 1))
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(7, 1))
	var report := _run(state, [{"c": "end_turn"}])
	assert_eq(ReplayFixture.count(report, "undefended_hq"), 1)
	assert_string_contains(ReplayFixture.first(report, "undefended_hq").detail, "(0, 0)")


func test_an_hq_something_can_get_back_to_is_not_undefended() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"infantry", 2, Vector2i(1, 1))
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(0, 1))  # standing on the doorstep
	assert_eq(ReplayFixture.count(_run(state, [{"c": "end_turn"}]), "undefended_hq"), 0)


## The heaviest severity in the table, so a standing lapse said every turn would
## fill the printed summary with one sentence. Latched like `banked_power`.
func test_a_standing_undefended_hq_is_reported_once() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"infantry", 2, Vector2i(1, 1))
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(4, 1))  # too far to answer for either HQ
	assert_eq(ReplayFixture.count(_run(state, _idle_rounds(4)), "undefended_hq"), 1)


## Cleared the moment the side can answer for the HQ again, so a second lapse is a
## second finding.
func test_an_hq_covered_and_then_exposed_again_is_reported_twice() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"infantry", 2, Vector2i(1, 1))
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(3, 1))
	var entries: Array = [
		{"c": "end_turn"},  # exposed: reported
		{"c": "end_turn"},
		{"c": "move", "path": [[3, 1], [2, 1]]},  # back in reach of home
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "move", "path": [[2, 1], [3, 1], [4, 1], [5, 1]]},  # and away again
		{"c": "end_turn"},
	]
	assert_eq(ReplayFixture.count(_run(state, entries), "undefended_hq"), 2)
