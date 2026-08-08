extends GutTest

const SAMPLE := """
# tiny test map
[terrain]
SSSS
S.QS
SC=S
SSSS
[owners]
1 2 1
"""

var db: TerrainDB


func before_each() -> void:
	db = Fixture.terrain_db()


func test_dimensions() -> void:
	var map := MapData.parse(SAMPLE, db)
	assert_eq(map.width, 4)
	assert_eq(map.height, 4)
	assert_eq(map.size(), Vector2i(4, 4))


func test_terrain_at() -> void:
	var map := MapData.parse(SAMPLE, db)
	assert_eq(map.terrain_at(Vector2i(0, 0)).id, &"sea")
	assert_eq(map.terrain_at(Vector2i(1, 1)).id, &"plains")
	assert_eq(map.terrain_at(Vector2i(2, 1)).id, &"hq")
	assert_eq(map.terrain_at(Vector2i(1, 2)).id, &"city")
	assert_eq(map.terrain_at(Vector2i(2, 2)).id, &"road")


func test_owners() -> void:
	var map := MapData.parse(SAMPLE, db)
	assert_eq(map.owner_at(Vector2i(2, 1)), 1)
	assert_eq(map.owner_at(Vector2i(1, 2)), MapData.NEUTRAL)


func test_out_of_bounds() -> void:
	var map := MapData.parse(SAMPLE, db)
	assert_false(map.in_bounds(Vector2i(-1, 0)))
	assert_false(map.in_bounds(Vector2i(4, 0)))
	assert_false(map.in_bounds(Vector2i(0, 4)))
	assert_true(map.in_bounds(Vector2i(3, 3)))
	assert_null(map.terrain_at(Vector2i(-1, 0)))


func test_ragged_rows_rejected() -> void:
	assert_null(MapData.parse("[terrain]\nSS\nSSS", db))
	assert_push_error("row 1 is 3 wide, expected 2")


func test_unknown_symbol_rejected() -> void:
	assert_null(MapData.parse("[terrain]\nSX", db))
	assert_push_error("unknown terrain symbol 'X'")


func test_empty_map_rejected() -> void:
	assert_null(MapData.parse("# nothing here", db))
	assert_push_error("map has no terrain rows")


func test_owner_on_non_property_rejected() -> void:
	var text := "[terrain]\n.Q\n[owners]\n1 0 0"
	assert_null(MapData.parse(text, db))
	assert_push_error("is not a property")


func test_owner_out_of_bounds_rejected() -> void:
	var text := "[terrain]\n.Q\n[owners]\n1 5 0"
	assert_null(MapData.parse(text, db))
	assert_push_error("out of bounds")


# String→int coercion reads "x" as 0, so a coordinate typo like `1 x 0` would
# silently place the owner at column 0 — in bounds and a property on this board —
# instead of failing the way every other malformed line does. A non-numeric
# coordinate has to take the same loud error path; a negative one stays numeric
# and keeps failing on the bounds check as before.
func test_owner_non_numeric_coordinate_rejected() -> void:
	assert_not_null(MapData.parse("[terrain]\nCC\n[owners]\n1 0 0", db), "valid line still parses")
	assert_null(MapData.parse("[terrain]\nCC\n[owners]\n1 x 0", db))
	assert_push_error("owner cell must be integer coordinates")
	assert_null(MapData.parse("[terrain]\nCC\n[owners]\n1 1 y", db))
	assert_push_error("owner cell must be integer coordinates")
	assert_null(MapData.parse("[terrain]\nCC\n[owners]\n1 0 -1", db))
	assert_push_error("owner cell (0, -1) out of bounds")


func test_units_section_parsed() -> void:
	var text := "[terrain]\n....\n[units]\n1 i 0 0\n2 t 3 0"
	var map := MapData.parse(text, db)
	assert_not_null(map)
	assert_eq(map.starting_units.size(), 2)
	assert_eq(
		map.starting_units[0],
		{"team": 1, "symbol": "i", "cell": Vector2i(0, 0), "tag": &"", "carry": false}
	)
	assert_eq(
		map.starting_units[1],
		{"team": 2, "symbol": "t", "cell": Vector2i(3, 0), "tag": &"", "carry": false}
	)


func test_bad_unit_line_rejected() -> void:
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i 0", db))
	assert_push_error("bad unit line")
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i 0 0 tag extra", db))
	assert_push_error("bad unit line")


