extends GutTest
## The authoring traps `make campaigns` refuses, on fixtures rather than on
## shipped content.
##
## Each one is a slip that leaves no mark anywhere a player or an author would
## look: the mission plays, the beat speaks, the page turns, and the thing the
## file said would happen simply does not. `test_campaign_content.gd` holds the
## 108 to the same bar; this is where each check is shown to catch what it claims
## and to leave the honest shape alone.

const HELD := &"greenwater_held"
## Two seats, an HQ each and a city between them, so a board question has a home
## headquarters to ask after.
const BOARD := """
[terrain]
Q.C.Q
.....
[owners]
1 0 0
2 4 0
[units]
1 i 0 1
2 i 4 1
"""
## The same board with the player's unit named, so a `UnitReached` trigger has
## somebody to wait for.
const TAGGED_BOARD := """
[terrain]
Q.C.Q
.....
[owners]
1 0 0
2 4 0
[units]
1 i 0 1 courier
2 i 4 1
"""
## The same board with a third army on it, so felling one enemy leaves another.
const THREE_SEAT_BOARD := """
[terrain]
Q.C.Q
..Q..
.....
[owners]
1 0 0
2 4 0
3 2 1
[units]
1 i 0 2
2 i 4 2
3 i 2 2
"""


func _mission(id: StringName = &"probe_one") -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.id = id
	mission.title = String(id)
	mission.map_path = "res://maps/first_steps.txt"
	mission.player_team = 1
	return mission


func _campaign(ids: Array = [&"one", &"two"]) -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.id = &"probe"
	campaign.title = "Probe"
	for id: StringName in ids:
		campaign.missions.append(_mission(id))
	return campaign


func _condition(flag: StringName, at_least := 1, at_most := -1) -> FlagCondition:
	var condition := FlagCondition.new()
	condition.flag = flag
	condition.at_least = at_least
	condition.at_most = at_most
	return condition


## A beat on `mission` writing `flag`, waiting for whatever it is handed.
func _writes(mission: MissionDefinition, flag: StringName, trigger: MissionTrigger) -> void:
	var effect := SetFlagEffect.new()
	effect.flag = flag
	effect.value = 1
	var event := MissionEvent.new()
	event.id = &"writes_it"
	event.effects.append(effect)
	event.triggers.append(trigger)
	mission.events.append(event)


func _on_day(day: int) -> DayReachedTrigger:
	var trigger := DayReachedTrigger.new()
	trigger.day = day
	return trigger


## A beat waiting for ground the player has to take, which is the shape of a fact
## that reads two ways.
func _on_the_relay() -> CellOwnedTrigger:
	var trigger := CellOwnedTrigger.new()
	trigger.cell = Vector2i(2, 0)
	trigger.holder = CellOwnedTrigger.Holder.OURS
	return trigger


func _capture(cell: Vector2i) -> CaptureCellObjective:
	var objective := CaptureCellObjective.new()
	objective.cell = cell
	objective.text = "Take %s." % cell
	return objective


# --- a fact nothing can vary ------------------------------------------------


func test_a_fact_only_the_calendar_writes_is_refused_where_something_reads_it() -> void:
	var campaign := _campaign()
	campaign.missions[0].par_day = 5
	_writes(campaign.missions[0], HELD, _on_day(3))
	campaign.missions[1].unlock_requires = _condition(HELD)
	assert_string_contains(campaign.constant_fact_error(), "reads the same on every route")


func test_a_fact_the_board_decides_is_a_consequence() -> void:
	var campaign := _campaign()
	_writes(campaign.missions[0], HELD, _on_the_relay())
	campaign.missions[1].unlock_requires = _condition(HELD)
	assert_eq(campaign.constant_fact_error(), "")


## Past par the beat is one a player who is quick genuinely avoids, which is how
## the ledger records "was careful" rather than only "went wrong".
func test_a_beat_past_the_missions_own_par_still_varies() -> void:
	var campaign := _campaign()
	campaign.missions[0].par_day = 5
	_writes(campaign.missions[0], HELD, _on_day(7))
	campaign.missions[1].unlock_requires = _condition(HELD)
	assert_eq(campaign.constant_fact_error(), "")


## `ledger_error`'s rule at this width: a road the player may decline is the
## ordinary shape of a fact that sometimes goes unwritten.
func test_a_beat_on_a_gated_mission_varies_whatever_it_waits_for() -> void:
	var campaign := _campaign([&"one", &"two", &"three"])
	_writes(campaign.missions[0], &"first_fact", _on_the_relay())
	campaign.missions[1].unlock_requires = _condition(&"first_fact")
	campaign.missions[1].par_day = 5
	_writes(campaign.missions[1], HELD, _on_day(1))
	campaign.missions[2].unlock_requires = _condition(HELD)
	assert_eq(campaign.constant_fact_error(), "")


## A fact nobody conditions anything on is a note in the ledger, which is allowed
## to be true of every run.
func test_a_fact_nothing_reads_is_left_alone() -> void:
	var campaign := _campaign()
	campaign.missions[0].par_day = 5
	_writes(campaign.missions[0], HELD, _on_day(1))
	assert_eq(campaign.constant_fact_error(), "")


# --- a block closed by a mission not everybody plays -------------------------


func test_a_gated_mission_may_not_close_a_block_that_has_a_page() -> void:
	var campaign := _campaign()
	campaign.block_titles = ["Spring"]
	campaign.block_lengths = [2]
	var page := CampaignInterlude.new()
	page.after_block = 0
	page.title = "Spring"
	campaign.interludes.append(page)
	_writes(campaign.missions[0], HELD, _on_the_relay())
	campaign.missions[1].unlock_requires = _condition(HELD)
	assert_string_contains(campaign.block_error(), "closes block 0")


