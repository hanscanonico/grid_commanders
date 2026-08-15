extends GutTest
## Which squares a mission asks the board to mark: `BattleCampaign.objective_cells`,
## the single collector the drawer is handed.
##
## `BattleCampaign` lives under `scenes/` but this entry is Node-free and pure —
## a static read over `CampaignSession` and a `GameState`, with no scene and no
## `Node` anywhere in it — so it earns `CampaignSession`'s own exception for the
## same reason that autoload does: the rules it is worth pinning are which
## objectives count, not any drawing.
##
## The rules, and each is one test below: live only, unmet only, primary and
## bonus alike, no cell twice, and nothing at all for a skirmish.

const PROBE := &"__probe_marks_campaign"

## Two cities and an HQ on one row, and team 1 already owns (0,0) — so an
## objective naming that cell is met on the opening board and one naming (1,0)
## is not.
const ROW := """
[terrain]
CCQ.
[owners]
1 0 0
2 1 0
2 2 0
[units]
1 i 3 0
2 i 1 0
"""

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


func _state() -> GameState:
	var state := GameState.create(MapData.parse(ROW, terrain_db), unit_db, chart)
	assert_not_null(state)
	return state


func _capture(cell: Vector2i, id: StringName = &"", hidden := false) -> CaptureCellObjective:
	var objective := CaptureCellObjective.new()
	objective.cell = cell
	objective.id = id
	objective.hidden = hidden
	return objective


## A campaign of one mission carrying the objectives handed over, armed on the
## session exactly as the hub arms one.
func _begin(objectives: Array, bonus: Array = []) -> void:
	var mission := MissionDefinition.new()
	mission.id = &"probe_marks"
	mission.title = "Probe"
	mission.map_path = "res://maps/first_steps.txt"
	mission.player_team = 1
	for objective: MissionObjective in objectives:
		mission.objectives.append(objective)
	for objective: MissionObjective in bonus:
		mission.bonus_objectives.append(objective)
	var campaign := CampaignDefinition.new()
	campaign.id = PROBE
	campaign.title = "Probe"
	campaign.missions.append(mission)
	CampaignSession.begin(campaign, mission, CampaignState.begin(campaign))


func test_a_skirmish_marks_nothing() -> void:
	# Nothing outside a campaign may put a mark on the board, which is what
	# leaves every non-campaign frame the one it was before this existed.
	assert_eq(BattleCampaign.objective_cells(_state()), [])


func test_ground_still_wanted_is_marked_and_ground_already_taken_is_not() -> void:
	# A ring on a square the player already holds is one they learn to ignore.
	_begin([_capture(Vector2i(0, 0)), _capture(Vector2i(1, 0))])
	assert_eq(BattleCampaign.objective_cells(_state()), [Vector2i(1, 0)])


func test_a_bonus_objective_is_marked_like_a_primary_one() -> void:
	_begin([_capture(Vector2i(1, 0))], [_capture(Vector2i(2, 0))])
	assert_eq(BattleCampaign.objective_cells(_state()), [Vector2i(1, 0), Vector2i(2, 0)])


func test_a_hidden_objective_is_no_more_marked_than_it_is_named() -> void:
	# `is_live` is the card's authority too, so the board can never point at
	# ground a mission has not admitted it wants yet.
	_begin([_capture(Vector2i(1, 0), &"the_secret", true)])
	assert_eq(BattleCampaign.objective_cells(_state()), [], "unrevealed, so unmarked")
	CampaignSession.tally.reveal(&"the_secret")
	assert_eq(BattleCampaign.objective_cells(_state()), [Vector2i(1, 0)], "revealed, so marked")


func test_two_objectives_about_one_square_mark_it_once() -> void:
	_begin([_capture(Vector2i(1, 0))], [_capture(Vector2i(1, 0))])
	assert_eq(BattleCampaign.objective_cells(_state()), [Vector2i(1, 0)])
