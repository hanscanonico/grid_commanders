extends GutTest
## The Balance Lab's match engine: determinism, the caps, and the day-cap
## tiebreak that turns an unfinished match into a scored one.
##
## Determinism is the property every number the Lab publishes rests on — a
## tuning change has to be attributable to the change and never to noise — so it
## is pinned here rather than assumed from "the RNG is seeded".

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart

## Two mirrored armies with a base each and room to fight: long enough to build,
## trade and capture, small enough to play a few dozen times in a test.
const BOARD := """
[terrain]
QB......
........
..F..F..
........
......BQ
[owners]
1 0 0
1 1 0
2 7 4
2 6 4
[units]
1 i 1 1
1 t 2 1
2 i 6 3
2 t 5 3
"""

## A board nothing can happen on: a sea channel no ground unit crosses, and a
## fighter neither side can shoot (a fighter hits only air, and nothing here
## shoots air). All that happens over twenty days is the fighter burning fuel —
## 5 of its 99 a turn, so the twentieth start-of-turn tick strands it. That tick
## runs inside the previous side's EndTurnCommand, which is the seam these two
## tests are about.
const STRANDED_BOARD := """
[terrain]
..SS..
..SS..
[units]
1 i 0 0
1 f 0 1
2 i 5 0
"""

## The same board with red's infantry gone, so the stranded fighter is red's last
## unit and the tick that takes it also ends the match.
const ROUTED_BOARD := """
[terrain]
..SS..
..SS..
[units]
1 f 0 1
2 i 5 0
"""


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _setup(seed_val: int, days: int = 8) -> BalanceMatchEngine.Setup:
	var setup := BalanceMatchEngine.Setup.new()
	setup.map = MapData.parse(BOARD, terrain_db)
	setup.unit_db = unit_db
	setup.chart = chart
	setup.seed_val = seed_val
	setup.days_cap = days
	setup.tiers = {1: &"normal", 2: &"normal"}
	setup.planners = {1: AIController.new(unit_db), 2: AIController.new(unit_db)}
	return setup


## Timeline rows minus the one wall-clock column, which measures how long the
## planner thought and so cannot repeat. Everything else must.
func _comparable(rows: Array[Dictionary]) -> Array:
	var stripped: Array = []
	for row in rows:
		var copy := row.duplicate()
		for column in BalanceMatchRecorder.NONDETERMINISTIC_COLUMNS:
			copy.erase(column)
		stripped.append(copy)
	return stripped


# --- determinism ---------------------------------------------------------------


func test_the_same_spec_replays_identically() -> void:
	var first := BalanceMatchEngine.play(_setup(4242))
	var second := BalanceMatchEngine.play(_setup(4242))
	assert_eq(first.winner, second.winner, "same seed, same winner")
	assert_eq(first.day_ended, second.day_ended)
	assert_eq(first.commands, second.commands, "same seed, same command count")
	assert_eq(first.termination, second.termination)
	assert_eq(
		first.state.units_of(1).size() + first.state.units_of(2).size(),
		second.state.units_of(1).size() + second.state.units_of(2).size()
	)


func test_the_timeline_replays_byte_for_byte() -> void:
	var first := BalanceMatchRecorder.new()
	var second := BalanceMatchRecorder.new()
	BalanceMatchEngine.play(_setup(99), first)
	BalanceMatchEngine.play(_setup(99), second)
	assert_gt(first.rows().size(), 4, "the fixture should play several turns")
	assert_eq(
		_comparable(first.rows()),
		_comparable(second.rows()),
		"every timeline column but planning_ms is a pure function of the spec"
	)
	assert_eq(first.command_log(), second.command_log(), "and so is the command log")