## The carry slot is the last column of the row, after the optional tag: a
## campaign's carried army stands there instead of this unit (campaign-depth D6).
func test_carry_slots_parsed() -> void:
	var text := "[terrain]\n....\n[units]\n1 i 0 0 ^\n1 t 1 0 courier ^\n2 t 3 0"
	var map := MapData.parse(text, db)
	assert_not_null(map)
	assert_true(map.starting_units[0].carry, "a marked row is a carry slot")
	assert_true(map.starting_units[1].carry, "and so is a marked row that is also named")
	assert_eq(map.starting_units[1].tag, &"courier", "the name is still the name")
	assert_false(map.starting_units[2].carry, "an unmarked row is the unit it always was")


## The mark can never be read as a name, in either direction: a tag is an
## identifier and `^` is not, so a board naming `^` is refused rather than
## quietly carrying a unit called that.
func test_the_carry_mark_is_not_a_tag() -> void:
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i 0 0 ^ ^", db))
	assert_push_error("is not an identifier")
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i 0 ^", db))
	assert_push_error("unit cell must be integer coordinates")


func test_unit_out_of_bounds_rejected() -> void:
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i 5 0", db))
	assert_push_error("unit cell (5, 0) out of bounds")


# Same String→int coercion trap as owners: `1 i x 0` would coerce to column 0 and
# spawn a unit where none was written, while a negative coordinate stays numeric
# and keeps failing on the bounds check as before.
func test_unit_non_numeric_coordinate_rejected() -> void:
	assert_not_null(MapData.parse("[terrain]\n..\n[units]\n1 i 0 0", db), "valid line still parses")
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i x 0", db))
	assert_push_error("unit cell must be integer coordinates")
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i 0 y", db))
	assert_push_error("unit cell must be integer coordinates")
	assert_null(MapData.parse("[terrain]\n..\n[units]\n1 i 0 -1", db))
	assert_push_error("unit cell (0, -1) out of bounds")


func test_unit_bad_team_rejected() -> void:
	assert_null(MapData.parse("[terrain]\n..\n[units]\n0 i 1 0", db))
	assert_push_error("unit team must be 1..4")
	assert_null(MapData.parse("[terrain]\n..\n[units]\n5 i 1 0", db))
	assert_push_error("unit team must be 1..4")


func test_loads_first_steps_map() -> void:
	var map := MapData.load_from_file("res://maps/first_steps.txt", db)
	assert_not_null(map)
	assert_eq(map.size(), Vector2i(20, 15))
	assert_eq(map.terrain_at(Vector2i(2, 2)).id, &"hq")
	assert_eq(map.owner_at(Vector2i(2, 2)), 1)
	assert_eq(map.terrain_at(Vector2i(17, 11)).id, &"hq")
	assert_eq(map.owner_at(Vector2i(17, 11)), 2)
	assert_eq(map.terrain_at(Vector2i(16, 8)).id, &"city")
	assert_eq(map.owner_at(Vector2i(16, 8)), MapData.NEUTRAL, "cities start neutral")
	# borders are sea
	assert_eq(map.terrain_at(Vector2i(0, 0)).id, &"sea")
	assert_eq(map.terrain_at(Vector2i(19, 14)).id, &"sea")


func test_owner_bad_team_rejected() -> void:
	assert_null(MapData.parse("[terrain]\n.C\n[owners]\n0 1 0", db))
	assert_push_error("owner team must be 1..4")
	assert_null(MapData.parse("[terrain]\n.C\n[owners]\n5 1 0", db))
	assert_push_error("owner team must be 1..4")


## The board is the roster authority (four-players plan D1): how many armies play
## is read off the seats [owners] and [units] name, and nothing else can say.
func test_the_roster_runs_up_to_the_highest_seat_the_board_names() -> void:
	var owned := MapData.parse("[terrain]\n.CCC\n[owners]\n1 1 0\n3 2 0", db)
	assert_eq(owned.teams(), [1, 2, 3] as Array[int], "an owner on seat 3 deals three seats")
	assert_eq(owned.player_count(), 3)
	var garrisoned := MapData.parse("[terrain]\n....\n[units]\n4 i 0 0", db)
	assert_eq(garrisoned.teams(), [1, 2, 3, 4] as Array[int], "a unit on seat 4 deals four")


## A board that names one army, or none at all, is a fixture rather than a match —
## most movement tests build one — and a duel is what every one of them has always
## been played as.
func test_a_board_that_names_nobody_still_seats_a_duel() -> void:
	assert_eq(MapData.parse("[terrain]\n....\n", db).teams(), MapData.DEFAULT_TEAMS)
	var lone := MapData.parse("[terrain]\n.C..\n[owners]\n1 1 0", db)
	assert_eq(lone.teams(), MapData.DEFAULT_TEAMS, "one army named is still a duel's seats")
