extends GutTest
## Reading back the match the main menu last set up (SK-13): a stored setup is a
## file a player can edit or an older version wrote, so every reading falls back
## to the menu's own default rather than trusting it.


func test_the_remembered_board_is_found_on_the_shelf_by_its_path() -> void:
	var maps := MapCatalog.ordered(Fixture.terrain_db())
	var last := maps.size() - 1
	var setup := {MenuSetupMemory.MAP_KEY: maps[last].source_path}
	assert_eq(MenuSetupMemory.map_index(setup, maps), last)


func test_a_board_no_longer_on_the_shelf_keeps_the_default() -> void:
	var maps := MapCatalog.ordered(Fixture.terrain_db())
	assert_eq(MenuSetupMemory.map_index({}, maps), -1, "nothing remembered")
	var gone := {MenuSetupMemory.MAP_KEY: "user://maps/deleted.txt"}
	assert_eq(MenuSetupMemory.map_index(gone, maps), -1, "a deleted board")
	var garbled := {MenuSetupMemory.MAP_KEY: 7}
	assert_eq(MenuSetupMemory.map_index(garbled, maps), -1, "a value that is no path")


func test_fog_and_the_table_fall_back_on_anything_malformed() -> void:
	assert_false(MenuSetupMemory.fog({}), "fog starts off")
	assert_true(MenuSetupMemory.fog({MenuSetupMemory.FOG_KEY: true}))
	assert_false(MenuSetupMemory.fog({MenuSetupMemory.FOG_KEY: "yes"}))
	assert_eq(MenuSetupMemory.table({MenuSetupMemory.TABLE_KEY: [1, 2]}), {})
	var garbled_seats := {"who": "human,cpu", "sides": [0, 1], "tiers": []}
	assert_eq(MenuSetupMemory.table({MenuSetupMemory.TABLE_KEY: garbled_seats}), {}, "seats")
	var garbled_sides := {"who": [0, 1], "sides": [0, {}], "tiers": []}
	assert_eq(MenuSetupMemory.table({MenuSetupMemory.TABLE_KEY: garbled_sides}), {}, "sides")
	var kept := {"who": [0, 1], "sides": [0, 1], "tiers": ["normal", "hard"]}
	assert_eq(MenuSetupMemory.table({MenuSetupMemory.TABLE_KEY: kept}), kept, "a sound table")