## The engine can only seed the match RNG *after* GameState.create, because
## create is what builds the state — and it runs the opening side's day-1 tick
## inside itself. That ordering is exact only while create draws nothing: a draw
## taken there comes off the constructor's random stream, so it would differ run
## to run and no seed could pin it. Combat is the sim's one consumer today, and
## this is what says so out loud rather than leaving it to be rediscovered by a
## golden that stopped reproducing.
func test_building_a_board_draws_nothing_from_the_match_rng() -> void:
	var state := GameState.create(MapData.parse(BOARD, terrain_db), unit_db, chart)
	var untouched := RandomNumberGenerator.new()
	untouched.seed = state.rng.seed
	assert_eq(
		state.rng.state,
		untouched.state,
		"create() must leave the RNG where a fresh one on the same seed sits"
	)


func test_a_different_seed_is_a_different_match() -> void:
	# Not a guarantee about *which* differs — only that the seed reaches the sim
	# at all, which is what a stuck or ignored seed would break.
	var log_a := BalanceMatchRecorder.new()
	var log_b := BalanceMatchRecorder.new()
	BalanceMatchEngine.play(_setup(1), log_a)
	BalanceMatchEngine.play(_setup(2), log_b)
	assert_ne(log_a.command_log(), log_b.command_log(), "the seed must reach combat luck")


# --- the harness's own guarantees ----------------------------------------------


func test_a_match_refuses_one_controller_shared_between_teams() -> void:
	var setup := _setup(42)
	setup.planners[2] = setup.planners[1]
	var outcome := BalanceMatchEngine.play(setup)
	assert_eq(
		outcome.termination,
		"invalid_planners",
		"each side owns its controller state, just as it does in the live scene"
	)


func test_a_match_refuses_a_seat_with_no_planner_of_its_own() -> void:
	for missing: int in [1, 2]:
		var setup := _setup(42)
		setup.planners.erase(missing)
		var outcome := BalanceMatchEngine.play(setup)
		assert_eq(
			outcome.termination,
			"invalid_planners",
			"team %d has no controller, so there is no match to play" % missing
		)
		assert_null(outcome.state, "a refused match never built a board")


func test_the_planner_never_proposes_an_illegal_command() -> void:
	for seed_val in [7, 21, 404]:
		var outcome := BalanceMatchEngine.play(_setup(seed_val))
		assert_eq(outcome.rejected, 0, "seed %d: the AI and the rules must agree" % seed_val)
		assert_false(outcome.cap_stall, "seed %d: the match must resolve" % seed_val)
		assert_eq(outcome.turn_cap_hits, 0, "seed %d: no turn should overstay" % seed_val)


func test_the_telemetry_reconciles_against_the_board_it_describes() -> void:
	for seed_val in [11, 55, 900]:
		var recorder := BalanceMatchRecorder.new()
		var outcome := BalanceMatchEngine.play(_setup(seed_val), recorder)
		assert_eq(
			recorder.reconcile(outcome.state, outcome.starting_units),
			"",
			"seed %d: the timeline must add up to the final board" % seed_val
		)
		assert_eq(recorder.unattributed(), 0, "seed %d: every removal is explained" % seed_val)


func test_one_recorder_carries_a_batch_and_reconciles_each_match_apart() -> void:
	var recorder := BalanceMatchRecorder.new()
	for seed_val in [3, 4]:
		var outcome := BalanceMatchEngine.play(_setup(seed_val), recorder)
		assert_eq(recorder.reconcile(outcome.state, outcome.starting_units), "")
	var ids: Dictionary = {}
	for row in recorder.rows():
		ids[row["match_id"]] = true
	assert_gt(recorder.rows().size(), 0)
	assert_eq(ids.size(), 2, "two seeds, two derived ids — rows stay joinable to their match")


func test_every_played_turn_gets_exactly_one_row_per_side() -> void:
	var recorder := BalanceMatchRecorder.new()
	var outcome := BalanceMatchEngine.play(_setup(1234), recorder)
	var seen: Dictionary = {}
	for row in recorder.rows():
		var key := "%d/%d" % [row["day"], row["team"]]
		assert_false(seen.has(key), "day %s appears twice" % key)
		seen[key] = true
		var played: bool = int(row["commands"]) > 0
		var carries_a_death: bool = row["killed"] != "" or row["lost"] != ""
		assert_true(
			played or carries_a_death,
			"a filed row is a turn that was played, or the tick that ended the match in one"
		)
	assert_true(outcome.day_ended >= 1)


