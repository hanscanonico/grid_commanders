extends GutTest
## MapDocument, the editable draft a board is authored in.
##
## Everything here rests on one claim: a draft's `to_text` is a map file, not
## something like one. So the suite's centre is the round trip — write a
## document, parse the text, and compare the board that comes back — and its
## strongest case runs it over every shipped board, which is the only corpus
## that exercises the grammar's corners (an omitted `[units]`, a `# symmetric`
## claim, a `# grouping` claim, a named unit, a carry slot).

var terrain_db: TerrainDB
var unit_db: UnitDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()


func test_a_blank_document_is_open_ground() -> void:
	var doc := MapDocument.blank(4, 3, terrain_db)
	assert_eq(doc.size(), Vector2i(4, 3), "a blank draft is the size it was asked for")
	assert_eq(
		doc.terrain_at(Vector2i(3, 2)).id,
		TerrainDB.GROUND_ID,
		"every cell of a blank draft is the ground a property is drawn over"
	)
	assert_null(doc.terrain_at(Vector2i(4, 0)), "nothing stands outside the board")
	assert_eq(doc.player_count(), 2, "a board that names nobody still seats a duel")


func test_a_written_document_parses_back_as_the_board_it_drew() -> void:
	var doc := MapDocument.blank(3, 2, terrain_db)
	doc.description = "a scratch board"
	assert_true(doc.paint(Vector2i(0, 0), &"hq"), "the HQ goes down")
	assert_true(doc.paint(Vector2i(2, 1), &"base"), "and a base opposite it")
	assert_true(doc.set_owner(Vector2i(0, 0), 1), "seat 1 holds its HQ")
	assert_true(doc.set_owner(Vector2i(2, 1), 3), "seat 3 holds the base")
	assert_true(
		doc.place_unit(Vector2i(1, 0), unit_db.by_id(&"infantry"), 1), "with one rifleman out"
	)

	var map := MapData.parse(doc.to_text(), terrain_db)
	assert_not_null(map, "the text a draft writes is a map file")
	assert_eq(map.description, "a scratch board", "the pitch is the first comment line")
	assert_eq(map.terrain_at(Vector2i(0, 0)).id, &"hq", "the HQ came back")
	assert_eq(map.owner_at(Vector2i(2, 1)), 3, "and so did who holds the base")
	assert_eq(map.teams(), [1, 2, 3], "the roster is read off the seats the draft named")
	assert_eq(doc.teams(), map.teams(), "and the draft said the same before it was saved")
	assert_eq(map.starting_units.size(), 1, "one unit was placed")
	assert_eq(map.starting_units[0].symbol, "i", "and it is the rifleman")


func test_every_shipped_board_survives_a_round_trip() -> void:
	for path in _every_board():
		var original := MapData.load_from_file(path, terrain_db)
		assert_not_null(original, "%s parses" % path)
		if original == null:
			continue
		var draft := MapDocument.from_map(original, terrain_db)
		var reparsed := MapData.parse(draft.to_text(), terrain_db)
		assert_not_null(reparsed, "%s survives a draft and a save" % path)
		if reparsed == null:
			continue
		assert_eq(
			_board_digest(reparsed), _board_digest(original), "%s comes back unchanged" % path
		)
		assert_eq(draft.teams(), original.teams(), "%s seats the same armies as a draft" % path)


func test_ownership_clears_when_a_cell_stops_being_a_property() -> void:
	var doc := MapDocument.blank(2, 1, terrain_db)
	doc.paint(Vector2i(0, 0), &"city")
	doc.set_owner(Vector2i(0, 0), 2)
	doc.paint(Vector2i(0, 0), &"woods")
	assert_eq(
		doc.owner_at(Vector2i(0, 0)),
		MapData.NEUTRAL,
		"a team owns a building, not the ground it stood on"
	)
	assert_false(
		doc.set_owner(Vector2i(1, 0), 1), "and nobody can be handed a cell with no building on it"
	)
	assert_push_error("is not a property, cannot be owned")


func test_a_building_painted_for_a_seat_is_that_seats() -> void:
	var doc := MapDocument.blank(2, 1, terrain_db)
	assert_true(doc.paint(Vector2i(0, 0), &"hq", 2), "the HQ goes down for seat 2")
	assert_eq(doc.owner_at(Vector2i(0, 0)), 2, "and belongs to it at once")
	doc.paint(Vector2i(0, 0), &"city", MapData.NEUTRAL)
	assert_eq(
		doc.owner_at(Vector2i(0, 0)), 2, "naming nobody leaves the cell's ownership as it stands"
	)
	doc.paint(Vector2i(1, 0), &"woods", 1)
	assert_eq(doc.owner_at(Vector2i(1, 0)), MapData.NEUTRAL, "and open ground is owned by nobody")


