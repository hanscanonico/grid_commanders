extends GutTest
## What MapValidator says about the units a board opens with (ED-01).
##
## A board that loads is not yet a board that seats: `GameState.create` refuses a
## unit on ground its move class has no cost for, a kind the roster does not
## hold, and two units on one cell. The validator asks the same questions, so a
## board it passes always starts.

## A legal 10x5 duel with a strip of open sea along its southern edge, for the
## units that stand on water and the ones that cannot.
const COASTAL := """[terrain]
..........
.QB....BQ.
..........
....CC....
SSSSS.....
[owners]
1 1 1
1 2 1
2 7 1
2 8 1
[units]
"""

var terrain_db: TerrainDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()


func test_a_ship_on_land_is_refused() -> void:
	var text := COASTAL + "2 c 9 4\n"
	assert_has_error(_errors(text), "A Cruiser cannot stand on plains")
	assert_eq(_cells_of(text, "cannot stand on"), [Vector2i(9, 4)])


func test_infantry_on_the_sea_is_refused() -> void:
	var text := COASTAL + "1 i 1 4\n"
	assert_has_error(_errors(text), "An Infantry cannot stand on sea")
	assert_eq(_cells_of(text, "cannot stand on"), [Vector2i(1, 4)])


## Aircraft stand anywhere, ships on water, foot on land: no complaint, and the
## board the validator passed seats.
func test_units_on_ground_they_can_use_draw_no_complaint() -> void:
	var text := COASTAL + "1 i 0 0\n1 c 0 4\n2 f 3 4\n2 b 9 0\n"
	assert_eq(_errors(text), [] as Array[String])
	var map := MapData.parse(text, terrain_db)
	assert_not_null(GameState.create(map, Fixture.unit_db(), Fixture.chart()), "it must seat")


func test_a_unit_of_no_known_kind_is_refused() -> void:
	assert_has_error(_errors(COASTAL + "1 ? 0 0\n"), "no known kind")


func test_two_units_on_one_cell_are_refused() -> void:
	var text := COASTAL + "1 i 0 0\n2 i 0 0\n"
	assert_has_error(_errors(text), "Two units start")
	assert_eq(_cells_of(text, "Two units start"), [Vector2i(0, 0)])


## The editor's path: a hull placed on a field is marked on the cell it stands on.
func test_a_draft_with_a_ship_on_land_marks_its_cell() -> void:
	var doc := MapDocument.from_map(MapData.parse(COASTAL, terrain_db), terrain_db)
	doc.place_unit(Vector2i(9, 0), Fixture.unit_db().by_symbol("c"), 2)
	var found := MapValidator.draft_defects(doc, terrain_db)
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq(found[0].text, "A Cruiser cannot stand on plains at (9, 0).")
		assert_eq(found[0].cells, [Vector2i(9, 0)] as Array[Vector2i])


## Parity the other way round from test_map_validator.gd: every shipped board
## both passes and seats.
func test_every_shipped_board_seats() -> void:
	for path in MapCatalog.paths():
		var map := MapData.load_from_file(path, terrain_db)
		assert_not_null(map, "%s should parse" % path)
		if map != null:
			var state := GameState.create(map, Fixture.unit_db(), Fixture.chart())
			assert_not_null(state, "%s passes the validator, so it must seat" % path)


func assert_has_error(errors: Array[String], needle: String) -> void:
	for error in errors:
		if error.contains(needle):
			return
	fail_test("no complaint mentioning '%s' in %s" % [needle, errors])


func _errors(text: String) -> Array[String]:
	var map := MapData.parse(text, terrain_db)
	assert_not_null(map, "the crafted board should still parse")
	if map == null:
		return [] as Array[String]
	return MapValidator.errors(map)


func _cells_of(text: String, needle: String) -> Array[Vector2i]:
	var map := MapData.parse(text, terrain_db)
	if map == null:
		return [] as Array[Vector2i]
	for defect in MapValidator.defects(map):
		if defect.text.contains(needle):
			return defect.cells
	fail_test("no complaint mentioning '%s'" % needle)
	return [] as Array[Vector2i]
