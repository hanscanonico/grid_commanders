extends GutTest
## The picker's words, which are pure functions of a board: the cell's name, the
## armies line and the facts caption. Static, like SeatStrip.normalised_sides, so
## what a player reads off the picker is checked without building the control.


func _map(path: String) -> MapData:
	return MapData.load_from_file(path, Fixture.terrain_db())


func test_the_teaching_board_wears_its_badge() -> void:
	var map := _map(MapCatalog.TUTORIAL_MAP_PATH)
	var cell_name := MapPicker.cell_name(map, false)
	assert_string_contains(cell_name, MapCatalog.display_name(map.source_path))
	assert_string_contains(cell_name, "Tutorial")
	assert_false(cell_name.ends_with("✓"), "an unselected cell wears no tick")


func test_the_selected_cell_is_ticked() -> void:
	var map := _map(MapCatalog.TUTORIAL_MAP_PATH)
	assert_true(MapPicker.cell_name(map, true).ends_with("✓"))


## A duel says nothing about its seats; a board that deals more than two says how
## many, because that is what a player scrolling the list is choosing between.
func test_only_a_board_past_a_duel_names_its_seats() -> void:
	for map in MapCatalog.ordered(Fixture.terrain_db()):
		var marked := MapPicker.cell_name(map, false).contains("· %dP" % map.player_count())
		assert_eq(marked, map.player_count() > 2, map.source_path)


## A board whose seats may close is offered as a range, floored at the fewest
## armies a match can be played with (open-seats D4).
func test_a_board_that_may_close_a_seat_reads_as_a_range() -> void:
	assert_eq(MapPicker.armies_label(2), "2 armies")
	assert_eq(MapPicker.armies_label(4), "%d–4 armies" % SeatStrip.MIN_FILLED)


func test_the_caption_quotes_the_board() -> void:
	var map := _map(MapCatalog.TUTORIAL_MAP_PATH)
	var caption := MapPicker.caption_text(map)
	assert_string_contains(caption, "%d×%d" % [map.width, map.height])
	assert_string_contains(caption, "%d PROPERTIES" % map.property_cells().size())
	assert_string_contains(caption, MapPicker.armies_label(map.player_count()).to_upper())
	assert_string_contains(caption, map.description.to_upper())
	assert_eq(caption, caption.to_upper(), "the caption is set in caps")


## Random is an action, not a selection: it draws a board from the roster the
## picker already holds. The arithmetic is static, so what it may land on is
## checked without building the grid.
func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## The board in hand is never the teaching one here, so only the pool's own
## filter can keep the tutorial out of the draw.
func test_random_never_draws_the_teaching_board() -> void:
	var maps := MapCatalog.ordered(Fixture.terrain_db())
	for s in 40:
		var index := MapPicker.random_index(maps, 1 + s % (maps.size() - 1), _rng(s))
		assert_false(
			MapCatalog.teaches(maps[index].source_path), "seed %d drew the tutorial board" % s
		)


## The same exclusion, pinned rather than sampled: on a three-board roster whose
## first is the tutorial and whose second is in hand, the third is the only legal
## draw at any seed.
func test_a_three_board_roster_leaves_one_legal_draw() -> void:
	var roster := MapCatalog.ordered(Fixture.terrain_db())
	assert_true(MapCatalog.teaches(roster[0].source_path), "the roster leads with the tutorial")
	var maps: Array[MapData] = [roster[0], roster[1], roster[2]]
	for s in 20:
		assert_eq(MapPicker.random_index(maps, 1, _rng(s)), 2, "seed %d" % s)


func test_random_never_draws_the_board_in_hand() -> void:
	var maps := MapCatalog.ordered(Fixture.terrain_db())
	for s in 40:
		var current := s % maps.size()
		assert_ne(MapPicker.random_index(maps, current, _rng(s)), current, "seed %d" % s)


func test_random_lands_on_a_board_that_exists() -> void:
	var maps := MapCatalog.ordered(Fixture.terrain_db())
	for s in 40:
		var index := MapPicker.random_index(maps, s % maps.size(), _rng(s))
		assert_between(index, 0, maps.size() - 1, "seed %d" % s)


## The pool empties on a one-board install — that board is both the tutorial and
## the one in hand — and the fall back to the whole roster is what keeps the
## press from being a refusal.
func test_a_single_board_roster_draws_that_board() -> void:
	var maps: Array[MapData] = [
		MapData.load_from_file(MapCatalog.TUTORIAL_MAP_PATH, Fixture.terrain_db())
	]
	assert_eq(MapPicker.random_index(maps, 0, _rng(1)), 0)


func test_an_empty_roster_draws_nothing() -> void:
	var maps: Array[MapData] = []
	assert_eq(MapPicker.random_index(maps, 0, _rng(1)), -1)
