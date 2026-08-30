extends GutTest
## What MapValidator refuses, and what it must not.
##
## Two halves. The first is parity: every board that ships passes, so the
## validator and the roster lints in test_maps.gd cannot drift into disagreeing
## about what playable means — a validator stricter than the shipped roster would
## refuse an author a board the game itself plays. The second is one crafted bad
## board per rule, each a copy of the good one with exactly one thing wrong, so a
## failure names the rule rather than the board.

## The board every case below starts from: a legal 10x5 duel. Two seats, each on
## an HQ and a base, two neutral cities to fight over, all of it walkable.
const GOOD := """[terrain]
..........
.QB....BQ.
..........
....CC....
..........
[owners]
1 1 1
1 2 1
2 7 1
2 8 1
"""

## The same duel with a channel of open sea down the middle: nothing walks
## between the two headquarters, so no army can ever be felled by capture.
const WALLED := """[terrain]
.....S....
.QB..S.BQ.
.....S....
....CS.C..
.....S....
[owners]
1 1 1
1 2 1
2 7 1
2 8 1
"""

var terrain_db: TerrainDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()


func test_every_shipped_board_passes() -> void:
	for path in MapCatalog.paths() + MapCatalog.fixture_paths():
		var map := MapData.load_from_file(path, terrain_db)
		assert_not_null(map, "%s should parse" % path)
		if map != null:
			assert_eq(
				MapValidator.errors(map),
				[] as Array[String],
				"%s is played today, so the validator may not refuse it" % path
			)


func test_a_good_board_draws_no_complaint() -> void:
	assert_eq(_errors(GOOD), [] as Array[String])


func test_a_board_under_the_floor_is_refused() -> void:
	var text := "[terrain]\n" + ".....\n".repeat(4) + "[owners]\n"
	assert_has_error(_errors(text), "5x4; a map must be at least")


func test_a_board_over_the_ceiling_is_refused() -> void:
	var wide := ".".repeat(MapValidator.MAX_SIZE.x + 1) + "\n"
	assert_has_error(_errors("[terrain]\n" + wide.repeat(5)), "a map may be at most")


func test_a_seat_with_nothing_on_the_board_is_refused() -> void:
	assert_has_error(
		_errors(GOOD.replace("2 7 1\n2 8 1", "3 7 1\n3 8 1")),
		"Seat 2 holds nothing. Seats are numbered from 1 with no gaps, so give it a headquarters"
	)


## Several empty seats are one complaint naming them all: the same sentence said
## once per seat is four lines of a strip and no more information than one.
func test_every_empty_seat_is_named_in_one_complaint() -> void:
	var errors := _errors(GOOD.replace("1 1 1\n1 2 1\n2 7 1\n2 8 1", "3 1 1\n3 2 1\n3 7 1\n3 8 1"))
	assert_has_error(
		errors,
		(
			"Seats 1 and 2 hold nothing. Seats are numbered from 1 with no gaps, so give each a "
			+ "headquarters"
		)
	)
	var about_seating := 0
	for error in errors:
		if error.contains("hold"):
			about_seating += 1
	assert_eq(about_seating, 1, "one complaint for every empty seat, not one apiece")


func test_a_seat_with_two_headquarters_is_refused() -> void:
	assert_has_error(
		_errors(GOOD.replace("....CC....", "....CQ....") + "1 5 3\n"), "Seat 1 owns 2 headquarters"
	)


func test_a_seat_that_cannot_build_is_refused() -> void:
	var text := GOOD.replace(".QB....BQ.", ".Q.....BQ.").replace("1 2 1\n", "")
	assert_has_error(_errors(text), "Seat 1 owns nothing")


func test_a_headquarters_nobody_owns_is_refused() -> void:
	assert_has_error(_errors(GOOD.replace("....CC....", "....CQ....")), "belongs to nobody")


func test_headquarters_walled_off_from_each_other_are_refused() -> void:
	assert_has_error(_errors(WALLED), "No infantry can walk")


func test_a_unit_standing_on_a_property_is_refused() -> void:
	assert_has_error(_errors(GOOD + "[units]\n1 i 4 3\n"), "no side should open the match")


