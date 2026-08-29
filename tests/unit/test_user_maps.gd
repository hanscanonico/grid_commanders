extends GutTest
## The player's own boards on disk: naming them, writing them, listing them,
## reading them back and removing them.
##
## The round trip is the whole claim — a board saved here is the plain map text
## every shipped board is, so `MapData` reads it back with no idea it was drawn
## in the game. The rest is naming: a name is also a filename and a `--map=`
## argument, so what the text field accepts and what the disk gets are two
## different strings and only one of them is the board's.
##
## Every case writes into the real `user://maps`, which is where the code being
## tested looks, and `after_each` takes its own files back out again.

const BOARD := """# A board somebody drew.
[terrain]
..........
.QB....BQ.
..........
[owners]
1 1 1
1 2 1
2 7 1
2 8 1
"""

var _written: Array[String] = []


func after_each() -> void:
	for name in _written:
		UserMaps.delete(name)
	_written.clear()


func test_a_saved_board_lists_loads_and_deletes() -> void:
	assert_eq(_save("Iron Gulf", BOARD), "")
	assert_true(UserMaps.exists("iron_gulf"), "the board should be on disk")
	assert_has(UserMaps.list(), "iron_gulf")

	var map := UserMaps.load_map("iron_gulf", Fixture.terrain_db())
	assert_not_null(map, "a saved board should parse")
	if map != null:
		assert_eq(map.size(), Vector2i(10, 3))
		assert_eq(map.description, "A board somebody drew.")
		assert_eq(map.owner_at(Vector2i(8, 1)), 2)

	assert_eq(UserMaps.delete("iron_gulf"), "")
	assert_false(UserMaps.exists("iron_gulf"), "and gone again")
	assert_does_not_have(UserMaps.list(), "iron_gulf")


## A saved board is reachable by name from `--map=` and the menu, through the
## same resolver a shipped board is — which is the whole reason it is written as
## map text rather than a format of its own.
func test_a_saved_board_resolves_by_name() -> void:
	assert_eq(_save("scratch board", BOARD), "")
	assert_eq(MapCatalog.resolve("scratch_board"), UserMaps.path_for("scratch_board"))
	assert_has(MapCatalog.user_paths(), UserMaps.path_for("scratch_board"))
	assert_does_not_have(
		MapCatalog.paths(), UserMaps.path_for("scratch_board"), "and never joins the roster"
	)


func test_a_name_becomes_a_filename() -> void:
	assert_eq(UserMaps.slug("  The Iron Gulf!! "), "the_iron_gulf")
	assert_eq(UserMaps.slug("north-reach 2"), "north-reach_2")
	assert_eq(UserMaps.slug("***"), "")


func test_an_empty_name_is_refused() -> void:
	assert_ne(UserMaps.name_error("   "), "")
	assert_ne(UserMaps.name_error("!!!"), "")


func test_a_name_that_ships_with_the_game_is_refused() -> void:
	var shipped: String = MapCatalog.paths()[0].get_file().trim_suffix(".txt")
	assert_ne(UserMaps.name_error(shipped), "", "'%s' is the game's own board" % shipped)
	assert_ne(_save(shipped, BOARD), "", "and saving over it is refused too")
	assert_eq(MapCatalog.resolve(shipped), MapCatalog.paths()[0], "so the roster still wins")


func test_a_name_longer_than_the_cap_is_refused() -> void:
	assert_ne(UserMaps.name_error("x".repeat(UserMaps.MAX_NAME_LENGTH + 1)), "")
	assert_eq(UserMaps.name_error("x".repeat(UserMaps.MAX_NAME_LENGTH)), "")


func test_saving_the_same_name_twice_replaces_the_board() -> void:
	assert_eq(_save("overwrite me", BOARD), "")
	assert_eq(_save("overwrite me", BOARD.replace("A board somebody drew.", "Redrawn.")), "")
	assert_eq(UserMaps.list().count("overwrite_me"), 1, "one file, not two")
	var map := UserMaps.load_map("overwrite_me", Fixture.terrain_db())
	assert_eq(map.description if map != null else "", "Redrawn.")


func test_renaming_moves_the_board_and_refuses_to_bury_another() -> void:
	assert_eq(_save("first draft", BOARD), "")
	assert_eq(_save("keep me", BOARD), "")
	assert_ne(UserMaps.rename("first draft", "keep me"), "", "renaming onto a board is refused")
	assert_true(UserMaps.exists("first_draft"), "so neither board moved")

	_written.append("second_draft")
	assert_eq(UserMaps.rename("first draft", "second draft"), "")
	assert_false(UserMaps.exists("first_draft"))
	assert_true(UserMaps.exists("second_draft"))


func test_removing_a_board_that_is_not_there_says_so() -> void:
	assert_ne(UserMaps.delete("never_existed"), "")
	assert_ne(UserMaps.rename("never_existed", "somewhere"), "")


func _save(name: String, text: String) -> String:
	_written.append(UserMaps.slug(name))
	return UserMaps.save(name, text)
