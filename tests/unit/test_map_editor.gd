extends GutTest
## The editor's pure answers: which cell a press lands on, where a board sits in
## a frame too small for it, which order the brushes come in, and what a new
## board's dialog will let an author ask for. Statics over a draft and a rect,
## like MapThumbnail's region choice, so the arithmetic the page is laid out by
## is checked without building the page.


func _draft(width: int, height: int) -> MapDocument:
	return MapDocument.blank(width, height, Fixture.terrain_db())


func test_a_press_lands_on_the_cell_under_it() -> void:
	assert_eq(EditorBoard.cell_from(Vector2(0, 0), Vector2.ZERO, 16.0), Vector2i.ZERO)
	assert_eq(EditorBoard.cell_from(Vector2(31, 17), Vector2.ZERO, 16.0), Vector2i(1, 1))
	# The board scrolled right by a tile: the same point is one cell earlier.
	assert_eq(EditorBoard.cell_from(Vector2(31, 17), Vector2(16, 0), 16.0), Vector2i(0, 1))


func test_a_press_off_the_board_reads_as_a_cell_off_the_board() -> void:
	assert_eq(EditorBoard.cell_from(Vector2(-1, -1), Vector2.ZERO, 16.0), Vector2i(-1, -1))


func test_a_board_that_fits_its_frame_is_centred() -> void:
	assert_eq(EditorBoard.scroll_axis(100.0, 60.0, 0.0, 20.0, -40.0), 20.0)


func test_a_board_larger_than_its_frame_holds_its_scroll() -> void:
	assert_eq(EditorBoard.scroll_axis(100.0, 300.0, 100.0, 20.0, -40.0), -40.0)


func test_the_scroll_follows_a_cursor_off_either_edge() -> void:
	# Past the right edge: scrolled exactly enough to show the focused cell.
	assert_eq(EditorBoard.scroll_axis(100.0, 300.0, 200.0, 20.0, 0.0), -120.0)
	# Past the left edge, coming back: the cell's own offset, and no further.
	assert_eq(EditorBoard.scroll_axis(100.0, 300.0, 40.0, 20.0, -120.0), -40.0)


func test_the_scroll_never_leaves_the_board_edge_inside_the_frame() -> void:
	assert_eq(EditorBoard.scroll_axis(100.0, 300.0, 280.0, 20.0, 0.0), -200.0)


func test_a_board_opens_at_the_rung_a_match_opens_at() -> void:
	var rungs := BattleZoom.rungs_for(0.8)
	assert_eq(rungs[EditorBoard.opening_rung(rungs)], BattleZoom.DEFAULT_ZOOM)


func test_a_board_too_small_to_frame_opens_on_the_whole_board_view() -> void:
	var rungs := BattleZoom.rungs_for(4.5)
	assert_eq(EditorBoard.opening_rung(rungs), 0)


func test_the_preview_is_the_board_the_parser_makes_of_the_draft() -> void:
	var db := Fixture.terrain_db()
	var doc := _draft(4, 3)
	var sea := db.by_id(&"sea")
	assert_true(doc.paint(Vector2i(1, 1), sea.id))
	var preview := EditorBoard.preview_of(doc, db)
	assert_eq(preview.size(), Vector2i(4, 3))
	assert_eq(preview.terrain_at(Vector2i(1, 1)).id, sea.id)
	assert_eq(preview.terrain_at(Vector2i(0, 0)).id, db.ground().id)


func test_the_palette_offers_the_ground_before_the_properties() -> void:
	var db := Fixture.terrain_db()
	var brushes := EditorPalette.ordering(db)
	assert_eq(brushes.size(), db.size())
	var seen_property := false
	var previous := ""
	for terrain in brushes:
		if terrain.is_property and not seen_property:
			seen_property = true
			previous = ""
		assert_eq(terrain.is_property, seen_property, "%s is out of its group" % terrain.id)
		assert_true(previous <= terrain.display_name, "%s is out of order" % terrain.id)
		previous = terrain.display_name
	assert_true(seen_property, "the palette offers no property to paint")


func test_a_new_board_is_never_smaller_or_wider_than_the_editor_offers() -> void:
	assert_eq(
		EditorNewMapPanel.clamp_side(EditorNewMapPanel.MIN_SIDE - 1), EditorNewMapPanel.MIN_SIDE
	)
	assert_eq(
		EditorNewMapPanel.clamp_side(EditorNewMapPanel.MAX_SIDE + 1), EditorNewMapPanel.MAX_SIDE
	)
	assert_eq(EditorNewMapPanel.clamp_side(20), 20)


func test_a_new_board_plans_for_between_two_and_four_armies() -> void:
	assert_eq(EditorNewMapPanel.clamp_seats(1), MapData.DEFAULT_TEAMS.size())
	assert_eq(EditorNewMapPanel.clamp_seats(9), MapData.PLAYER_TEAMS.size())
	assert_eq(EditorNewMapPanel.clamp_seats(3), 3)


func test_the_default_board_is_one_the_dialog_can_offer() -> void:
	var wanted := EditorNewMapPanel.DEFAULT_SIZE
	assert_eq(EditorNewMapPanel.clamp_side(wanted.x), wanted.x)
	assert_eq(EditorNewMapPanel.clamp_side(wanted.y), wanted.y)
