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
	assert_has_error(_errors(text), "at least")


func test_a_board_over_the_ceiling_is_refused() -> void:
	var wide := ".".repeat(MapValidator.MAX_SIZE.x + 1) + "\n"
	assert_has_error(_errors("[terrain]\n" + wide.repeat(5)), "at most")


func test_a_seat_with_nothing_on_the_board_is_refused() -> void:
	assert_has_error(_errors(GOOD.replace("2 7 1\n2 8 1", "3 7 1\n3 8 1")), "Seat 2 holds nothing")


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
