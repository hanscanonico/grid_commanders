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
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()
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


## A fact every route writes the same way is not a consequence: the condition
## reading it is not a choice, so one side of a variant pair is content nobody
## can reach and the other is a line that would have played anyway.
func test_every_fact_a_campaign_conditions_content_on_can_read_two_ways() -> void:
	for campaign in db.all():
		assert_eq(campaign.constant_fact_error(), "", "campaign '%s'" % campaign.id)


## An interlude is shown by winning the one mission that closes its block, so a
## gate on that mission takes the page with it for everyone the route sends past.
func test_no_gated_mission_closes_a_block() -> void:
	for campaign in db.all():
		assert_eq(campaign.block_error(), "", "campaign '%s'" % campaign.id)


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


## The bars a mission clears by being content somebody meant to write rather than
## by being playable: D9's own clause (a mission that scripts nothing plays
## perfectly well), a briefing with nothing to say when it is won, a seat cast
## off the roster, and the deadline pair — one filed as a goal, and a par past
## the mission's own clock.
func test_every_mission_is_content_somebody_authored() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			assert_eq(mission.content_error(commander_db), "", "%s/%s" % [campaign.id, mission.id])


## Three questions only the board a mission opens on can answer: whether it is
## already over before the first command, whether an objective standing beside a
## match-ending one is ever judged, and whether a visible goal was met at deploy —
## fw11 shipped with "keep our own headquarters/base" on ground the player
## already owned.
func test_every_mission_is_still_being_played_on_the_board_it_opens_on() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			var map := _map_of(mission)
			if map == null:
				continue
			var seats: Array[int] = mission.seats.duplicate()
			var state := GameState.create(map, unit_db, chart, {}, seats)
			if state == null:
				continue
			assert_eq(mission.board_error(state), "", "%s/%s" % [campaign.id, mission.id])


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
		assert_eq(campaign.speech_error(), "", "campaign '%s'" % campaign.id)


## `DifficultyDB.by_id` falls back to Normal for an unknown id — right for a save
## naming a retired tier, silent for a mission whose author typed the name wrong.
## Thirty missions once asked for a tier that does not exist and played at Normal
## without a word, which flattened a campaign's whole difficulty curve.
func test_every_mission_asks_for_a_tier_that_exists() -> void:
	var tiers := DifficultyDB.load_default()
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			assert_eq(mission.difficulty_error(tiers), "", "%s/%s" % [campaign.id, mission.id])
