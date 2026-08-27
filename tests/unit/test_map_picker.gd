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
