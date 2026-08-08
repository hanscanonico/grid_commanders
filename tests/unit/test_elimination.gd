extends GutTest
## An army falls; a side wins (COM-46, four-players plan FP3/D3).
##
## Both win paths used to be binary. Rout handed victory to the first other team
## in the roster the instant anyone lost their last unit — with three armies, the
## second one dying crowned the first while the third stood at full strength. An
## HQ capture ended the whole match no matter whose HQ it was. Elimination was not
## a modelled state at all: no flag, no unit removal, no forfeited ground, and a
## dead army would still have been handed turns and income.
##
## The duel cases here are the protect clause, not decoration: the first
## elimination *is* the victory when two armies play, so a two-army board has to
## resolve on the same day with the same winner it always did.

const QUARTET := "res://maps/fixtures/quartet.txt"
## Team 2 owns the whole row, HQ included, with team 1 already standing on that
## HQ and team 3 waiting at the far end — so one capture fells an army while two
## others are still fighting over what it leaves behind.
const FALLEN_EMPIRE := """
[terrain]
CCQC
[owners]
2 0 0
2 1 0
2 2 0
2 3 0
[units]
1 i 2 0
2 i 3 0
3 i 0 0
"""

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


func _state(map_text: String, allies: Array = []) -> GameState:
	var state := Fixture.state(map_text)
	for team: int in allies:
		state.sides[team] = 0
	return state


## Every unit of `team`, gone — the rout the sim reaches through `remove_unit`.
func _rout(state: GameState, team: int) -> void:
	for unit in state.units_of(team):
		state.remove_unit(unit)


# --- the duel still resolves exactly as it did ------------------------------


func test_in_a_duel_the_first_elimination_is_the_victory() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n2 i 3 0")
	_rout(state, 2)
	assert_true(state.is_eliminated(2), "the routed army has fallen")
	assert_eq(state.winner, 1, "and with one army left the match is over")
	assert_eq(state.winners(), [1] as Array[int])


func test_a_duel_hq_capture_still_ends_the_match_on_the_spot() -> void:
	var state := _state("[terrain]\nQ.\n[owners]\n2 0 0\n[units]\n1 i 0 0\n2 i 1 0")
	state.capture_progress[Vector2i(0, 0)] = 1
	var command := CaptureCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(state.is_eliminated(2))
	assert_eq(state.winner, 1, "the last army standing wins")


# --- the edge cases the ticket names ----------------------------------------


## A unit can die to the counter on its own turn, which means the rout is reached
## from inside an attack rather than from a turn boundary.
func test_an_army_routed_by_a_counter_on_its_own_turn_falls_there_and_then() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 T 1 0")
	state.units[0].hp = 5  # one counter kills it
	var command := AttackCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(state.units_of(1).is_empty(), "the attacker died to the reply")
	assert_true(state.is_eliminated(1), "so its army fell on its own turn")
	assert_eq(state.winner, 2)


## The bug this milestone exists for: with more than two armies, one falling used
## to crown a survivor while others were still fighting.
func test_three_armies_fall_in_sequence_and_only_the_last_one_standing_wins() -> void:
	var state := _state("[terrain]\n......\n[units]\n1 i 0 0\n2 i 2 0\n3 i 4 0")
	assert_eq(state.teams, [1, 2, 3] as Array[int])
	_rout(state, 2)
	assert_true(state.is_eliminated(2))
	assert_eq(state.winner, 0, "two armies are still fighting")
	assert_eq(state.active_teams(), [1, 3] as Array[int])
	_rout(state, 1)
	assert_eq(state.winner, 3, "now one army is left")
	assert_eq(state.active_teams(), [3] as Array[int])


func test_an_allied_pair_wins_together() -> void:
	var state := _state("[terrain]\n........\n[units]\n1 i 0 0\n2 i 3 0\n3 i 5 0\n4 i 7 0", [1, 3])
	_rout(state, 2)
	assert_eq(state.winner, 0, "team 4 still stands against the pair")
	_rout(state, 4)
	assert_eq(state.winner, 1, "the winning side's lead army")
	assert_eq(state.winners(), [1, 3] as Array[int], "and the whole side for presentation")


