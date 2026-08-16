extends GutTest
## How often the production planner actually buys something, turn after turn.
##
## The replay analyser reports the failure this pins as `hoarding`: an army
## sitting on tens of thousands with a free base and nothing on the board to show
## for it. The banking rule is what produces it — the wait is board-wide, it
## re-arms every turn against an ever-costlier target, and a duplicate already
## fielded pushes the rank far enough that one more place of improvement looks
## worth another twelve thousand.
##
## So this suite is a characterisation, not a judgement: the shipped cadence is
## recorded exactly as it is, and each of the three banking dials is then shown
## to break the silence. When a tier seats one of them the golden below moves,
## and moving it is the deliberate act this file exists to make visible.

## Causeway-shaped: two bases and a port for the expensive want to hide behind,
## five cities to pay for it (8 properties, 8000 a turn), and empty ground to
## park what gets built so a facility is never blocked.
const BOARD := """
[terrain]
BBP.........
CCCCC.......
............
............
[owners]
1 0 0
1 1 0
1 2 0
1 0 1
1 1 1
1 2 1
1 3 1
1 4 1
[units]
1 i 6 2
1 i 7 2
1 i 8 2
"""

## Long enough to hold the analyser's own window — its findings name runs of
## three to six turns.
const TURNS := 8

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


## Plays TURNS turns of production alone: credit the day's income, then buy until
## the planner stops, parking each purchase on empty ground so the facility it
## came out of is free again next turn.
##
## Returns the builds each turn, the smallest treasury the planner was ever asked
## from, and the largest it ever reached.
func _cadence(profile: AIProfile) -> Dictionary:
	var map := MapData.parse(BOARD, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	var team := state.current_team
	assert_eq(TurnRules.income_for(state, team), 8000, "the board's income")
	var context := AIPlanningContext.new(unit_db)
	var planner := AIProductionPlanner.new(profile)
	var builds: Array[int] = []
	var parked := 0
	var lowest := -1
	var peak := 0
	state.funds[team] = 0
	for turn in TURNS:
		state.funds[team] += TurnRules.income_for(state, team)
		lowest = state.funds[team] if lowest < 0 else mini(lowest, state.funds[team])
		peak = maxi(peak, state.funds[team])
		var bought := 0
		while true:
			context.begin(state)
			var command := planner.plan(context)
			if command == null:
				break
			var build := command as BuildCommand
			assert_eq(build.validate(state), "", "the planner offered a build the rules refuse")
			build.apply(state)
			state.unit_at(build.cell).cell = Vector2i(parked % 12, 2 + parked / 12)
			parked += 1
			bought += 1
		builds.append(bought)
	return {"builds": builds, "lowest_funds": lowest, "peak_funds": peak}


## The longest run of turns that bought nothing.
static func _longest_silence(builds: Array) -> int:
	var longest := 0
	var run := 0
	for bought in builds:
		run = 0 if bought > 0 else run + 1
		longest = maxi(longest, run)
	return longest


## The shipped profile with one dial turned on. Duplicated first: a loaded
## resource is one shared instance per path, so writing to `load_default()` would
## retune the tier every other suite reads.
func _shipped_plus(dial: String, value: Variant) -> AIProfile:
	var profile: AIProfile = AIProfile.load_default().duplicate()
	profile.set(dial, value)
	return profile


## The golden. It records the freeze rather than approving of it: eight turns,
## three of them buying, three silent in a row, and a treasury that reaches
## 32 000 with both bases empty and an infantry priced at 1000. Seating a banking
## dial on a tier moves these numbers, and moving them deliberately is the point.
func test_the_shipped_profile_freezes_production_for_three_turns() -> void:
	var cadence := _cadence(AIProfile.load_default())
	assert_eq(
		cadence["builds"],
		[0, 1, 0, 0, 0, 1, 0, 1] as Array[int],
		"the shipped build cadence over %d turns" % TURNS
	)
	assert_eq(_longest_silence(cadence["builds"]), 3, "the shipped freeze")
	assert_eq(cadence["peak_funds"], 32000, "what the treasury reaches while it waits")


## The ceiling: past a few turns of income banked, the wait stops and the money is
## spent on the best thing a facility can reach today.
func test_the_spend_ceiling_ends_the_freeze() -> void:
	var cadence := _cadence(_shipped_plus("spend_ceiling_turns", 2.0))
	assert_lt(_longest_silence(cadence["builds"]), 3, "a run of three idle turns survived the dial")
	assert_gte(cadence["lowest_funds"], 1000, "the planner was never too poor to buy anything")


## The scope: a base waits only for something a base could build, so what the
## port is saving for no longer silences it.
func test_per_facility_banking_ends_the_freeze() -> void:
	var cadence := _cadence(_shipped_plus("bank_scope", AIProfile.BANK_SCOPE_FACILITY))
	assert_lt(_longest_silence(cadence["builds"]), 3, "a run of three idle turns survived the dial")
	assert_gte(cadence["lowest_funds"], 1000, "the planner was never too poor to buy anything")


## The margin: one place of improvement is inside the noise a single duplicate
## makes, so it no longer justifies banking.
func test_the_rank_margin_ends_the_freeze() -> void:
	var cadence := _cadence(_shipped_plus("bank_rank_margin", 4))
	assert_lt(_longest_silence(cadence["builds"]), 3, "a run of three idle turns survived the dial")
	assert_gte(cadence["lowest_funds"], 1000, "the planner was never too poor to buy anything")


## D1's inert half, read as cadence: all three dials at their shipped values plan
## the same eight turns as the shipped profile, purchase for purchase.
func test_the_dials_at_their_inert_values_keep_the_shipped_cadence() -> void:
	var shipped := AIProfile.load_default()
	assert_eq(shipped.spend_ceiling_turns, 0.0, "the ceiling ships inert")
	assert_eq(shipped.bank_scope, AIProfile.BANK_SCOPE_BOARD, "the scope ships board-wide")
	assert_eq(shipped.bank_rank_margin, 0, "the margin ships inert")
	var zeroed: AIProfile = AIProfile.load_default().duplicate()
	zeroed.spend_ceiling_turns = 0.0
	zeroed.bank_scope = AIProfile.BANK_SCOPE_BOARD
	zeroed.bank_rank_margin = 0
	assert_eq(_cadence(zeroed)["builds"], _cadence(shipped)["builds"])
