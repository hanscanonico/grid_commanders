extends GutTest
## Reading back the match the main menu last set up (SK-13): a stored setup is a
## file a player can edit or an older version wrote, so every reading falls back
## to the menu's own default rather than trusting it.


func test_the_remembered_board_is_read_back_by_its_path() -> void:
	var path: String = MapCatalog.paths()[0]
	assert_eq(MenuSetupMemory.map_path({MenuSetupMemory.MAP_KEY: path}), path)


func test_nothing_sound_remembered_reads_as_no_board() -> void:
	assert_eq(MenuSetupMemory.map_path({}), "", "nothing remembered")
	var garbled := {MenuSetupMemory.MAP_KEY: 7}
	assert_eq(MenuSetupMemory.map_path(garbled), "", "a value that is no path")


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