## The day the first unit leaves the board, from a timeline. 0 if none does.
static func _day_of_first_loss(rows: Array[Dictionary]) -> int:
	for row in rows:
		if row["lost"] != "":
			return int(row["day"])
	return 0


func test_a_unit_stranded_in_the_final_tick_reaches_the_census() -> void:
	# The day cap falls on the turn the tick just opened, so nobody plays it. The
	# recorder must still file that row: the loss is real, and losing it would fail
	# a correct match's reconciliation and abort the whole batch.
	#
	# The dry day is measured rather than assumed. Fuel is spent on movement as
	# well as upkeep, so how long the tank lasts is how far the planner chooses to
	# fly — its business, not this test's. Capping the match one day short of it is
	# what puts the death in a turn nobody plays.
	var probe := BalanceMatchRecorder.new()
	var probe_setup := _setup(17, 25)
	probe_setup.map = MapData.parse(STRANDED_BOARD, terrain_db)
	BalanceMatchEngine.play(probe_setup, probe)
	var dry_day := _day_of_first_loss(probe.rows())
	assert_gt(dry_day, 1, "the fighter has nowhere to refuel and must fall out of the sky")

	var setup := _setup(17, dry_day - 1)
	setup.map = MapData.parse(STRANDED_BOARD, terrain_db)
	var recorder := BalanceMatchRecorder.new()
	var outcome := BalanceMatchEngine.play(setup, recorder)
	assert_eq(outcome.termination, "day_cap")
	assert_eq(outcome.state.units_of(1).size(), 1, "the fighter ran its tank dry on the last tick")
	assert_eq(
		recorder.reconcile(outcome.state, outcome.starting_units),
		"",
		"the timeline must still add up to the final board"
	)
	var last: Dictionary = recorder.rows()[recorder.rows().size() - 1]
	assert_eq(int(last["day"]), dry_day, "the turn the cap cut off")
	assert_eq(int(last["team"]), 1)
	assert_eq(int(last["commands"]), 0, "nobody got to play it")
	assert_eq(last["lost"], "fighter", "and it still reports what the tick took")


func test_the_tick_that_routs_a_side_reaches_the_census_too() -> void:
	# The same seam reached by the other exit: the stranded unit was the side's
	# last, so the match ends on the tick rather than on the cap.
	var setup := _setup(17, 25)
	setup.map = MapData.parse(ROUTED_BOARD, terrain_db)
	var recorder := BalanceMatchRecorder.new()
	var outcome := BalanceMatchEngine.play(setup, recorder)
	assert_eq(outcome.termination, "rout")
	assert_eq(outcome.winner, 2, "red has nothing left to play with")
	assert_eq(recorder.reconcile(outcome.state, outcome.starting_units), "")
	var last: Dictionary = recorder.rows()[recorder.rows().size() - 1]
	assert_eq(int(last["team"]), 1)
	assert_eq(last["lost"], "fighter")


# --- scoring -------------------------------------------------------------------


func test_a_day_cap_match_is_scored_on_properties_then_units_then_funds() -> void:
	var state := GameState.create(MapData.parse(BOARD, terrain_db), unit_db, chart)
	# create() runs the opening side's income tick and only its own, so red is up
	# a turn's funds before anyone has moved. Level that first: this test is about
	# the ranking, not about who ticked.
	state.funds[2] = state.funds[1]
	assert_eq(BalanceMatchEngine.tiebreak(state), 0, "a symmetric board opens level")
	state.funds[1] += 1
	assert_eq(BalanceMatchEngine.tiebreak(state), 1, "funds break a total tie")
	state.units.erase(state.units_of(2)[0])
	assert_eq(BalanceMatchEngine.tiebreak(state), 1, "and surviving units outrank funds")
	state.funds[1] = state.funds[2]
	state.units.erase(state.units_of(1)[0])
	state.units.erase(state.units_of(1)[0])
	assert_eq(BalanceMatchEngine.tiebreak(state), 2, "units decide when funds are level")
	# The base red opened owning: handing it over puts blue ahead on properties,
	# which outranks the units red still has.
	state.set_owner(Vector2i(1, 0), 2)
	state.units.append(Unit.create(unit_db.by_symbol("i"), 1, Vector2i(3, 1)))
	state.units.append(Unit.create(unit_db.by_symbol("i"), 1, Vector2i(4, 1)))
	assert_eq(BalanceMatchEngine.tiebreak(state), 2, "properties rank first of all")