## A fallen army's ground goes neutral rather than to the conqueror — contested,
## not a windfall that snowballs whoever was already winning.
func test_a_fallen_armys_ground_goes_neutral_and_is_retaken_by_whoever_gets_there() -> void:
	var state := _state(FALLEN_EMPIRE)
	state.capture_progress[Vector2i(2, 0)] = 1
	CaptureCommand.new(state.units[0], Fixture.path([Vector2i(2, 0)])).apply(state)
	assert_true(state.is_eliminated(2), "the HQ's owner fell")
	assert_eq(state.winner, 0, "but two armies are still fighting")
	assert_eq(state.owner_at(Vector2i(2, 0)), 1, "the conqueror keeps the HQ it took")
	assert_eq(state.owner_at(Vector2i(0, 0)), MapData.NEUTRAL, "the rest went neutral")
	assert_eq(state.owner_at(Vector2i(1, 0)), MapData.NEUTRAL)
	assert_eq(state.owner_at(Vector2i(3, 0)), MapData.NEUTRAL)
	assert_true(state.units_of(2).is_empty(), "and its units left the board")
	# Two different survivors now take the loose ground, which is the whole point
	# of neutral rather than forfeit.
	state.capture_progress[Vector2i(0, 0)] = 1
	CaptureCommand.new(state.units_of(3)[0], Fixture.path([Vector2i(0, 0)])).apply(state)
	assert_eq(state.owner_at(Vector2i(0, 0)), 3, "team 3 took one")
	assert_eq(state.owner_at(Vector2i(2, 0)), 1, "team 1 still holds the other")


# --- the fallen take no turn and earn nothing -------------------------------


func test_the_turn_skips_a_fallen_army_and_the_day_wraps_on_the_first_survivor() -> void:
	var state := _state("[terrain]\n......\n[units]\n1 i 0 0\n2 i 2 0\n3 i 4 0")
	_rout(state, 2)
	assert_eq(state.current_team, 1)
	EndTurnCommand.new().apply(state)
	assert_eq(state.current_team, 3, "team 2 is skipped")
	assert_eq(state.day, 1, "and the day has not wrapped yet")
	EndTurnCommand.new().apply(state)
	assert_eq(state.current_team, 1, "back to the first survivor")
	assert_eq(state.day, 2, "which is when the day advances")


## The day counts rounds of the board's roster, not of whoever is left. When the
## army holding the turn falls during it, the next seat is both the next hand and
## the new lead survivor — so asking "is this the first survivor?" would turn the
## day on the spot and give the other two a whole fresh day to finish the round
## they were already playing.
func test_the_lead_army_falling_on_its_own_turn_does_not_turn_the_day_early() -> void:
	var state := _state("[terrain]\n......\n[units]\n1 i 0 0\n2 i 2 0\n3 i 4 0")
	state.day = 5
	assert_eq(state.current_team, 1, "day 5 opens on the lead army")
	_rout(state, 1)
	assert_true(state.is_eliminated(1), "which then falls during its own turn")
	assert_eq(state.winner, 0, "two armies are still fighting")
	EndTurnCommand.new().apply(state)
	assert_eq(state.current_team, 2)
	assert_eq(state.day, 5, "team 2 plays the rest of the round it was already in")
	EndTurnCommand.new().apply(state)
	assert_eq(state.current_team, 3)
	assert_eq(state.day, 5, "and so does team 3")
	EndTurnCommand.new().apply(state)
	assert_eq(state.current_team, 2, "now the hand rolls back past the last seat")
	assert_eq(state.day, 6, "which is the one day that round cost")


func test_a_fallen_army_earns_no_income() -> void:
	var state := _state(
		"[terrain]\nCC....\n[owners]\n2 0 0\n2 1 0\n[units]\n1 i 3 0\n2 i 2 0\n3 i 5 0"
	)
	var banked: int = state.funds[2]
	_rout(state, 2)
	EndTurnCommand.new().apply(state)  # 1 -> 3, skipping the fallen
	EndTurnCommand.new().apply(state)  # 3 -> 1, a full round
	assert_eq(state.funds[2], banked, "no turn came round, so no income did either")


# --- the save carries it ----------------------------------------------------


func test_a_mid_elimination_save_round_trips() -> void:
	var map := MapData.load_from_file(QUARTET, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = QUARTET
	state.sides = {1: 0, 3: 0, 2: 1, 4: 1}
	state.eliminate(4)
	assert_eq(state.winner, 0, "three armies still play")
	var data := SaveCodec.encode(state, [] as Array[int])
	assert_eq(SaveCodec.validate(data), "")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_true(loaded.state.is_eliminated(4), "the fallen army resumes fallen")
	assert_eq(loaded.state.active_teams(), [1, 2, 3] as Array[int])
	assert_eq(loaded.state.next_team(), 2, "and the rotation still skips it")


## `winner` is the winning side's lead army, and the lead army is the lowest
## *surviving* seat — an ally that fell on the way did not win the match.
func test_a_side_that_lost_a_member_wins_without_naming_it() -> void:
	var state := _state("[terrain]\n........\n[units]\n1 i 0 0\n2 i 3 0\n3 i 5 0\n4 i 7 0", [1, 3])
	_rout(state, 1)
	assert_eq(state.winner, 0, "the pair is down to one, but two sides still stand")
	_rout(state, 2)
	assert_eq(state.winner, 0, "team 4 is still fighting")
	_rout(state, 4)
	assert_eq(state.winner, 3, "the surviving member leads the side")
	assert_eq(state.winners(), [3] as Array[int], "and its fallen ally is not on the screen")
