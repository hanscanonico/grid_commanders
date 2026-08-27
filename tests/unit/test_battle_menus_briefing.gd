extends GutTest
## The pause menu's Briefing row and the words behind it: `BattleMenus.map_actions`
## and `BattleCampaign.briefing_lines`.
##
## Both live under `scenes/` and both are Node-free and pure — which rows a menu
## offers is content, and the lines are a static read over `CampaignSession` — so
## they earn the same exception `test_objective_marks.gd` and `test_unit_pricing.gd`
## already take.
##
## The rules, one test each: nothing to re-read outside a campaign, one row inside
## one, no row over a recording, and a variant briefing read against the ledger
## rather than printed whole.

const PROBE := &"__probe_briefing_campaign"
const OATH := &"held_the_bridge"

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

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	CampaignSession.clear()


func after_each() -> void:
	CampaignSession.clear()


func _state() -> GameState:
	var state := GameState.create(MapData.parse(ROW, terrain_db), unit_db, chart)
	assert_not_null(state)
	return state


func _line(text: String, requires: FlagCondition = null) -> MissionLine:
	var line := MissionLine.of(&"", text)
	line.requires = requires
	return line


func _at_least(flag: StringName, value: int) -> FlagCondition:
	var condition := FlagCondition.new()
	condition.flag = flag
	condition.at_least = value
	return condition


## A campaign of one mission carrying the briefing handed over, armed on the
## session exactly as the hub arms one.
func _begin(briefing: Array[MissionLine], ledger_flag := 0) -> void:
	var mission := MissionDefinition.new()
	mission.id = &"probe_briefing"
	mission.title = "Probe"
	mission.map_path = "res://maps/first_steps.txt"
	mission.player_team = 1
	mission.briefing = briefing
	var campaign := CampaignDefinition.new()
	campaign.id = PROBE
	campaign.title = "Probe"
	campaign.missions.append(mission)
	var ledger := CampaignState.begin(campaign)
	if ledger_flag != 0:
		ledger.flags[OATH] = ledger_flag
	CampaignSession.begin(campaign, mission, ledger)


func _row_ids(game: GameState, savable := true) -> Array:
	var ids: Array = []
	for action: Dictionary in BattleMenus.map_actions(game, true, savable):
		ids.append(action["id"])
	return ids


func test_a_skirmish_offers_no_briefing_row() -> void:
	assert_false(_row_ids(_state()).has(&"briefing"), "skirmish has nothing to re-read")


func test_a_mission_offers_exactly_one_briefing_row() -> void:
	_begin([_line("Hold the bridge.")] as Array[MissionLine])
	var ids := _row_ids(_state())
	assert_eq(ids.count(&"briefing"), 1, "one Briefing row")
	assert_eq(ids.find(&"briefing"), ids.find(&"commanders") + 1, "sits after Commanders")


func test_a_recording_offers_no_briefing_row() -> void:
	_begin([_line("Hold the bridge.")] as Array[MissionLine])
	assert_false(_row_ids(_state(), false).has(&"briefing"), "a replay re-reads nothing")


func test_a_skirmish_has_no_briefing_lines() -> void:
	assert_eq(BattleCampaign.briefing_lines(), [] as Array[MissionLine])


func test_a_mission_says_its_briefing_again() -> void:
	_begin([_line("Hold the bridge."), _line("Then burn it.")] as Array[MissionLine])
	var lines := BattleCampaign.briefing_lines()
	assert_eq(lines.size(), 2)
	assert_eq(lines[0].text, "Hold the bridge.")
	assert_eq(lines[1].text, "Then burn it.")


func test_a_variant_briefing_reads_the_ledger() -> void:
	var briefing: Array[MissionLine] = [
		_line("Hold the bridge."),
		_line("You held the last one.", _at_least(OATH, 1)),
	]
	_begin(briefing)
	assert_eq(BattleCampaign.briefing_lines().size(), 1, "the gated line is not said")
	CampaignSession.clear()
	_begin(briefing, 1)
	assert_eq(BattleCampaign.briefing_lines().size(), 2, "and is once the war says so")