## An army has one home. Painting a second headquarters for a seat moves the one
## it had rather than adding to it, so an author who wanted their HQ elsewhere
## does not have to erase the old one to be allowed to save.
func test_an_army_keeps_exactly_one_headquarters() -> void:
	var doc := MapDocument.blank(4, 1, terrain_db)
	assert_true(doc.paint(Vector2i(0, 0), &"hq", 1), "seat 1 takes a home")
	assert_true(doc.paint(Vector2i(1, 0), &"hq", 1), "and then wants it one cell over")
	assert_eq(doc.headquarters_of(1), [Vector2i(1, 0)] as Array[Vector2i], "one home, the new one")
	assert_eq(
		doc.terrain_at(Vector2i(0, 0)).id, TerrainDB.GROUND_ID, "the old cell is bare ground again"
	)
	assert_eq(doc.owner_at(Vector2i(0, 0)), MapData.NEUTRAL, "owned by nobody")

	assert_true(doc.paint(Vector2i(3, 0), &"hq", 2), "seat 2 takes a home of its own")
	assert_eq(doc.headquarters_of(1), [Vector2i(1, 0)] as Array[Vector2i], "seat 1 keeps its own")
	assert_eq(doc.headquarters_of(2), [Vector2i(3, 0)] as Array[Vector2i], "beside seat 2's")
	assert_eq(
		MapValidator.draft_errors(doc, terrain_db).filter(
			func(text: String) -> bool: return text.contains("headquarters")
		),
		[] as Array[String],
		"and the validator has nothing to say about either army's home"
	)


## The owner brush hands over a building that is already painted, so it is the
## second way to give an army a second home and answers the rule the same way.
func test_handing_an_army_a_second_headquarters_moves_its_home() -> void:
	var doc := MapDocument.blank(2, 1, terrain_db)
	doc.paint(Vector2i(0, 0), &"hq", 1)
	doc.paint(Vector2i(1, 0), &"hq", 2)
	assert_true(doc.set_owner(Vector2i(1, 0), 1), "seat 1 takes seat 2's home")
	assert_eq(doc.headquarters_of(1), [Vector2i(1, 0)] as Array[Vector2i], "and gives up its own")
	assert_eq(doc.terrain_at(Vector2i(0, 0)).id, TerrainDB.GROUND_ID, "which is ground again")


func test_resizing_keeps_the_overlap_and_drops_what_falls_off() -> void:
	var doc := MapDocument.blank(3, 3, terrain_db)
	doc.paint(Vector2i(0, 0), &"mountain")
	doc.paint(Vector2i(2, 2), &"city")
	doc.set_owner(Vector2i(2, 2), 1)
	doc.place_unit(Vector2i(2, 0), unit_db.by_id(&"tank"), 2)

	doc.resize(2, 2)
	assert_eq(doc.terrain_at(Vector2i(0, 0)).id, &"mountain", "the overlap is kept as drawn")
	assert_eq(doc.terrain_at(Vector2i(1, 1)).id, TerrainDB.GROUND_ID, "the crop drops the corner")
	assert_eq(doc.owner_at(Vector2i(2, 2)), MapData.NEUTRAL, "with the ownership on it")
	assert_true(doc.unit_at(Vector2i(2, 0)).is_empty(), "and the unit that stood off the board")

	doc.resize(4, 4)
	assert_eq(doc.terrain_at(Vector2i(0, 0)).id, &"mountain", "growing back keeps what is drawn")
	assert_eq(doc.terrain_at(Vector2i(3, 3)).id, TerrainDB.GROUND_ID, "and opens ground beside it")
	assert_not_null(MapData.parse(doc.to_text(), terrain_db), "a cropped draft is still a map file")


func test_a_cell_holds_one_unit() -> void:
	var doc := MapDocument.blank(2, 1, terrain_db)
	doc.place_unit(Vector2i(0, 0), unit_db.by_id(&"infantry"), 1)
	doc.place_unit(Vector2i(0, 0), unit_db.by_id(&"tank"), 2)
	assert_eq(doc.unit_at(Vector2i(0, 0)).symbol, "t", "the second unit replaces the first")
	assert_eq(doc.unit_at(Vector2i(0, 0)).team, 2, "team and all")
	doc.remove_unit(Vector2i(0, 0))
	assert_true(doc.unit_at(Vector2i(0, 0)).is_empty(), "and the cell empties again")
	assert_eq(
		MapData.parse(doc.to_text(), terrain_db).starting_units.size(),
		0,
		"a draft with no army writes no [units] section"
	)


