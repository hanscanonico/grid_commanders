extends GutTest
## What a board and a mission may author about the carried army, and the one
## chain the shipped content declares.
##
## `test_campaign_roster.gd` is what the army does; this is the gate `make
## campaigns` runs before it can do it. Every check here catches a slip with no
## other symptom — a slot nothing will ever stand in, a chain with a hole in it —
## because a carry slot that is never filled looks exactly like a board opening as
## authored, which is what it does 106 times out of 108.

## One carry slot for team 1, and the enemy's own row marked as well.
const RIVAL_SLOT := """
[terrain]
C...Q
.....
[owners]
1 0 0
2 4 0
[units]
1 i 0 1 ^
2 i 4 1 ^
"""


func _mission(map_path: String = CampaignFixture.MAP_PATH) -> MissionDefinition:
	var mission := CampaignFixture.capture_mission(&"probe_one")
	mission.map_path = map_path
	return mission


func _campaign(count: int = 2) -> CampaignDefinition:
	var missions: Array[MissionDefinition] = []
	for index in count:
		missions.append(CampaignFixture.capture_mission(StringName("probe_%d" % index)))
	return CampaignFixture.campaign(&"__probe_carry_campaign", missions)


func _board(text: String) -> MapData:
	return MapData.parse(text, Fixture.terrain_db())


func _slots(map: MapData) -> Array[String]:
	var symbols: Array[String] = []
	for entry: Dictionary in map.starting_units:
		if entry.carry:
			symbols.append(entry.symbol)
	return symbols


## The roster is the player's army, so a mark on anybody else's row is a slot
## nothing will ever stand in.
func test_a_carry_slot_on_another_army_is_refused() -> void:
	var error := _mission().definition_error(_board(RIVAL_SLOT), Fixture.unit_db())
	assert_string_contains(error, "is team 2's, not the player's")


func test_a_mission_that_carries_an_army_in_needs_somewhere_to_put_it() -> void:
	var mission := _mission()
	mission.carry_in = true
	var bare := _board("[terrain]\nC...Q\n[owners]\n1 0 0\n2 4 0\n")
	assert_string_contains(mission.definition_error(bare, Fixture.unit_db()), "has no carry slot")
	var slotted := _board("[terrain]\nC...Q\n.....\n[owners]\n1 0 0\n2 4 0\n[units]\n1 i 0 1 ^\n")
	assert_eq(mission.definition_error(slotted, Fixture.unit_db()), "")


func test_a_floor_no_unit_could_be_refit_to_is_refused() -> void:
	var mission := _mission()
	var map := _board("[terrain]\nC...Q\n.....\n[owners]\n1 0 0\n2 4 0\n[units]\n1 i 0 1 ^\n")
	mission.carry_floor_hp = Unit.MAX_HP + 1
	assert_string_contains(
		mission.definition_error(map, Fixture.unit_db()), "refits a carried unit"
	)
	mission.carry_floor_hp = -1
	assert_string_contains(
		mission.definition_error(map, Fixture.unit_db()), "refits a carried unit"
	)
	mission.carry_floor_hp = Unit.MAX_HP
	assert_eq(mission.definition_error(map, Fixture.unit_db()), "")


## The campaign-wide half, `ledger_error`'s shape: a mission that carries an army
## in behind one that carries none out opens with the map's own units and nothing
## to say that anything was meant to arrive.
func test_a_chain_with_a_hole_in_it_is_refused() -> void:
	var campaign := _campaign()
	campaign.missions[1].carry_in = true
	assert_string_contains(campaign.carry_error(), "carries an army in")
	campaign.missions[0].carry_out = true
	assert_eq(campaign.carry_error(), "")


## Voss's retreat, the chain this test pins: she holds the customs line and
## falls back to the causeway with the same three units. The furnace act's
## fw12 → fw18 veteran column is the other shipped chain, counted by the census
## below.
func test_the_shipped_chain_carries_the_army_it_says_it_does() -> void:
	var campaign := CampaignDB.load_default().by_id(&"the_long_front")
	assert_not_null(campaign)
	assert_eq(campaign.carry_error(), "")
	assert_true(campaign.mission(&"lf01_customs_line").carry_out)
	var causeway := campaign.mission(&"lf02_the_last_causeway")
	assert_true(causeway.carry_in)
	assert_gt(causeway.carry_floor_hp, 0, "and it declares what the retreat refits them to")
	var slots := _slots(MapData.load_from_file(causeway.map_path, Fixture.terrain_db()))
	assert_eq(slots, ["r", "t", "i"] as Array[String], "the three that came off the customs line")


## Every other shipped board carries no slot at all: nothing to fill, so nothing
## to get wrong. Two chains exist on purpose — Voss's retreat (lf01 → lf02) and
## The Furnace Winter's whole third act (fw12 → fw18), where the veteran column
## that opened the last mile marches on the furnace mission by mission.
func test_the_rest_of_the_shipped_content_carries_nothing() -> void:
	var chained := 0
	for campaign: CampaignDefinition in CampaignDB.load_default().all():
		assert_eq(campaign.carry_error(), "", "%s" % campaign.id)
		for mission: MissionDefinition in campaign.missions:
			if mission.carry_in or mission.carry_out:
				chained += 1
				continue
			var map := MapData.load_from_file(mission.map_path, Fixture.terrain_db())
			assert_eq(_slots(map), [] as Array[String], "%s/%s" % [campaign.id, mission.id])
	assert_eq(chained, 9, "the customs line and the causeway, and the furnace act's seven")
