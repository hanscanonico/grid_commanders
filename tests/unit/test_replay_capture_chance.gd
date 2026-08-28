extends GutTest
## The analyser's `missed_capture` detector, one board apiece.
##
## Split off test_replay_analysis.gd, which keeps the other end-of-turn detectors,
## because the one file sat at the gdlintrc max-public-methods ceiling and this
## detector is the one with a family of cases: what buys a turn, which board the
## reach is measured on, and — the reason for the split — what the rest of the
## side did with the ground. The fixture helpers are `ReplayFixture`'s.
##
## Capturing is a **side**-level decision, so most of what is checked here is the
## detector staying quiet: a false positive costs more than a miss, and every
## finding this detector made on a real recorded match named ground one of the
## side's own other units had already taken.


func _run(state: GameState, entries: Array) -> ReplayAnalysis.Report:
	var report := ReplayFixture.run(state, entries)
	assert_eq(report.stopped, "", "the fixture recording must re-issue cleanly")
	return report


func test_missed_capture_is_ground_a_footsoldier_could_have_stood_on() -> void:
	var state := ReplayFixture.board()
	# One step off the neutral city at (2, 2).
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(2, 3))
	var report := _run(state, [{"c": "end_turn"}])
	assert_eq(ReplayFixture.count(report, "missed_capture"), 1)
	assert_string_contains(ReplayFixture.first(report, "missed_capture").detail, "(2, 2)")


func test_a_unit_that_did_capture_is_not_reported() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(2, 3))
	var report := _run(state, [{"c": "capture", "path": [[2, 3], [2, 2]]}, {"c": "end_turn"}])
	assert_eq(ReplayFixture.count(report, "missed_capture"), 0)


## A shot buys the turn: the detector prices ground not taken, and a unit that
## fought instead made a trade this instrument cannot judge.
func test_a_unit_that_fought_instead_is_not_a_missed_capture() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(2, 3))
	ReplayFixture.stand(state, &"infantry", 2, Vector2i(2, 4))  # adjacent, so the shot needs no walk
	var entries: Array = [
		{"c": "attack", "path": [[2, 3]], "target": [2, 4]},
		{"c": "end_turn"},
	]
	assert_eq(ReplayFixture.count(_run(state, entries), "missed_capture"), 0)


## Only fighting buys it. A unit that walked and did nothing else is the miss the
## detector exists for, so the exclusion may never be widened to `acted`.
func test_a_unit_that_only_walked_is_still_a_missed_capture() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(2, 3))
	var entries: Array = [{"c": "move", "path": [[2, 3], [3, 3]]}, {"c": "end_turn"}]
	var report := _run(state, entries)
	assert_eq(ReplayFixture.count(report, "missed_capture"), 1)
	# The unit is standing at (3, 3) by the time the finding is made, so the line has
	# to name the cell the reach was measured from or the reader cannot check it.
	assert_string_contains(ReplayFixture.first(report, "missed_capture").detail, "(2, 3)")


## The reach is the one the turn *opened* with. A capturer marching toward ground
## it could not have stood on this turn is doing exactly what it should, and the
## board it hands over — where it has moved and its budget is gone — answers a
## question about next turn.
func test_ground_the_walk_only_brought_into_reach_is_not_a_missed_capture() -> void:
	var state := ReplayFixture.board()
	# Four tiles from the neutral city at (2, 2) on three movement, and it spends
	# the whole walk closing to one step short of it.
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(0, 4))
	var entries: Array = [
		{"c": "move", "path": [[0, 4], [1, 4], [1, 3], [2, 3]]},
		{"c": "end_turn"},
	]
	assert_eq(ReplayFixture.count(_run(state, entries), "missed_capture"), 0)


## Two footsoldiers opening beside the same neutral city is the side playing
## correctly, and this is the case the detector spent a whole measurement pass
## getting wrong: one of them takes the ground and the other has nothing left to
## take, so blaming the second is blaming it for the first having got there.
func test_ground_an_ally_captured_is_not_a_missed_capture() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(2, 1))  # the one that takes the city at (2, 2)
	# And the one with nothing else in reach.
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(2, 3))
	var entries: Array = [{"c": "capture", "path": [[2, 1], [2, 2]]}, {"c": "end_turn"}]
	assert_eq(ReplayFixture.count(_run(state, entries), "missed_capture"), 0)


## Occupied is claimed too, even by something that cannot capture: on a real
## recording one of these cells was a firing position rather than a capture, and
## the ground is just as unavailable either way.
func test_ground_an_ally_is_standing_on_is_not_a_missed_capture() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"tank", 1, Vector2i(2, 1))
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(2, 3))
	var entries: Array = [{"c": "move", "path": [[2, 1], [2, 2]]}, {"c": "end_turn"}]
	assert_eq(ReplayFixture.count(_run(state, entries), "missed_capture"), 0)


## The other half of the rule: only the claimed ground comes off the list. A unit
## that still had a second, untouched property in its opening reach missed one.
func test_a_second_unclaimed_property_still_fires() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(2, 1))  # takes the city at (2, 2)
	# Within reach of both cities, and the far one is nobody else's business.
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(3, 2))
	var entries: Array = [{"c": "capture", "path": [[2, 1], [2, 2]]}, {"c": "end_turn"}]
	var report := _run(state, entries)
	assert_eq(ReplayFixture.count(report, "missed_capture"), 1)
	assert_string_contains(ReplayFixture.first(report, "missed_capture").detail, "(5, 2)")


## Only a *sibling*'s claim strikes a cell off. A unit standing on the property it
## walked onto and did not take is the miss the detector exists for, so its own
## occupancy may never excuse it.
func test_standing_on_the_property_it_did_not_take_still_fires() -> void:
	var state := ReplayFixture.board()
	ReplayFixture.stand(state, &"infantry", 1, Vector2i(2, 3))
	var entries: Array = [{"c": "move", "path": [[2, 3], [2, 2]]}, {"c": "end_turn"}]
	var report := _run(state, entries)
	assert_eq(ReplayFixture.count(report, "missed_capture"), 1)
	assert_string_contains(ReplayFixture.first(report, "missed_capture").detail, "(2, 2)")
