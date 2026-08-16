extends GutTest
## The analyser's per-command detectors — walk_into_fire, worse_shot, oscillation —
## and the report they come out of, one board apiece.
##
## Split off test_replay_analysis.gd, which keeps the end-of-turn detectors, because
## the one file sat at the gdlintrc max-public-methods ceiling. The seam is the one
## the file already had section comments for: a detector that reads a command as it
## is issued belongs here, one that reads the board at the end of a turn belongs
## there. The fixture helpers are duplicated across the two rather than hoisted into
## a base class, the same as the four save-codec suites.
##
## Each case stands exactly the units its detector is about and hands the walk a
## recording made by hand, so a finding here can only come from the thing the test
## is named after. A detector with no fixture is a detector nobody can trust: the
## whole instrument's value is that a report says something true about the match,
## and a false positive costs more than a miss — it sends the reader looking at a
## doctrine that was playing correctly.
##
## The board is a file rather than an inline one because a replay stores its
## opening as a save envelope, which names its map by path.

const BOARD := "res://maps/fixtures/analysis.txt"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


## The fixture board with no units on it, ready for a test to stand its own.
func _bare_state() -> GameState:
	var map := MapData.load_from_file(BOARD, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = BOARD
	state.units.clear()
	return state


func _stand(state: GameState, id: StringName, team: int, cell: Vector2i) -> Unit:
	var unit := Unit.create(unit_db.by_id(id), team, cell)
	state.units.append(unit)
	return unit


## A recording of `entries` played from `state`. No checkpoints: a hand-made
## fixture is not describing a board some other build produced, and `drift` takes
## a line with none on trust for exactly that reason.
func _replay(state: GameState, entries: Array) -> ReplayCodec.Replay:
	var replay := ReplayCodec.Replay.new()
	replay.opening = SaveCodec.encode(state, [] as Array[int])
	for entry: Dictionary in entries:
		replay.entries.append(entry)
	return replay


func _run(state: GameState, entries: Array) -> ReplayAnalysis.Report:
	var report := ReplayAnalysis.run(
		_replay(state, entries), terrain_db, unit_db, chart, commander_db
	)
	assert_eq(report.stopped, "", "the fixture recording must re-issue cleanly")
	return report


func _count(report: ReplayAnalysis.Report, kind: String) -> int:
	return int(report.counts().get(kind, 0))


## The first finding of a kind. Asked for by name rather than by index because a
## board that trips one detector usually trips another.
func _first(report: ReplayAnalysis.Report, kind: String) -> ReplayAnalysis.Finding:
	for finding in report.findings:
		if finding.kind == kind:
			return finding
	return null


# --- per-command detectors -----------------------------------------------------


func test_walk_into_fire_is_a_move_out_of_safety_into_a_killing_ground() -> void:
	var state := _bare_state()
	_stand(state, &"infantry", 1, Vector2i(0, 0))
	# Three tanks in the far corner. Between them they can kill an infantry that
	# steps out to (3, 0), and none of them can reach a cell that fires on (0, 0).
	for x in [5, 6, 7]:
		_stand(state, &"tank", 2, Vector2i(x, 4))
	var report := _run(state, [{"c": "move", "path": [[0, 0], [1, 0], [2, 0], [3, 0]]}])
	assert_eq(_count(report, "walk_into_fire"), 1)


## The second half of the rule, and the half that makes it a finding: a unit
## already standing in the same fire did not walk into anything.
func test_a_move_inside_fire_it_was_already_in_is_not_reported() -> void:
	var state := _bare_state()
	_stand(state, &"infantry", 1, Vector2i(3, 3))
	for x in [3, 4, 5]:
		_stand(state, &"tank", 2, Vector2i(x, 4))
	assert_eq(_count(_run(state, [{"c": "move", "path": [[3, 3], [4, 3]]}]), "walk_into_fire"), 0)


func test_worse_shot_names_the_better_target_in_range() -> void:
	var state := _bare_state()
	_stand(state, &"tank", 1, Vector2i(3, 1))
	_stand(state, &"infantry", 2, Vector2i(2, 1))  # the cheap one it shot
	_stand(state, &"artillery", 2, Vector2i(4, 1))  # worth far more, and it cannot answer
	var report := _run(state, [{"c": "attack", "path": [[3, 1]], "target": [2, 1]}])
	assert_eq(_count(report, "worse_shot"), 1)
	assert_string_contains(_first(report, "worse_shot").detail, "artillery")


func test_the_best_shot_available_is_not_a_finding() -> void:
	var state := _bare_state()
	_stand(state, &"tank", 1, Vector2i(3, 1))
	_stand(state, &"infantry", 2, Vector2i(2, 1))
	_stand(state, &"artillery", 2, Vector2i(4, 1))
	var report := _run(state, [{"c": "attack", "path": [[3, 1]], "target": [4, 1]}])
	assert_eq(_count(report, "worse_shot"), 0)


## A kill is worth only the HP that was left, so a healthy dearer target outbids
## every finishing blow in funds — which had the detector accusing the planner of
## the one thing it was doing right, on 24 of the 27 findings two recorded
## matches held.
func test_a_kill_is_not_displaced_by_a_richer_shot_that_only_chips() -> void:
	var state := _bare_state()
	_stand(state, &"tank", 1, Vector2i(3, 1))
	var dying := _stand(state, &"infantry", 2, Vector2i(2, 1))
	dying.hp = 10  # what the tank finished
	_stand(state, &"artillery", 2, Vector2i(4, 1))  # worth far more, and it survives
	var report := _run(state, [{"c": "attack", "path": [[3, 1]], "target": [2, 1]}])
	assert_eq(_count(report, "worse_shot"), 0)


## The rule protects a kill and never argues for one: what a kill is worth past
## the funds it collects is the planner's own dial, so a cheap one left in range
## is not evidence of anything.
func test_a_kill_worth_less_than_the_shot_taken_is_not_a_finding() -> void:
	var state := _bare_state()
	_stand(state, &"tank", 1, Vector2i(3, 1))
	var dying := _stand(state, &"infantry", 2, Vector2i(2, 1))
	dying.hp = 10
	_stand(state, &"artillery", 2, Vector2i(4, 1))
	assert_eq(
		_count(_run(state, [{"c": "attack", "path": [[3, 1]], "target": [4, 1]}]), "worse_shot"), 0
	)


## A kill that is also the richer shot is still the shot that was there to take.
func test_a_richer_kill_in_range_is_the_better_shot() -> void:
	var state := _bare_state()
	_stand(state, &"tank", 1, Vector2i(3, 1))
	_stand(state, &"infantry", 2, Vector2i(2, 1))  # the cheap one it shot
	var gun := _stand(state, &"artillery", 2, Vector2i(4, 1))
	gun.hp = 30  # dearer even at a third, and the tank finishes it
	var report := _run(state, [{"c": "attack", "path": [[3, 1]], "target": [2, 1]}])
	assert_eq(_count(report, "worse_shot"), 1)
	assert_string_contains(_first(report, "worse_shot").detail, "kill")


## The exchange is priced in funds, and that is the whole of what makes this
## detector agree with the planner it is reading. A quarter of an md tank is worth
## several infantry outright, so a reading in raw HP percentages calls the heavy
## shot the worse one every time it is offered — which is what every large finding
## on a real recorded match turned out to be.
func test_the_dearer_target_survives_a_shot_the_hp_reading_would_flag() -> void:
	var state := _bare_state()
	var tank := _stand(state, &"tank", 1, Vector2i(3, 1))
	var heavy := _stand(state, &"md_tank", 2, Vector2i(4, 1))
	heavy.hp = 20  # what is left of it is still worth more than a whole infantry
	var soft := _stand(state, &"infantry", 2, Vector2i(2, 1))
	var hard_shot := CombatResolver.forecast(state, tank, Vector2i(3, 1), heavy)
	var soft_shot := CombatResolver.forecast(state, tank, Vector2i(3, 1), soft)
	assert_lt(
		hard_shot.attack_damage - hard_shot.counter_damage,
		soft_shot.attack_damage - soft_shot.counter_damage,
		"the fixture must be the worse shot in HP terms, or it proves nothing"
	)
	var report := _run(state, [{"c": "attack", "path": [[3, 1]], "target": [4, 1]}])
	assert_eq(_count(report, "worse_shot"), 0)


func test_oscillation_is_a_unit_walked_back_where_it_came_from() -> void:
	var state := _bare_state()
	_stand(state, &"infantry", 1, Vector2i(3, 1))
	var report := _run(
		state,
		[
			{"c": "end_turn"},  # seat 1 ends turn 1 standing on (3, 1)
			{"c": "end_turn"},
			{"c": "move", "path": [[3, 1], [4, 1]]},
			{"c": "end_turn"},  # turn 2 ends on (4, 1)
			{"c": "end_turn"},
			{"c": "move", "path": [[4, 1], [3, 1]]},
			{"c": "end_turn"},  # turn 3 ends back on (3, 1)
			{"c": "end_turn"},
		]
	)
	assert_eq(_count(report, "oscillation"), 1)


## The detector says "having fought nothing", so a unit that went out, took its
## shot and came home must not be one of them: the finding would contradict the
## board it names, which is the false positive this instrument cannot afford.
func test_a_unit_that_fought_on_the_way_out_is_not_oscillating() -> void:
	var state := _bare_state()
	_stand(state, &"infantry", 1, Vector2i(3, 1))
	_stand(state, &"infantry", 2, Vector2i(5, 1))
	var report := _run(
		state,
		[
			{"c": "end_turn"},  # seat 1 ends turn 1 standing on (3, 1)
			{"c": "end_turn"},
			{"c": "attack", "path": [[3, 1], [4, 1]], "target": [5, 1]},
			{"c": "end_turn"},  # turn 2 ends on (4, 1), having shot from it
			{"c": "end_turn"},
			{"c": "move", "path": [[4, 1], [3, 1]]},
			{"c": "end_turn"},  # turn 3 ends back on (3, 1)
			{"c": "end_turn"},
		]
	)
	assert_eq(_count(report, "oscillation"), 0)


func test_a_unit_walking_somewhere_is_not_oscillating() -> void:
	var state := _bare_state()
	_stand(state, &"infantry", 1, Vector2i(3, 1))
	var report := _run(
		state,
		[
			{"c": "end_turn"},
			{"c": "end_turn"},
			{"c": "move", "path": [[3, 1], [4, 1]]},
			{"c": "end_turn"},
			{"c": "end_turn"},
			{"c": "move", "path": [[4, 1], [5, 1]]},
			{"c": "end_turn"},
			{"c": "end_turn"},
		]
	)
	assert_eq(_count(report, "oscillation"), 0)


# --- the report itself ---------------------------------------------------------


## A recording this build cannot re-issue is reported as such rather than reported
## on: findings drawn from a board that stopped matching would be findings about a
## match nobody played.
func test_a_recording_that_stops_early_says_so() -> void:
	var state := _bare_state()
	var report := ReplayAnalysis.run(
		_replay(state, [{"c": "move", "path": [[4, 4]]}]), terrain_db, unit_db, chart
	)
	assert_string_contains(report.stopped, "could not be rebuilt")
	assert_push_error("where nothing stands")


func test_findings_rank_by_kind_before_size() -> void:
	var state := _bare_state()
	state.funds[1] = 9000
	_stand(state, &"infantry", 2, Vector2i(1, 1))  # threatens seat 1's home HQ
	_stand(state, &"infantry", 1, Vector2i(7, 1))
	# Three of seat 1's turns, so the purse clears the hoarding floor.
	var report := _run(
		state,
		[
			{"c": "end_turn"},
			{"c": "end_turn"},
			{"c": "end_turn"},
			{"c": "end_turn"},
			{"c": "end_turn"},
			{"c": "end_turn"},
		]
	)
	assert_gt(report.findings.size(), 1)
	assert_eq(
		report.findings[0].kind,
		"undefended_hq",
		"losing the match outranks a purse, whatever the two numbers happen to be"
	)
