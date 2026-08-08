extends GutTest
## `MissionProgress` and the two objectives that can only be read from it: how
## long ground has been held, and how many units the side has lost.
##
## Three properties carry this file. **A hold advances on a day boundary**, never
## per command, or a mission is won by ending several turns on the same day.
## **A loss is a departure from the board**, not "started with, minus have now",
## because a unit built after a unit died leaves that subtraction unmoved. And
## both are counted for the player's **side**, so an ally's ridge and an ally's
## casualties are the mission's, exactly as every other objective reads them.
##
## The fourth is the resume: only the counters are saved, so the tally has to
## re-baseline against the board it is handed and can neither forget what it had
## counted nor count it again.

## Two properties and an HQ over open ground, two armies for the player's side to
## be split across, and a second unit for team 1 so a loss is not a rout.
const BOARD := """
[terrain]
CCQ.
....
[owners]
1 0 0
2 1 0
2 2 0
[units]
1 i 3 0
1 i 3 1
2 i 1 0
3 i 0 1
"""

const OURS := Vector2i(0, 0)
const THEIRS := Vector2i(1, 0)

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	CampaignSession.clear()


func after_each() -> void:
	CampaignSession.clear()


func _state(allies: Array = []) -> GameState:
	var state := GameState.create(MapData.parse(BOARD, terrain_db), unit_db, chart)
	assert_not_null(state)
	for team: int in allies:
		state.sides[team] = 0
	return state


## The tally over a board that has already been seen once, which is what every
## boundary but the first is.
func _tally(state: GameState) -> MissionProgress:
	var tally := MissionProgress.new()
	tally.observe(state, 1)
	return tally


## One day passing, as the tally sees it: the board settles and is observed on
## the new day.
func _next_day(state: GameState, tally: MissionProgress) -> void:
	state.day += 1
	tally.observe(state, 1)


func _profile() -> CampaignState:
	var state := CampaignState.new()
	state.campaign_id = &"probe_tally"
	state.unlocked[&"probe_one"] = true
	state.active_mission = &"probe_one"
	return state


