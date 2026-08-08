extends GutTest
## What each objective says about its own progress — the line the in-battle card
## prints beside its tick.
##
## Its own suite because a readout is what the panel would otherwise work out for
## itself off the objective's `@export`s, which is the second opinion
## `MissionObjective.readout` exists to prevent: these pin that the words come
## from the condition that is being measured, and that a condition with nothing
## countable says nothing rather than something empty-looking.

## Two cities and an HQ on one row, one unit a side. Enough ground for a property
## count, a zone and a hold to have somewhere to be.
const ROW := """
[terrain]
CCQ.
[owners]
1 0 0
2 1 0
2 2 0
[units]
1 i 3 0 courier
2 i 1 0
"""

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state() -> GameState:
	var state := GameState.create(MapData.parse(ROW, terrain_db), unit_db, chart)
	assert_not_null(state)
	return state


func test_a_deadline_counts_the_day_out_of_its_last_one() -> void:
	var deadline := DayDeadlineObjective.new()
	deadline.last_day = 8
	var state := _state()
	state.day = 4
	assert_eq(deadline.readout(state, 1, null), "DAY 4/8")


func test_survival_counts_the_day_toward_the_one_it_ends_on() -> void:
	var survive := SurviveUntilDayObjective.new()
	survive.day = 7
	var state := _state()
	state.day = 3
	assert_eq(survive.readout(state, 1, null), "DAY 3/7")


func test_a_property_count_reads_the_sides_holdings_against_the_target() -> void:
	var own := OwnPropertiesObjective.new()
	own.count = 3
	assert_eq(own.readout(_state(), 1, null), "1/3")


func test_a_zone_reads_how_many_of_ours_have_arrived() -> void:
	var reach := ReachCellObjective.new()
	reach.cells = [Vector2i(3, 0), Vector2i(2, 0)]
	reach.count = 2
	assert_eq(reach.readout(_state(), 1, null), "1/2")


func test_a_hold_reads_the_days_the_tally_counted() -> void:
	var hold := HoldCellObjective.new()
	hold.cell = Vector2i(0, 0)
	hold.days = 3
	var state := _state()
	var progress := MissionProgress.new()
	progress.observe(state, 1)
	state.day += 1
	progress.observe(state, 1)
	assert_eq(hold.readout(state, 1, progress), "1/3 DAYS")


func test_a_loss_limit_reads_the_bill_against_what_it_allows() -> void:
	var limit := LossLimitObjective.new()
	limit.max_losses = 2
	var state := _state()
	var progress := MissionProgress.new()
	progress.observe(state, 1)
	state.units.erase(MissionObjective.tagged_unit(state, &"courier"))
	progress.observe(state, 1)
	assert_eq(limit.readout(state, 1, progress), "1/2 LOST")


func test_a_condition_with_nothing_to_count_says_nothing() -> void:
	var state := _state()
	for objective: MissionObjective in [
		CaptureCellObjective.new(),
		DefeatTeamObjective.new(),
		AllySurvivesObjective.new(),
		DestroyUnitObjective.new(),
		ProtectUnitObjective.new(),
	]:
		assert_eq(objective.readout(state, 1, null), "", "%s reads out nothing" % objective)
