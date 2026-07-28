extends GutTest
## SaveCodec's second validator: whether a save describes a board that can exist.
##
## Split from test_save_codec.gd because the two validators are split. `validate`
## answers about structure without a map, so a save can be named on a menu that has
## loaded none; `board_error` answers about values and needs the board to answer at
## all. These cases therefore all load a real map, which is the line between the
## files.
##
## Every case here used to decode *clean* (COM-52) and hand the rules a board they
## cannot reason about, so the symptom arrived much later and somewhere else: a unit
## off the map null-derefs CombatResolver's terrain read the first time anything
## shoots at it, a unit at zero HP is a corpse no attack can finish, and a unit on a
## team that does not play is one no turn ever readies. That each rejection *names*
## its reason is the point — the loader is the last place that still knows the save
## is the cause.

const MAP_PATH := "res://maps/first_steps.txt"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _encoded() -> Dictionary:
	var map := MapData.load_from_file(MAP_PATH, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = MAP_PATH
	return SaveCodec.encode(state, [2] as Array[int])


func _decode(data: Dictionary) -> SaveCodec.LoadedMatch:
	return SaveCodec.decode(data, terrain_db, unit_db, chart)


func test_a_unit_off_the_board_is_rejected() -> void:
	var data := _encoded()
	(data["units"] as Array)[0]["x"] = 999
	assert_null(_decode(data), "a unit off the map must fail here, not in the combat resolver")
	assert_push_error("off a")


func test_a_negative_cell_is_rejected() -> void:
	var data := _encoded()
	(data["units"] as Array)[0]["y"] = -1
	assert_null(_decode(data), "in_bounds is the authority, so below zero is off the board too")
	assert_push_error("off a")


func test_a_unit_with_no_hp_is_rejected() -> void:
	var data := _encoded()
	(data["units"] as Array)[0]["hp"] = 0
	assert_null(_decode(data), "zero HP is a dead unit, not a wounded one")
	assert_push_error("outside 1-100")


func test_hp_above_full_health_is_rejected() -> void:
	var data := _encoded()
	(data["units"] as Array)[0]["hp"] = 101
	assert_null(_decode(data))
	assert_push_error("outside 1-100")


func test_a_unit_on_a_team_that_does_not_play_is_rejected() -> void:
	var data := _encoded()
	(data["units"] as Array)[0]["team"] = 9
	assert_null(_decode(data), "a unit no turn would ever ready must not load")
	assert_push_error("team 9, which does not play")


func test_a_turn_belonging_to_a_team_that_does_not_play_is_rejected() -> void:
	var data := _encoded()
	data["current_team"] = 9
	assert_null(_decode(data), "the turn indexes funds, which only the playing teams have")
	assert_push_error("turn belongs to team 9")


func test_a_victory_by_a_team_that_does_not_play_is_rejected() -> void:
	var data := _encoded()
	data["winner"] = 9
	assert_null(_decode(data), "a winner nobody was locks the board against every command")
	assert_push_error("won by team 9")


## Zero is the running match, not a nonsense winner — every save the game writes
## mid-match carries it, so refusing it would refuse them all.
func test_no_winner_yet_is_not_a_bad_winner() -> void:
	var map := MapData.load_from_file(MAP_PATH, terrain_db)
	var data := _encoded()
	data["winner"] = 0
	assert_eq(SaveCodec.board_error(data, map), "")


## `board_error` is public and `validate` is a separate call, so a caller that has
## not run one first must get the reason string the signature promises rather than a
## runtime error off a key that was never there.
func test_an_unvalidated_dictionary_comes_back_as_a_reason() -> void:
	var map := MapData.load_from_file(MAP_PATH, terrain_db)
	assert_ne(SaveCodec.board_error({}, map), "", "a save with no lists at all is a reason")
	var data := _encoded()
	data["units"] = ["not a unit"]
	assert_ne(SaveCodec.board_error(data, map), "", "so is an entry that is not a dictionary")
	data = _encoded()
	(data["owners"] as Array)[0].erase("x")
	assert_ne(SaveCodec.board_error(data, map), "", "so is an entry with no cell to check")


func test_an_owned_property_off_the_board_is_rejected() -> void:
	var data := _encoded()
	(data["owners"] as Array)[0]["x"] = 999
	assert_null(_decode(data), "every cell the save carries is asked, not only the units'")
	assert_push_error("owned property at")


func test_a_capture_in_progress_off_the_board_is_rejected() -> void:
	var data := _encoded()
	data["capture_progress"] = [{"x": 999, "y": 0, "points": 10}]
	assert_null(_decode(data))
	assert_push_error("capture in progress at")


## The counterpart every rejection test needs: a save the game itself wrote must
## still be read, so none of the bounds above has been drawn one cell too tight.
func test_a_freshly_encoded_save_passes_the_board_check() -> void:
	var map := MapData.load_from_file(MAP_PATH, terrain_db)
	assert_eq(SaveCodec.board_error(_encoded(), map), "")
	assert_not_null(_decode(_encoded()))


## Full health and the far corner are legal, not merely almost — an off-by-one in
## either bound would refuse a board the game routinely produces.
func test_the_bounds_include_their_own_edges() -> void:
	var map := MapData.load_from_file(MAP_PATH, terrain_db)
	var data := _encoded()
	var unit: Dictionary = (data["units"] as Array)[0]
	unit["hp"] = SaveCodec.MAX_HP
	unit["x"] = map.width - 1
	unit["y"] = map.height - 1
	assert_eq(SaveCodec.board_error(data, map), "", "the last cell of the board is on it")
	unit["hp"] = SaveCodec.MIN_HP
	assert_eq(SaveCodec.board_error(data, map), "", "one HP is a unit clinging on, not a corpse")
