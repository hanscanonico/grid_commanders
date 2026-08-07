extends GutTest
## The shipped campaigns, held to the bar a playable mission has to clear.
##
## `tools/check_campaigns.gd` is the authoring guard a content author runs; this
## is the same bar as a merge gate, so a mission that names a cell which is not a
## property cannot reach `main` even if nobody ran the tool. It walks real
## content rather than a fixture on purpose: the failure this catches is a
## typo'd coordinate, and a fixture cannot have one.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB
var db: CampaignDB


func before_all() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()
	db = CampaignDB.load_default()


func _map_of(mission: MissionDefinition) -> MapData:
	return MapData.parse(FileAccess.get_file_as_string(mission.map_path), terrain_db)


func test_at_least_one_campaign_ships() -> void:
	assert_gt(db.size(), 0, "data/campaigns/ holds no campaign")


func test_every_campaign_is_structurally_sound() -> void:
	for campaign in db.all():
		assert_eq(campaign.definition_error(), "", "campaign '%s'" % campaign.id)


func test_every_mission_names_a_board_that_parses() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			var where := "%s/%s" % [campaign.id, mission.id]
			assert_true(
				FileAccess.file_exists(mission.map_path), "%s: %s" % [where, mission.map_path]
			)
			assert_not_null(_map_of(mission), "%s: board does not parse" % where)


## The coordinate check. A capture objective on plains is a mission that can
## never be finished, and it looks exactly like a correct one in the file.
func test_every_mission_can_be_won_and_lost_on_its_own_board() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			var map := _map_of(mission)
			if map == null:
				continue
			assert_eq(mission.definition_error(map), "", "%s/%s" % [campaign.id, mission.id])


func test_every_mission_builds_the_match_it_states() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			var map := _map_of(mission)
			if map == null:
				continue
			var seats: Array[int] = mission.seats.duplicate()
			var state := GameState.create(map, unit_db, chart, {}, seats)
			assert_not_null(
				state,
				"%s/%s: the board refuses seating %s" % [campaign.id, mission.id, mission.seats]
			)


func test_every_seat_is_cast_from_the_shipped_roster() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			for team: int in mission.commanders:
				var id: StringName = mission.commanders[team]
				assert_true(
					commander_db.has(id),
					"%s/%s seats '%s', who is not on the roster" % [campaign.id, mission.id, id]
				)


## A deadline in `objectives` is a mission won by running out of time. The two
## lists read in opposite directions, so the mistake is invisible in the file
## and total on the board.
func test_no_deadline_is_filed_as_a_goal() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			for objective: MissionObjective in mission.objectives:
				assert_false(
					objective is DayDeadlineObjective,
					"%s/%s files a deadline as a goal" % [campaign.id, mission.id]
				)


func test_every_mission_that_speaks_says_something_when_it_is_won() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			if mission.briefing.is_empty():
				continue
			assert_false(
				mission.victory.is_empty(),
				"%s/%s briefs the player and then says nothing" % [campaign.id, mission.id]
			)


## Par has to be reachable inside the clock, or the speed star is unearnable.
func test_par_falls_inside_the_missions_own_deadline() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			if mission.par_day <= 0:
				continue
			for failure: MissionObjective in mission.failures:
				if failure is DayDeadlineObjective:
					assert_lte(
						mission.par_day,
						(failure as DayDeadlineObjective).last_day,
						(
							"%s/%s: par %d is past its own deadline"
							% [campaign.id, mission.id, mission.par_day]
						)
					)