## Through the text a profile is actually stored as, so the integers come back as
## JSON's one number type rather than as the ints they were written with.
func _stored(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


## A mission the session can be armed with: the player is team 1, and the board
## it names is only ever the one this file parses by hand.
func _mission() -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.id = &"probe_tally"
	campaign.title = "Probe"
	var mission := MissionDefinition.new()
	mission.id = &"probe_one"
	mission.title = "Probe One"
	mission.map_path = "res://maps/first_steps.txt"
	mission.player_team = 1
	campaign.missions.append(mission)
	return campaign


## A deployed mission, as the hub stages one: fresh when `resumed` is null, and
## picking up a saved tally when it is not.
func _deploy(resumed: MissionProgress = null) -> void:
	var campaign := _mission()
	CampaignSession.begin(campaign, campaign.missions[0], CampaignState.begin(campaign), resumed)


# --- holding ground ---------------------------------------------------------


func test_a_hold_advances_on_a_day_boundary_and_never_on_a_command() -> void:
	var state := _state()
	var tally := _tally(state)
	assert_eq(tally.days_held(OURS), 0, "holding it at the opening is not a day held")
	tally.observe(state, 1)
	tally.observe(state, 1)
	assert_eq(tally.days_held(OURS), 0, "and neither are two more commands on day one")
	_next_day(state, tally)
	assert_eq(tally.days_held(OURS), 1)
	_next_day(state, tally)
	assert_eq(tally.days_held(OURS), 2)


func test_a_hold_drops_to_nothing_the_moment_the_ground_changes_hands() -> void:
	var state := _state()
	var tally := _tally(state)
	_next_day(state, tally)
	_next_day(state, tally)
	assert_eq(tally.days_held(OURS), 2)
	state.set_owner(OURS, 2)
	tally.observe(state, 1)
	assert_eq(tally.days_held(OURS), 0, "a run of days is consecutive or it is nothing")
	state.set_owner(OURS, 1)
	_next_day(state, tally)
	assert_eq(tally.days_held(OURS), 1, "and taking it back starts the run again")


func test_a_hold_counts_the_ground_an_ally_is_holding() -> void:
	var state := _state([1, 3])
	state.set_owner(THEIRS, 3)
	var tally := _tally(state)
	_next_day(state, tally)
	assert_eq(tally.days_held(THEIRS), 1, "our side holds it, whichever of us took it")


func test_hold_cell_is_met_once_the_tally_reaches_the_days_it_asks_for() -> void:
	var state := _state()
	var tally := _tally(state)
	var objective := HoldCellObjective.new()
	objective.cell = OURS
	objective.days = 2
	_next_day(state, tally)
	assert_false(objective.is_met(state, 1, tally), "one day of the two")
	_next_day(state, tally)
	assert_true(objective.is_met(state, 1, tally))


func test_hold_cell_refuses_ground_no_run_of_days_could_be_held_on() -> void:
	var map := MapData.parse(BOARD, terrain_db)
	var objective := HoldCellObjective.new()
	objective.cell = Vector2i(3, 0)
	assert_ne(objective.definition_error(map, 1, unit_db), "", "plains is nobody's to hold")
	objective.cell = Vector2i(9, 9)
	assert_ne(objective.definition_error(map, 1, unit_db), "", "and that cell is off the board")
	objective.cell = OURS
	objective.days = 0
	assert_ne(
		objective.definition_error(map, 1, unit_db), "", "nor is holding it for no days a task"
	)
	objective.days = 3
	assert_eq(objective.definition_error(map, 1, unit_db), "")


# --- losing units -----------------------------------------------------------


func test_a_unit_that_leaves_the_board_is_a_loss() -> void:
	var state := _state()
	var tally := _tally(state)
	assert_eq(tally.losses(), 0)
	state.remove_unit(state.units_of(1)[0])
	tally.observe(state, 1)
	assert_eq(tally.losses(), 1)


func test_a_unit_built_after_one_died_does_not_hide_it() -> void:
	# The whole reason the tally diffs the units it saw rather than counting them:
	# both boards hold two of ours, and one of them is a different two.
	var state := _state()
	var tally := _tally(state)
	state.remove_unit(state.units_of(1)[0])
	state.units.append(Unit.create(unit_db.by_symbol("i"), 1, Vector2i(2, 1)))
	tally.observe(state, 1)
	assert_eq(tally.losses(), 1)


func test_an_allys_casualty_is_our_sides() -> void:
	var state := _state([1, 3])
	var tally := _tally(state)
	state.remove_unit(state.units_of(3)[0])
	tally.observe(state, 1)
	assert_eq(tally.losses(), 1, "a partner's column is on our side of the bill")


func test_loss_limit_fires_only_past_the_number_it_allows() -> void:
	var state := _state()
	var tally := _tally(state)
	var objective := LossLimitObjective.new()
	objective.max_losses = 1
	assert_false(objective.is_met(state, 1, tally))
	state.remove_unit(state.units_of(1)[0])
	tally.observe(state, 1)
	assert_false(objective.is_met(state, 1, tally), "one loss is the one it allows")
	state.remove_unit(state.units_of(1)[0])
	tally.observe(state, 1)
	assert_true(objective.is_met(state, 1, tally))


func test_loss_limit_refuses_a_bill_that_cannot_be_run_up() -> void:
	var map := MapData.parse(BOARD, terrain_db)
	var objective := LossLimitObjective.new()
	objective.max_losses = -1
	assert_ne(objective.definition_error(map, 1, unit_db), "")
	objective.max_losses = 0
	assert_eq(
		objective.definition_error(map, 1, unit_db),
		"",
		"losing nobody is a hard mission, not a bad one"
	)


# --- saved and resumed ------------------------------------------------------


func test_a_resumed_tally_keeps_its_counts_and_recounts_nothing() -> void:
	var state := _state()
	var tally := _tally(state)
	state.remove_unit(state.units_of(1)[0])
	tally.observe(state, 1)
	var data := _stored(CampaignSaveCodec.encode(_profile(), {"day": 4}, tally))
	assert_eq(CampaignSaveCodec.validate(data), "")
	var resumed := CampaignSaveCodec.tally_of(data)
	assert_eq(resumed.losses(), 1, "the mission opens owing what it had already lost")
	resumed.observe(state, 1)
	assert_eq(resumed.losses(), 1, "the board it resumes onto is a baseline, not a massacre")
	state.remove_unit(state.units_of(1)[0])
	resumed.observe(state, 1)
	assert_eq(resumed.losses(), 2, "and what it loses after the resume is still counted")


## The board the mission opens on is the baseline, so the very first command is
## diffed against something. Left to `decide`, that command *was* the baseline
## and whatever it cost was free.
func test_a_loss_on_the_first_command_of_a_mission_counts() -> void:
	var state := _state()
	_deploy()
	CampaignSession.open_board(state)
	state.remove_unit(state.units_of(1)[0])
	CampaignSession.decide(state)
	assert_eq(CampaignSession.tally.losses(), 1, "the first command is not a free one")


## And again after every resume, or a loss limit is spent by saving and
## reloading rather than by keeping the column alive.
func test_a_loss_on_the_first_command_after_a_resume_counts() -> void:
	var state := _state()
	var tally := _tally(state)
	state.remove_unit(state.units_of(1)[0])
	tally.observe(state, 1)
	var saved := _stored(CampaignSaveCodec.encode(_profile(), {"day": 4}, tally))
	_deploy(CampaignSaveCodec.tally_of(saved))
	assert_eq(CampaignSession.tally.losses(), 1, "the resume opens owing what it had lost")
	CampaignSession.open_board(state)
	state.remove_unit(state.units_of(1)[0])
	CampaignSession.decide(state)
	assert_eq(CampaignSession.tally.losses(), 2, "and a reload buys no casualty back")


## The other half of that rule: a retry is not a resume, and starts clean.
func test_a_retried_mission_opens_owing_nothing() -> void:
	var state := _state()
	_deploy()
	CampaignSession.open_board(state)
	assert_eq(CampaignSession.tally.losses(), 0, "nobody has spent a unit on this attempt")


func test_a_tally_is_dropped_with_the_battle_it_was_kept_for() -> void:
	var state := _state()
	var tally := _tally(state)
	state.remove_unit(state.units_of(1)[0])
	tally.observe(state, 1)
	var data := CampaignSaveCodec.encode(_profile(), {}, tally)
	assert_false(data.has("mission_progress"), "a mission nobody is in has no bookkeeping")
	assert_eq(CampaignSaveCodec.tally_of(data).losses(), 0)


func test_a_profile_written_before_the_tally_loads_without_one() -> void:
	var data := _stored(CampaignSaveCodec.encode(_profile(), {"day": 4}))
	data["version"] = 1
	assert_eq(CampaignSaveCodec.validate(data), "", "a version 1 profile is still a profile")
	assert_true(CampaignSaveCodec.tally_of(data).is_empty(), "and it was playing with no tally")


func test_a_tally_no_writer_could_have_produced_is_refused() -> void:
	var data := _stored(CampaignSaveCodec.encode(_profile(), {"day": 4}))
	data["mission_progress"] = {"losses": -1}
	assert_ne(CampaignSaveCodec.validate(data), "", "nobody has lost fewer than no units")
	data["mission_progress"] = {"held:x,y": 2}
	assert_ne(CampaignSaveCodec.validate(data), "", "and that is not a cell")
	data["mission_progress"] = {"losses": 2, "held:1,0": 3}
	assert_eq(CampaignSaveCodec.validate(data), "")
	data.erase("battle")
	assert_ne(CampaignSaveCodec.validate(data), "", "a tally without its board belongs to nothing")