func test_a_dock_with_no_water_beside_it_is_refused() -> void:
	assert_has_error(_errors(GOOD.replace("....CC....", "....CP....")), "no water beside it")


func test_two_docks_on_separate_seas_are_refused() -> void:
	var text := GOOD.replace("..........\n....CC....", "..PS..SP..\n..........")
	assert_has_error(_errors(text), "can never meet")


func test_a_board_with_fewer_properties_than_seats_is_refused() -> void:
	var text := (
		"[terrain]\n"
		+ "..........\n"
		+ ".Q........\n"
		+ "..........\n[owners]\n1 1 1\n[units]\n2 i 8 1\n"
	)
	assert_has_error(_errors(text), "need at least")


func test_a_draft_is_read_as_the_board_it_would_be_saved_as() -> void:
	var map := MapData.parse(GOOD, terrain_db)
	assert_not_null(map)
	if map == null:
		return
	var doc := MapDocument.from_map(map, terrain_db)
	assert_eq(MapValidator.draft_errors(doc, terrain_db), [] as Array[String])
	doc.set_owner(Vector2i(1, 1), MapData.NEUTRAL)
	assert_has_error(MapValidator.draft_errors(doc, terrain_db), "belongs to nobody")


## Every complaint is one whole sentence addressed to the author — the reason the
## class exists rather than a boolean.
func test_every_complaint_reads_as_a_sentence() -> void:
	for error in _errors(GOOD.replace("2 7 1\n2 8 1", "3 7 1\n3 8 1")):
		assert_true(error.ends_with("."), "'%s' should end like a sentence" % error)
		assert_eq(error, error.strip_edges(), "'%s' should not be padded" % error)


## Every complaint the editor can put a mark on names the cells it is about, so
## the strip and the board can never disagree about which building is wrong.
func test_a_complaint_names_the_cells_it_is_about() -> void:
	assert_eq(
		_cells_of(GOOD.replace("....CC....", "....CQ...."), "belongs to nobody"), [Vector2i(5, 3)]
	)
	assert_eq(
		_cells_of(GOOD + "[units]\n1 i 4 3\n", "no side should open the match"), [Vector2i(4, 3)]
	)
	assert_eq(_cells_of(WALLED, "No infantry can walk"), [Vector2i(1, 1), Vector2i(8, 1)])
	# Two headquarters: both of the seat's own, and neither of the other seat's.
	assert_eq(
		_cells_of(GOOD.replace("....CC....", "....CQ....") + "1 5 3\n", "owns 2 headquarters"),
		[Vector2i(1, 1), Vector2i(5, 3)]
	)


## A complaint about the board rather than about a cell of it points at nothing —
## an editor marking a cell for it would be marking one it picked itself.
func test_a_complaint_about_the_whole_board_names_no_cell() -> void:
	var text := "[terrain]\n" + ".....\n".repeat(4) + "[owners]\n"
	assert_eq(_cells_of(text, "a map must be at least"), [] as Array[Vector2i])


## A draft with no board at all is one complaint and no more: nothing else can be
## asked of a board that does not exist.
func test_a_draft_with_no_board_is_one_complaint() -> void:
	var doc := MapDocument.blank(0, 0, terrain_db)
	var found := MapValidator.draft_defects(doc, terrain_db)
	assert_push_error("map has no terrain rows")
	assert_eq(found.size(), 1)
	assert_true(found[0].text.contains("cannot be saved as a map file"), found[0].text)
	assert_eq(found[0].cells, [] as Array[Vector2i])


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


## The cells of the one complaint mentioning `needle`, and a failure when no
## complaint does.
func _cells_of(text: String, needle: String) -> Array[Vector2i]:
	var map := MapData.parse(text, terrain_db)
	assert_not_null(map, "the crafted board should still parse")
	if map == null:
		return [] as Array[Vector2i]
	for defect in MapValidator.defects(map):
		if defect.text.contains(needle):
			return defect.cells
	fail_test("no complaint mentioning '%s'" % needle)
	return [] as Array[Vector2i]