## The two decided endings are told apart by what the loop *saw*, not by what the
## final board holds: since elimination (four-players plan D3) an HQ capture takes
## its owner's units off the board with it, so "the loser still has units" stopped
## distinguishing them. An unfinished match answers the same either way.
func test_termination_names_how_the_match_ended() -> void:
	var state := GameState.create(MapData.parse(BOARD, terrain_db), unit_db, chart)
	assert_eq(BalanceMatchEngine.termination(state, false, false), "day_cap")
	assert_eq(BalanceMatchEngine.termination(state, true, false), "command_cap")
	state.winner = 1
	assert_eq(
		BalanceMatchEngine.termination(state, false, true), "hq", "a capture took the army out"
	)
	assert_eq(BalanceMatchEngine.termination(state, false, false), "rout", "nothing captured an HQ")
	# And the board being swept clear no longer decides it either way round.
	for unit in state.units_of(2):
		state.units.erase(unit)
	assert_eq(BalanceMatchEngine.termination(state, false, true), "hq")
	assert_eq(BalanceMatchEngine.termination(state, false, false), "rout")


func test_a_short_day_cap_stops_the_match_there() -> void:
	var outcome := BalanceMatchEngine.play(_setup(5, 3))
	assert_eq(outcome.termination, "day_cap")
	assert_lt(outcome.day_ended, 6, "the cap should bind well before the fixture resolves")


## The match-level net is the per-turn cap times the turns the day cap allows, so
## it moves with the run's horizon and the board's roster — the two things a
## preset changes, and the two the flat 3 000 it replaced could not see.
func test_the_command_ceiling_is_the_turn_cap_over_every_turn_the_day_cap_allows() -> void:
	var per_turn := BalanceMatchEngine.MAX_COMMANDS_PER_TURN + 1
	assert_eq(BalanceMatchEngine.command_ceiling(20, 2), per_turn * 2 * 21)
	assert_gt(
		BalanceMatchEngine.command_ceiling(100, 2),
		BalanceMatchEngine.command_ceiling(20, 2),
		"a longer horizon earns a higher ceiling"
	)
	assert_gt(
		BalanceMatchEngine.command_ceiling(20, 4),
		BalanceMatchEngine.command_ceiling(20, 2),
		"four armies take four turns a day"
	)


## The measurement the shape exists for. Twelve of the arena campaign's 23 682
## matches hit the old flat 3 000; replayed with room, every one ran to the day
## cap instead, the longest at 5 226 commands — a 76-unit army mopping up on
## `arsenal`. A ceiling that cannot clear that number truncates honest play and
## fails the run for it, which is what this pins.
func test_the_ceiling_clears_the_longest_match_the_arena_has_measured() -> void:
	assert_gt(BalanceMatchEngine.command_ceiling(ArenaPools.DAYS, 2), 5226)


## 0 means "derive", which is what every preset wants; an override is for a tool
## measuring the cap itself, and it still binds.
func test_a_match_derives_its_own_ceiling_unless_one_is_forced_on_it() -> void:
	var outcome := BalanceMatchEngine.play(_setup(5, 3))
	assert_false(outcome.cap_stall, "a three-day match is nowhere near its own ceiling")
	var forced := _setup(5, 3)
	forced.command_cap = 5
	var cut := BalanceMatchEngine.play(forced)
	assert_true(cut.cap_stall, "an override binds")
	assert_eq(cut.commands, 5)
	assert_eq(cut.termination, "command_cap")
