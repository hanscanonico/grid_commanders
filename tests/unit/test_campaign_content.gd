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


## A flag a mission reads and no mission of the campaign writes is a variant line
## nobody ever hears and a gated beat that never fires, with no other symptom.
func test_every_flag_a_campaign_reads_is_one_it_writes() -> void:
	for campaign in db.all():
		assert_eq(campaign.ledger_error(), "", "campaign '%s'" % campaign.id)


## A mission whose condition no earlier mission can satisfy is one the route walks
## past on every route through the war, with no other symptom (campaign-depth D7).
func test_every_mission_a_campaign_lists_can_be_opened() -> void:
	for campaign in db.all():
		assert_eq(campaign.route_error(), "", "campaign '%s'" % campaign.id)


func test_every_interlude_can_be_shown() -> void:
	for campaign in db.all():
		for page: CampaignInterlude in campaign.interludes:
			assert_eq(page.definition_error(commander_db), "", "campaign '%s'" % campaign.id)


## The one branch the shipped content authors, and the page it feeds: break Morn's
## vanguard in the spring and he never sends the ultimatum mission five is, so the
## route walks past it and the interlude that closes the act says which spring it
## was.
func test_the_shipped_branch_opens_and_closes_the_way_it_reads() -> void:
	var campaign := db.by_id(&"the_hollow_crown")
	assert_not_null(campaign)
	assert_has(campaign.mission(&"hc01_border_skirmish").written_flags(), &"morn_bloodied")
	var ultimatum := campaign.mission(&"hc05_the_ultimatum")
	assert_not_null(ultimatum.unlock_requires, "the ultimatum is the optional mission")
	assert_eq(ultimatum.unlock_requires.flag, &"morn_bloodied")
	assert_eq(ultimatum.unlock_requires.at_most, 0, "it opens only while the vanguard stood")
	assert_eq(campaign.closes_block(&"hc06_the_crack"), 0)
	var page := campaign.interlude_after(0)
	assert_not_null(page, "and the act it closes has a page")
	assert_has(page.read_flags(), &"morn_bloodied")


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
			assert_eq(
				mission.definition_error(map, unit_db), "", "%s/%s" % [campaign.id, mission.id]
			)


func test_every_mission_builds_the_match_it_states() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			var map := _map_of(mission)
			if map == null:
				continue
			var seats: Array[int] = mission.seats.duplicate()
			var state := GameState.create(map, unit_db, chart, {}, seats)
			# The usual cause is a starting unit standing on ground its movement
			# class cannot enter — a tank on a mountain. `create` pushes the cell
			# and the unit; naming the seating here would point at the wrong line.
			assert_not_null(
				state,
				(
					"%s/%s: the board would not build — see the pushed GameState error"
					% [campaign.id, mission.id]
				)
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


## A speaker who is not on the roster prints as a blank name beside real
## dialogue, which reads as a rendering fault rather than a typo in a data file.
func test_every_spoken_line_names_a_general_who_exists() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			assert_eq(mission.story_error(commander_db), "", "%s/%s" % [campaign.id, mission.id])


## A briefing nobody speaks is the narration the dialogue pass exists to replace.
## Counted rather than forbidden: a narrator's line is legitimate, an entire
## campaign of them is the thing that was wrong.
func test_most_of_a_campaigns_briefing_is_spoken() -> void:
	for campaign in db.all():
		var spoken := 0
		var total := 0
		for mission: MissionDefinition in campaign.missions:
			for line: MissionLine in mission.briefing + mission.victory:
				total += 1
				if not line.is_narration():
					spoken += 1
		if total == 0:
			continue
		assert_gt(
			float(spoken) / float(total),
			0.5,
			"%s: only %d of %d story lines have a speaker" % [campaign.id, spoken, total]
		)


## `DifficultyDB.by_id` falls back to Normal for an unknown id — right for a save
## naming a retired tier, silent for a mission whose author typed the name wrong.
## Thirty missions once asked for a tier that does not exist and played at Normal
## without a word, which flattened a campaign's whole difficulty curve.
func test_every_mission_asks_for_a_tier_that_exists() -> void:
	var tiers := DifficultyDB.load_default()
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			assert_eq(mission.difficulty_error(tiers), "", "%s/%s" % [campaign.id, mission.id])
