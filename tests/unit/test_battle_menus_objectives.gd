extends GutTest
## The pause menu's Objectives row: `BattleMenus.map_actions` again, on the same
## terms `test_battle_menus_briefing.gd` reads its sibling row — which rows a
## menu offers is content, and this one is a static read over `CampaignSession`.
##
## The rules, one test each: no row outside a campaign, exactly one inside one,
## a label that says which way the card currently is, and a row that survives
## a recording — the Briefing row's one gate this one deliberately does not
## share, a card on screen having to be lowerable whoever is playing the board.

const PROBE := &"__probe_objectives_campaign"

const ROW := """
[terrain]
CCQ.
[owners]
1 0 0
2 1 0
[units]
1 i 3 0
2 i 1 0
"""


func before_each() -> void:
	CampaignSession.clear()


func after_each() -> void:
	CampaignSession.clear()


func _state() -> GameState:
	var state := Fixture.state(ROW)
	assert_not_null(state)
	return state


func _begin() -> void:
	var mission := MissionDefinition.new()
	mission.id = &"probe_objectives"
	mission.title = "Probe"
	mission.map_path = "res://maps/first_steps.txt"
	mission.player_team = 1
	var campaign := CampaignDefinition.new()
	campaign.id = PROBE
	campaign.title = "Probe"
	campaign.missions.append(mission)
	CampaignSession.begin(campaign, mission, CampaignState.begin(campaign))


func _rows(game: GameState, savable := true, card_up := true) -> Array[Dictionary]:
	return BattleMenus.map_actions(game, true, savable, [], {}, null, card_up)


func _labels(rows: Array[Dictionary]) -> Array:
	var labels: Array = []
	for row: Dictionary in rows:
		if row["id"] == &"objectives":
			labels.append(row["label"])
	return labels


func test_a_skirmish_offers_no_objectives_row() -> void:
	assert_true(_labels(_rows(_state())).is_empty(), "a skirmish has no card to lower")


func test_a_mission_offers_exactly_one_objectives_row() -> void:
	_begin()
	var ids: Array = _rows(_state()).map(func(row: Dictionary) -> StringName: return row["id"])
	assert_eq(ids.count(&"objectives"), 1, "one Objectives row")
	assert_eq(ids.find(&"objectives"), ids.find(&"briefing") + 1, "sits after Briefing")


func test_the_row_says_which_way_the_card_is() -> void:
	_begin()
	assert_eq(_labels(_rows(_state(), true, true)), ["Objectives: On"])
	assert_eq(_labels(_rows(_state(), true, false)), ["Objectives: Off"])


func test_a_recording_still_offers_the_row() -> void:
	_begin()
	assert_eq(_labels(_rows(_state(), false)).size(), 1, "a watched card is still lowerable")
