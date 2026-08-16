extends GutTest
## What a hub row's second line says. `row_detail` is static and takes its
## mission, the roster and the record, so the line is read without the page and
## without a profile on disk — and every part is the mission's own authored fact,
## the antagonist through the same by-side read the briefing's picture uses.

var _commanders := CommanderDB.load_default()


func _mission() -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.id = &"one"
	mission.title = "One"
	mission.location = "Ash Reach"
	mission.map_path = "res://maps/first_steps.txt"
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
