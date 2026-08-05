extends GutTest
## Name to board: the half of MapCatalog that answers a `--map=` flag.
##
## `resolve()` is the single answer to "which board is `ironworks`?", and it has
## to be, because a watched match replays a headless row and the two resolve the
## same spec by different routes — a second opinion here would put the watched
## match on another board and read as a fidelity bug in the sim.
##
## The rest of the class is already pinned where it is used: `paths()` and
## `ordered()` by tests/unit/test_maps.gd (which lints the roster it discovers),
## `teaches()` by the same file, `display_name()` by test_save_summary.gd. What
## had nothing was the resolver and the name list a failed flag prints.

## A fixture named after a shipped board, staged by the precedence test and
## removed again. Nothing else may be left behind in maps/.
const SHADOW_PATH := "res://maps/fixtures/ironworks.txt"


func after_each() -> void:
	_remove_shadow()


func test_a_bare_name_and_a_file_name_are_the_same_board() -> void:
	assert_eq(MapCatalog.resolve("ironworks"), "res://maps/ironworks.txt")
	assert_eq(MapCatalog.resolve("ironworks.txt"), "res://maps/ironworks.txt")
	assert_eq(MapCatalog.resolve("  ironworks  "), "res://maps/ironworks.txt")


func test_the_tutorial_board_resolves_to_the_one_path_that_names_it() -> void:
	assert_eq(MapCatalog.resolve("boot_camp"), MapCatalog.TUTORIAL_MAP_PATH)


## Fixtures live a directory down so they stay out of the menu, the map lint and
## the per-map soak — and stay reachable by name from the offline tools.
func test_a_fixture_resolves_though_it_is_not_on_the_roster() -> void:
	assert_eq(MapCatalog.resolve("clash"), "res://maps/fixtures/clash.txt")
	assert_does_not_have(MapCatalog.paths(), "res://maps/fixtures/clash.txt")


## A name nothing answers to is "" rather than a path that does not exist, which
## is what lets a caller print the list instead of failing to open a file.
func test_a_name_nothing_answers_to_is_empty() -> void:
	for name: String in ["ironworkz", "fixtures", "maps/ironworks", "", "   ", ".txt"]:
		assert_eq(MapCatalog.resolve(name), "", "'%s' names no board" % name)


## The roster is the game and the fixtures are instruments, so a clash goes to
## the shipped board. No shipped name collides with a fixture today, which is
## exactly why the rule cannot be observed without staging one: this test writes
## the collision, asks, and removes it again.
func test_a_shipped_board_beats_a_fixture_of_the_same_name() -> void:
	var file := FileAccess.open(SHADOW_PATH, FileAccess.WRITE)
	assert_not_null(file, "staging the clash needs maps/fixtures to be writable")
	if file == null:
		return
	file.store_string("[terrain]\n..\n..\n")
	file.close()
	assert_true(FileAccess.file_exists(SHADOW_PATH), "the clash is staged")
	assert_eq(MapCatalog.resolve("ironworks"), "res://maps/ironworks.txt")
	_remove_shadow()
	assert_false(FileAccess.file_exists(SHADOW_PATH), "and taken down again")


## What a tool prints when a flag names nothing: every name the resolver answers
## to, and nothing it does not.
func test_every_listed_name_resolves_and_every_resolvable_name_is_listed() -> void:
	var names := MapCatalog.resolvable_names()
	assert_gt(names.size(), 0)
	for name in names:
		assert_ne(MapCatalog.resolve(name), "", "'%s' is listed but resolves to nothing" % name)
	for path in MapCatalog.paths():
		assert_has(names, path.get_file().trim_suffix(".txt"), "%s is missing from the list" % path)
	assert_has(names, "clash", "the fixtures are listed too")


## Shipped roster first, then fixtures — the order a reader scans for the board
## they meant, with the ones they can actually pick from the menu at the top.
func test_the_roster_is_listed_before_the_fixtures() -> void:
	var names := MapCatalog.resolvable_names()
	assert_eq(names.size(), MapCatalog.paths().size() + _fixture_count())
	for i in MapCatalog.paths().size():
		assert_eq(
			MapCatalog.resolve(names[i]).get_base_dir(),
			MapCatalog.MAPS_DIR,
			"'%s' is out of the roster's half of the list" % names[i]
		)


func _fixture_count() -> int:
	var count := 0
	for file in DirAccess.get_files_at(MapCatalog.FIXTURES_DIR):
		if file.trim_suffix(".remap").ends_with(".txt"):
			count += 1
	return count


func _remove_shadow() -> void:
	if FileAccess.file_exists(SHADOW_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SHADOW_PATH))
