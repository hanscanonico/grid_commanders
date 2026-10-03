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


## The seats' generals come back by seat, and an id the roster does not ship or a
## general a second seat also claims is dropped — that seat plays with none.
func test_remembered_generals_drop_a_stranger_and_a_duplicate() -> void:
	var db := CommanderDB.load_default()
	var stored := {"1": "alina_ward", "2": "no_such_general", "3": "alina_ward", "4": "gideon_holt"}
	var read := MenuSetupMemory.generals({MenuSetupMemory.GENERALS_KEY: stored}, db)
	assert_eq(read, {1: &"alina_ward", 4: &"gideon_holt"})


func test_generals_fall_back_to_none_on_anything_malformed() -> void:
	var db := CommanderDB.load_default()
	assert_eq(MenuSetupMemory.generals({}, db), {}, "nothing remembered")
	var garbled := {MenuSetupMemory.GENERALS_KEY: ["alina_ward"]}
	assert_eq(MenuSetupMemory.generals(garbled, db), {}, "a list is not a seat table")
	var bad_seat := {MenuSetupMemory.GENERALS_KEY: {"one": "alina_ward", "2": 7}}
	assert_eq(
		MenuSetupMemory.generals(bad_seat, db), {}, "neither entry names a seat and a general"
	)