func test_a_gated_mission_inside_a_block_is_fine() -> void:
	var campaign := _campaign([&"one", &"two", &"three"])
	campaign.block_titles = ["Spring"]
	campaign.block_lengths = [3]
	var page := CampaignInterlude.new()
	page.after_block = 0
	page.title = "Spring"
	campaign.interludes.append(page)
	_writes(campaign.missions[0], HELD, _on_the_relay())
	campaign.missions[1].unlock_requires = _condition(HELD)
	assert_eq(campaign.block_error(), "")


# --- the board a mission opens on -------------------------------------------


func test_a_mission_already_won_before_the_first_command_is_refused() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(0, 0)))
	assert_string_contains(
		mission.board_error(Fixture.state(BOARD)), "already over on the board it opens on"
	)


func test_a_mission_still_to_be_played_passes() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(2, 0)))
	assert_eq(mission.board_error(Fixture.state(BOARD)), "")


## Tactical victory outranks the objective list, so taking the last enemy's home
## headquarters wins the mission with everything beside it still unticked.
func test_an_objective_beside_a_match_ending_one_is_refused() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(4, 0)))
	mission.objectives.append(_capture(Vector2i(2, 0)))
	assert_string_contains(mission.board_error(Fixture.state(BOARD)), "ends the match")


func test_a_match_ending_objective_on_its_own_is_the_mission() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(4, 0)))
	assert_eq(mission.board_error(Fixture.state(BOARD)), "")


## Felling one army of two enemies resolves nothing, so the objective beside it
## is judged exactly as it reads.
func test_a_headquarters_that_leaves_another_enemy_standing_ends_nothing() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(4, 0)))
	mission.objectives.append(_capture(Vector2i(2, 0)))
	assert_eq(mission.board_error(Fixture.state(THREE_SEAT_BOARD)), "")


# --- a landing zone the beat's own triggers pin ------------------------------


## A mission carrying one beat: a column landing on `cell`, waiting for whatever
## it is handed. The board's own units stand on row 1, so row 0 is open ground.
func _lands_on(mission: MissionDefinition, cell: Vector2i, trigger: MissionTrigger) -> void:
	var spawn := MissionSpawn.new()
	spawn.unit_type = Fixture.unit_db().by_id(&"infantry")
	spawn.cell = cell
	var effect := SpawnUnitsEffect.new()
	effect.team = 2
	effect.units.append(spawn)
	var event := MissionEvent.new()
	event.id = &"the_column"
	event.triggers.append(trigger)
	event.effects.append(effect)
	mission.events.append(event)


func _reaches(tag: StringName, cells: Array[Vector2i]) -> UnitReachedTrigger:
	var trigger := UnitReachedTrigger.new()
	trigger.tag = tag
	trigger.cells = cells
	return trigger


func _exit_zone(cells: Array[Vector2i], count: int) -> ReachCellObjective:
	var objective := ReachCellObjective.new()
	objective.cells = cells
	objective.count = count
	objective.text = "Get %d out." % count
	return objective


func _watching(objective: MissionObjective) -> ObjectiveMetTrigger:
	var trigger := ObjectiveMetTrigger.new()
	trigger.objective = objective
	return trigger


## The one square the trigger holds our courier on is the one square the column
## can never take, so the beat speaks and lands nothing.
func test_a_beat_may_not_land_on_the_square_its_own_trigger_pins() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(4, 0)))
	_lands_on(mission, Vector2i(2, 0), _reaches(&"courier", [Vector2i(2, 0)]))
	var map := MapData.parse(TAGGED_BOARD, Fixture.terrain_db())
	assert_string_contains(
		mission.definition_error(map, Fixture.unit_db()), "where its own triggers hold a unit"
	)


## A zone with slack in it pins nothing: the courier is on one of the three and
## the column takes whichever it is not.
func test_a_beat_keyed_to_a_wider_zone_may_land_inside_it() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(4, 0)))
	var zone: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	_lands_on(mission, Vector2i(2, 0), _reaches(&"courier", zone))
	var map := MapData.parse(TAGGED_BOARD, Fixture.terrain_db())
	assert_eq(mission.definition_error(map, Fixture.unit_db()), "")


## An exit zone with no slack fills every square of itself, so the bridge across
## to the objective library pins them all.
func test_a_beat_watching_a_full_exit_zone_may_not_land_in_it() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(4, 0)))
	var zone: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	_lands_on(mission, Vector2i(2, 0), _watching(_exit_zone(zone, 2)))
	var map := MapData.parse(BOARD, Fixture.terrain_db())
	assert_string_contains(
		mission.definition_error(map, Fixture.unit_db()), "where its own triggers hold a unit"
	)


## The beat this whole narrowing exists for: the reserve drops onto the depot the
## player is being sent to take, and lands whenever they have not got there yet.
## Ownership is not occupancy, so neither `CaptureCell` nor `HoldCell` pins ground.
func test_a_beat_may_land_where_an_objective_merely_sends_us() -> void:
	var mission := _mission()
	mission.objectives.append(_capture(Vector2i(2, 0)))
	_lands_on(mission, Vector2i(2, 0), _on_day(3))
	var map := MapData.parse(BOARD, Fixture.terrain_db())
	assert_eq(mission.definition_error(map, Fixture.unit_db()), "")
