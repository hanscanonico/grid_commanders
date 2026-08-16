extends GutTest
## The analyser must not report a mistake against a unit the rules hide.
##
## `Vision.is_hidden_from` is the planner's one deliberate blindness — Sable
## Wren's Vanish, and a submerged submarine, which is hidden with fog off as
## well. A counterfactual drawn over a hidden unit is advice the side could not
## have taken: it would say a shot was there to be had, a gun was there to be
## dodged, or an HQ was there to be defended, against something nobody could see.
## That is the false positive this instrument cannot afford, so each case here is
## a pair — the same board and the same recording, hidden and not — and the
## control is what proves the detector was firing before the guard withheld it.
##
## Its own suite rather than a case in test_replay_detectors.gd or
## test_replay_analysis.gd: the two per-command detectors and the two
## end-of-turn ones are one idea read four times, and test_replay_analysis.gd
## sits at the gdlintrc max-public-methods ceiling.

const BOARD := "res://maps/fixtures/thicket.txt"
## Open water and no cover: the dive half of the rule needs neither.
const CHANNEL := "res://maps/fixtures/channel.txt"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


## The board with no units on it, ready for a test to stand its own.
func _bare_state(path: String) -> GameState:
	var map := MapData.load_from_file(path, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = path
	state.units.clear()
	return state


func _stand(state: GameState, id: StringName, team: int, cell: Vector2i) -> Unit:
	var unit := Unit.create(unit_db.by_id(id), team, cell)
	state.units.append(unit)
	return unit


## Seat 2 plays Sable Wren, with fog up and Vanish running: everything of theirs
## standing in cover is invisible to seat 1 for the round. Fired here rather than
## as a recorded command because the opening is a save envelope, which carries
## `power_active` — and seat 1, whose play is being judged, acts first.
func _vanish(state: GameState) -> void:
	state.fog_enabled = true
	state.set_commander(2, commander_db.by_id(&"sable_wren"))
	state.current_team = 2
	assert_eq(Fixture.fire_power(state, 2), "", "the fixture must be able to fire Vanish")
	state.current_team = 1


func _run(state: GameState, entries: Array) -> ReplayAnalysis.Report:
	var replay := ReplayCodec.Replay.new()
	replay.opening = SaveCodec.encode(state, [] as Array[int])
	for entry: Dictionary in entries:
		replay.entries.append(entry)
	var report := ReplayAnalysis.run(replay, terrain_db, unit_db, chart, commander_db)
	assert_eq(report.stopped, "", "the fixture recording must re-issue cleanly")
	return report


func _count(report: ReplayAnalysis.Report, kind: String) -> int:
	return int(report.counts().get(kind, 0))


## A tank with a cheap infantry and a dear artillery both in range, shooting the
## infantry. The artillery stands in the woods Vanish hides.
func _shot_board(hidden: bool) -> GameState:
	var state := _bare_state(BOARD)
	_stand(state, &"tank", 1, Vector2i(1, 1))
	_stand(state, &"infantry", 2, Vector2i(2, 1))
	_stand(state, &"artillery", 2, Vector2i(0, 1))
	if hidden:
		_vanish(state)
	return state


## An infantry stepping from open ground it is safe on to a cell a footsoldier in
## the far woods can reach and kill it on.
func _walk_board(hidden: bool) -> GameState:
	var state := _bare_state(BOARD)
	var walker := _stand(state, &"infantry", 1, Vector2i(3, 4))
	walker.hp = 5
	_stand(state, &"infantry", 2, Vector2i(7, 3))
	if hidden:
		_vanish(state)
	return state


## Seat 1's home HQ with an enemy footsoldier in the woods beside it and nothing
## of seat 1's within reach to contest the cell.
func _hq_board(hidden: bool) -> GameState:
	var state := _bare_state(BOARD)
	_stand(state, &"infantry", 1, Vector2i(4, 0))
	_stand(state, &"infantry", 2, Vector2i(0, 1))
	if hidden:
		_vanish(state)
	return state


## A tank that can capture nothing, standing still with one enemy in range — the
## only thing it has to do, and the thing Vanish takes away.
func _idle_board(hidden: bool) -> GameState:
	var state := _bare_state(BOARD)
	_stand(state, &"tank", 1, Vector2i(1, 1))
	_stand(state, &"infantry", 2, Vector2i(0, 1))
	if hidden:
		_vanish(state)
	return state


# --- the four sites ------------------------------------------------------------


func test_a_hidden_target_is_not_a_better_shot_the_side_passed_up() -> void:
	var seen := _run(_shot_board(false), [{"c": "attack", "path": [[1, 1]], "target": [2, 1]}])
	assert_eq(_count(seen, "worse_shot"), 1, "the artillery is the shot to take when it is there")
	var hidden := _run(_shot_board(true), [{"c": "attack", "path": [[1, 1]], "target": [2, 1]}])
	assert_eq(_count(hidden, "worse_shot"), 0)


func test_a_hidden_gun_is_not_fire_the_move_walked_into() -> void:
	var seen := _run(_walk_board(false), [{"c": "move", "path": [[3, 4], [4, 4]]}])
	assert_eq(_count(seen, "walk_into_fire"), 1, "the cell is a killing ground when it is seen")
	var hidden := _run(_walk_board(true), [{"c": "move", "path": [[3, 4], [4, 4]]}])
	assert_eq(_count(hidden, "walk_into_fire"), 0)


func test_a_hidden_enemy_does_not_leave_the_hq_undefended() -> void:
	var seen := _run(_hq_board(false), [{"c": "end_turn"}])
	assert_eq(_count(seen, "undefended_hq"), 1, "the HQ is open to a footsoldier that is seen")
	var hidden := _run(_hq_board(true), [{"c": "end_turn"}])
	assert_eq(_count(hidden, "undefended_hq"), 0)


## Three of seat 1's turns, which is the idle floor. Vanish covers the first of
## them, so the streak restarts and never reaches it — the guard read through the
## detector's own counter.
func test_a_hidden_enemy_is_not_something_a_still_unit_had_to_do() -> void:
	var turns := [
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "end_turn"},
		{"c": "end_turn"},
	]
	assert_eq(_count(_run(_idle_board(false), turns), "idle_unit"), 1, "one enemy is one errand")
	assert_eq(_count(_run(_idle_board(true), turns), "idle_unit"), 0)


# --- the dive half, with no fog at all -----------------------------------------


## A submerged submarine is unseeable whether or not the match has fog, which is
## why the analyser asks Vision rather than reading `fog_enabled`: this board has
## no commander and no fog, and the finding still has to be withheld.
func test_a_submerged_sub_is_not_fire_the_move_walked_into() -> void:
	var walk := [{"c": "move", "path": [[12, 1], [12, 2], [12, 3], [12, 4]]}]
	var seen := _run(_channel_board(false), walk)
	assert_eq(_count(seen, "walk_into_fire"), 1, "a surfaced sub covers the cell")
	assert_eq(_count(_run(_channel_board(true), walk), "walk_into_fire"), 0)


## A wounded cruiser rounding the coast into a submarine's reach. The sub's own
## shot is unaffected by diving — only being seen is — which the assertion holds
## so a withheld finding can only be the vision guard.
func _channel_board(dived: bool) -> GameState:
	var state := _bare_state(CHANNEL)
	var cruiser := _stand(state, &"cruiser", 1, Vector2i(12, 1))
	cruiser.hp = 5
	var sub := _stand(state, &"sub", 2, Vector2i(12, 8))
	sub.dived = dived
	assert_not_null(AttackRange.ready_shot(state, sub, cruiser), "a dived sub still has the shot")
	return state
