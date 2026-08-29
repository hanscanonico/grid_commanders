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
	assert_eq(map.starting_units.size(), 1, "one unit was placed")
	assert_eq(map.starting_units[0].symbol, "i", "and it is the rifleman")


func test_every_shipped_board_survives_a_round_trip() -> void:
	for path in _every_board():
		var original := MapData.load_from_file(path, terrain_db)
		assert_not_null(original, "%s parses" % path)
		if original == null:
			continue
		var reparsed := MapData.parse(
			MapDocument.from_map(original, terrain_db).to_text(), terrain_db
		)
		assert_not_null(reparsed, "%s survives a draft and a save" % path)
		if reparsed == null:
			continue
		assert_eq(
			_board_digest(reparsed), _board_digest(original), "%s comes back unchanged" % path
		)


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