func test_clearing_a_cell_empties_all_three_layers() -> void:
	var doc := MapDocument.blank(2, 1, terrain_db)
	doc.paint(Vector2i(0, 0), &"hq", 1)
	doc.place_unit(Vector2i(0, 0), unit_db.by_id(&"infantry"), 1)

	assert_true(doc.clear(Vector2i(0, 0)), "the cell had something to take away")
	assert_eq(
		doc.terrain_at(Vector2i(0, 0)).id, TerrainDB.GROUND_ID, "and is the ground a blank board is"
	)
	assert_eq(doc.owner_at(Vector2i(0, 0)), MapData.NEUTRAL, "owned by nobody")
	assert_true(doc.unit_at(Vector2i(0, 0)).is_empty(), "with nothing standing on it")
	assert_false(doc.clear(Vector2i(0, 0)), "clearing open ground changes nothing")


func test_a_copied_draft_is_its_own_board() -> void:
	var doc := MapDocument.blank(2, 1, terrain_db)
	doc.map_name = "scratch"
	doc.paint(Vector2i(0, 0), &"city", 1)
	doc.place_unit(Vector2i(1, 0), unit_db.by_id(&"tank"), 2)

	var copy := doc.copy()
	assert_eq(copy.to_text(), doc.to_text(), "a copy is the board it was taken of")
	assert_eq(copy.map_name, "scratch", "and saves to the same file")
	doc.clear(Vector2i(0, 0))
	doc.remove_unit(Vector2i(1, 0))
	assert_eq(copy.terrain_at(Vector2i(0, 0)).id, &"city", "painting on one leaves the other")
	assert_eq(copy.unit_at(Vector2i(1, 0)).symbol, "t", "army and all")


func test_the_same_board_writes_the_same_bytes_whatever_order_it_was_painted() -> void:
	var cells := [Vector2i(0, 0), Vector2i(2, 0), Vector2i(1, 1)]
	var forwards := _board_with_bases(cells)
	cells.reverse()
	var backwards := _board_with_bases(cells)
	assert_eq(
		forwards.to_text(), backwards.to_text(), "a saved draft is its board, not its edit history"
	)


## A 3x2 board with a base on each of `cells`, owned by seat 1, laid down in the
## order given.
func _board_with_bases(cells: Array) -> MapDocument:
	var doc := MapDocument.blank(3, 2, terrain_db)
	for cell: Vector2i in cells:
		doc.paint(cell, &"base")
		doc.set_owner(cell, 1)
		doc.place_unit(cell, unit_db.by_id(&"infantry"), 1)
	return doc


## Every board on disk: the shipped roster, the fixtures, and the campaign
## boards one war-directory down — the campaign half is here rather than for
## completeness, since it is the only place a named unit and a carry slot are
## written, and both are rows `to_text` has to put back.
func _every_board() -> Array[String]:
	var paths := MapCatalog.paths() + MapCatalog.fixture_paths()
	var campaign_dir := MapCatalog.MAPS_DIR.path_join("campaign")
	for war in DirAccess.get_directories_at(campaign_dir):
		paths += ResourceDir.files(campaign_dir.path_join(war), ".txt", "test_map_document")
	assert_gt(paths.size(), 40, "the corpus is the boards on disk, not a stale list")
	return paths


## Everything a board is that the editor can change, in one comparable value.
func _board_digest(map: MapData) -> Dictionary:
	var symbols := PackedStringArray()
	for y in map.height:
		var row := ""
		for x in map.width:
			row += map.terrain_at(Vector2i(x, y)).symbol
		symbols.append(row)
	var units := PackedStringArray()
	for entry: Dictionary in map.starting_units:
		units.append(
			"%d %s %s %s %s" % [entry.team, entry.symbol, entry.cell, entry.tag, entry.carry]
		)
	units.sort()
	return {
		"description": map.description,
		"symmetric": map.symmetric,
		"grouping": map.grouping,
		"terrain": symbols,
		"owners": map.initial_owners(),
		"units": units,
		"teams": map.teams(),
	}
