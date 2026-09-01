extends GutTest
## What a hub row's second line says. `row_detail` is static and takes its
## mission, the roster and the record, so the line is read without the page and
## without a profile on disk — and every part is the mission's own authored fact,
## the antagonist through the same by-side read the briefing's picture uses.

var _commanders := Fixture.commander_db()


func _mission() -> MissionDefinition:
	var mission := CampaignFixture.mission(&"one")
	mission.location = "Ash Reach"
	mission.ai_teams = [2]
	mission.commanders = {2: &"radek_morn"}
	mission.par_day = 12
	return mission


func test_the_line_names_the_ground_the_foe_the_par_and_the_best() -> void:
	var line := CampaignHubPanel.row_detail(
		_mission(), _commanders, CampaignState.MissionRecord.new(2, 9)
	)
	assert_string_contains(line, "ASH REACH", "the location leads the line")
	assert_string_contains(line, "VS RADEK MORN", "the first hostile seat's commander")
	assert_string_contains(line, "PAR 12", "the day the mission is rated on")
	assert_string_contains(line, "BEST 9", "the day this player already reached")


func test_an_unrated_mission_says_no_par() -> void:
	var mission := _mission()
	mission.par_day = 0
	var line := CampaignHubPanel.row_detail(mission, _commanders, null)
	assert_false(line.contains("PAR"), "no par day, no par")


func test_an_unplayed_mission_says_no_best() -> void:
	var line := CampaignHubPanel.row_detail(_mission(), _commanders, null)
	assert_false(line.contains("BEST"), "no record, no best day")
	assert_string_contains(line, "ASH REACH", "the rest of the line still reads")


func test_an_ally_is_never_the_face_the_row_is_set_against() -> void:
	var mission := _mission()
	mission.sides = {1: 1, 2: 1}
	var line := CampaignHubPanel.row_detail(mission, _commanders, null)
	assert_false(line.contains("VS"), "a seat standing with the player is no antagonist")


## The briefing's own side of the picture: the general the player commands as,
## and whoever the mission seats beside them. Read by the same side grouping the
## antagonist is, so the two cards can never name the same seat.
func _four_seat_mission() -> MissionDefinition:
	var mission := _mission()
	mission.ai_teams = [2, 3]
	mission.commanders = {1: &"mara_voss", 2: &"radek_morn", 3: &"iona_vance"}
	mission.sides = {1: 0, 2: 1, 3: 0}
	return mission


func test_the_protagonist_is_the_players_seat() -> void:
	var you := CampaignHubPanel.protagonist(_four_seat_mission(), _commanders)
	assert_eq(you.id, &"mara_voss", "the commander seated on player_team")


func test_the_allies_are_the_seats_standing_with_the_player() -> void:
	var allies := CampaignHubPanel.allies(_four_seat_mission(), _commanders)
	assert_eq(allies.size(), 1, "one seat shares the player's side")
	assert_eq(allies[0].id, &"iona_vance", "the seat on the player's side")
	var line := CampaignHubPanel.row_detail(_four_seat_mission(), _commanders, null)
	assert_string_contains(line, "VS RADEK MORN", "and the foe stays the seat against them")


func test_a_two_seat_mission_has_no_allies() -> void:
	assert_true(
		CampaignHubPanel.allies(_mission(), _commanders).is_empty(), "nobody stands with you"
	)
	var grouped := _mission()
	grouped.sides = {1: 0, 2: 1}
	assert_true(CampaignHubPanel.allies(grouped, _commanders).is_empty(), "grouped or not")


## Three blocks of two, so the route can stand in the first, the middle or past
## the end and the answer differs at each.
func _war() -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.id = &"war"
	campaign.block_titles = ["Ferrow", "Vale", "Morn"]
	campaign.block_lengths = [2, 2, 2]
	for index in 6:
		var mission := MissionDefinition.new()
		mission.id = StringName("m%d" % index)
		mission.title = "Mission %d" % index
		campaign.missions.append(mission)
	return campaign


func _progress(open: Array[StringName]) -> CampaignState:
	var state := CampaignState.new()
	state.campaign_id = &"war"
	for id in open:
		state.unlocked[id] = true
	return state


func test_a_fresh_war_expands_its_first_block_only() -> void:
	var expanded := CampaignHubPanel.expanded_blocks(_war(), _progress([&"m0"]))
	assert_eq(expanded.size(), 1, "one block dealt in full")
	assert_true(expanded.get(0, false), "the block the route opens on")


func test_a_war_with_nothing_unlocked_still_expands_the_first_block() -> void:
	var expanded := CampaignHubPanel.expanded_blocks(_war(), _progress([]))
	assert_true(expanded.get(0, false), "a fresh profile is never all-collapsed")


func test_a_route_in_the_second_block_expands_it_and_everything_behind() -> void:
	var expanded := CampaignHubPanel.expanded_blocks(
		_war(), _progress([&"m0", &"m1", &"m2", &"m3"])
	)
	assert_true(expanded.get(0, false), "a cleared block stays open")
	assert_true(expanded.get(1, false), "the block the route stands in")
	assert_false(expanded.get(2, false), "ground nobody has reached collapses")


func test_a_finished_war_expands_every_block() -> void:
	var open: Array[StringName] = [&"m0", &"m1", &"m2", &"m3", &"m4", &"m5"]
	var expanded := CampaignHubPanel.expanded_blocks(_war(), _progress(open))
	assert_eq(expanded.size(), 3, "nothing is left to collapse")


## The hub side of `--unlock-missions`: every block is dealt, because every row
## in it is one the developer may press.
func test_the_unlock_override_deals_the_whole_war() -> void:
	var progress := _progress([])
	progress.unlock_all = true
	assert_eq(CampaignHubPanel.expanded_blocks(_war(), progress).size(), 3)
	assert_true(MenuCampaignFlow.unlocks_all(PackedStringArray([MenuCampaignFlow.UNLOCK_ARG])))
	assert_false(MenuCampaignFlow.unlocks_all(PackedStringArray(["--fog"])), "and only on request")


## A war rated out of different numbers of stars: one mission out of one, one out
## of seven. The cell has to be the war's widest, or a row's subtitle is cut at a
## different column from its neighbour's.
func _rated_war() -> CampaignDefinition:
	var campaign := _war()
	campaign.missions[3].par_day = 6
	for index in 5:
		campaign.missions[3].bonus_objectives.append(DayDeadlineObjective.new())
	return campaign


func test_the_star_cell_is_the_widest_mission_in_the_war() -> void:
	assert_eq(CampaignHubPanel.star_span(_rated_war()), 7, "one star, par, and five bonuses")


func test_a_war_rated_out_of_one_asks_for_one_star() -> void:
	assert_eq(CampaignHubPanel.star_span(_war()), 1, "finishing is every mission's own star")


func test_a_war_with_no_missions_asks_for_none() -> void:
	var campaign := CampaignDefinition.new()
	assert_eq(CampaignHubPanel.star_span(campaign), 0, "no rows, no cell")
