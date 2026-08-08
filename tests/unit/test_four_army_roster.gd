extends GutTest
## A board that seats four armies, played end to end through the sim (COM-44,
## four-players plan FP1).
##
## Every other test in the suite builds a duel, because every shipped board is
## one. That is exactly why this file exists: the roster was a compile-time
## constant, so a four-army board parsed cleanly and then played a match with two
## seats empty — no funds and no turn. Each assertion below is one of those
## silences.
##
## Victory is not one of them: elimination and N-way victory shipped with FP3 and
## are pinned by `tests/unit/test_elimination.gd`, which plays out the four-army
## cases on its own fixtures.
##
## Most of it plays `maps/fixtures/quartet.txt`, which lives under fixtures/ so it
## is reachable by name and absent from the menu, the map lint and the AI soak.
## The save round-trip at the end plays the shipped `maps/compass.txt` instead,
## because what it has to prove is that a board a player can actually pick — in a
## grouping the seat strip can produce — survives the trip.

const FIXTURE := "res://maps/fixtures/quartet.txt"
const COMPASS := "res://maps/compass.txt"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


func _map() -> MapData:
	return MapData.load_from_file(FIXTURE, terrain_db)


func _state() -> GameState:
	var state := GameState.create(_map(), unit_db, chart)
	state.map_path = FIXTURE
	return state


func test_the_board_deals_four_seats() -> void:
	var map := _map()
	assert_not_null(map, "the four-army fixture should parse")
	assert_eq(map.teams(), [1, 2, 3, 4] as Array[int])
	assert_eq(map.player_count(), 4)


## The roster reaches the match through `create` and nowhere else, so the state
## an opening turn runs against is the board's own answer.
func test_the_match_seats_the_board_and_opens_on_the_first_seat() -> void:
	var state := _state()
	assert_eq(state.teams, [1, 2, 3, 4] as Array[int])
	assert_eq(state.current_team, 1, "the first seat opens")
	assert_eq(state.funds.size(), 4, "a purse per army")
	for team in state.teams:
		assert_true(state.funds.has(team), "team %d has a treasury" % team)
		assert_eq(state.units_of(team).size(), 1, "team %d fields its starting unit" % team)


## The turn used to wrap after the second army, which is what left seats 3 and 4
## with no way to ever act.
func test_the_turn_walks_every_seat_before_the_day_advances() -> void:
	var state := _state()
	var seen: Array[int] = [state.current_team]
	for i in 3:
		EndTurnCommand.new().apply(state)
		seen.append(state.current_team)
		assert_eq(state.day, 1, "the day holds until the hand comes back round")
	assert_eq(seen, [1, 2, 3, 4] as Array[int], "every army takes a turn")
	EndTurnCommand.new().apply(state)
	assert_eq(state.current_team, 1, "and the hand returns to the first seat")
	assert_eq(state.day, 2, "which is when the day advances")


## Funds are the field the save format used to spell out by hand, so seats 3 and
## 4 emptied through a round trip. The roster travels with them now, which is what
## lets the decoder know how many purses to look for.
func test_a_four_army_match_survives_a_save_round_trip() -> void:
	var state := _state()
	for i in state.teams.size():
		state.funds[state.teams[i]] = 500 + i * 100
	var data := SaveCodec.encode(state, [3, 4] as Array[int])
	assert_eq(data["teams"], [1, 2, 3, 4] as Array[int], "the envelope records the roster")
	assert_eq(SaveCodec.validate(data), "")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_eq(loaded.state.teams, [1, 2, 3, 4] as Array[int])
	assert_eq(loaded.ai_teams, [3, 4] as Array[int], "seats 3 and 4 stay the computer's")
	for i in state.teams.size():
		assert_eq(loaded.state.funds[state.teams[i]], 500 + i * 100, "seat %d's purse" % (i + 1))


## A four-army 2v2 taken mid-match through a save and back (COM-49). The roster,
## the grouping and the casualty list all arrived in different format versions, so
## this is the one case that proves they survive together rather than one at a
## time — and it is the shape a player actually saves: a real board, a grouping
## the seat strip can produce, and an army already gone.
func test_a_four_army_2v2_survives_a_mid_match_save() -> void:
	var map := MapData.load_from_file(COMPASS, terrain_db)
	assert_not_null(map, "Compass should parse")
	var state := GameState.create(map, unit_db, chart)
	state.map_path = COMPASS
	state.sides = {1: 0, 3: 0, 2: 1, 4: 1}
	state.fog_enabled = true
	state.day = 7
	state.funds[1] = 4200
	EndTurnCommand.new().apply(state)  # the hand has moved on; day and turn are real
	state.eliminate(4)
	assert_eq(state.winner, 0, "three armies still play")

	var data := SaveCodec.encode(state, [2, 4] as Array[int], &"hard")
	assert_eq(SaveCodec.validate(data), "")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	var back := loaded.state
	assert_eq(back.teams, [1, 2, 3, 4] as Array[int], "the board still seats four")
	assert_true(back.allied(1, 3), "the pair resumes standing together")
	assert_true(back.allied(2, 4))
	assert_false(back.allied(1, 2), "and still opposed")
	assert_true(back.is_eliminated(4), "the fallen army resumes fallen")
	assert_eq(back.active_teams(), [1, 2, 3] as Array[int])
	assert_eq(back.current_team, state.current_team, "the turn is where it was")
	assert_eq(back.day, state.day)
	assert_eq(back.funds[1], state.funds[1])
	assert_true(back.fog_enabled)
	assert_eq(loaded.ai_teams, [2, 4] as Array[int])
	assert_eq(loaded.difficulty, &"hard")
	# The board itself, not just the envelope: an eliminated army holds nothing.
	assert_true(back.units_of(4).is_empty())
	assert_eq(back.properties_of(4).size(), 0, "its ground went neutral before the save")
