extends GutTest
## What a mission calls the units its board names (`MissionDefinition.unit_names`),
## and the refusals that keep a name keyed to a unit the mission really deals.

## A board with the player's infantry carrying a tag, so a name has a unit to key on.
const NAMED_BOARD := """
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


func _named(names: Dictionary) -> String:
	var mission := CampaignFixture.capture_mission(&"probe_one", Vector2i(2, 0))
	mission.unit_names = names
	var map := MapData.parse(NAMED_BOARD, Fixture.terrain_db())
	return mission.definition_error(map, Fixture.unit_db())


func test_a_name_for_a_unit_the_board_deals_is_fine() -> void:
	assert_eq(_named({&"courier": "the courier"}), "")


func test_a_name_for_a_tag_nobody_carries_is_refused() -> void:
	assert_string_contains(_named({&"currier": "the courier"}), "names unit 'currier'")


func test_an_empty_name_is_refused() -> void:
	assert_string_contains(_named({&"courier": " "}), "an empty name")


func test_a_mission_answers_the_name_it_gives() -> void:
	var mission := CampaignFixture.mission(&"probe_one")
	mission.unit_names = {&"courier": "the courier"}
	assert_eq(mission.unit_name(&"courier"), "the courier")
	assert_eq(mission.unit_name(&"stranger"), "", "an unnamed tag has no name")
	assert_eq(mission.unit_name(&""), "", "and neither does an untagged unit")
