extends GutTest
## The offline instrument's fog seat: `AIController.honour_fog` holds one
## planner to the fog its team is shown, the way a human at that seat is.
##
## The shipped opponent never sets it — the AI sees the whole board on purpose,
## `test_ai_vision.gd` pins the one exception — so what this suite guards is
## that the default still sees everything, that the opt-in sees exactly what
## `Vision` shows, and that fog off makes the two the same seat.

var unit_db: UnitDB

## Nine plains: team 1's infantry at the west end (sight 2) and team 2's at the
## east end, seven cells away and outside any player sight.
const FAR_ENEMY := "[terrain]\n.........\n[units]\n1 i 0 0\n2 i 8 0"

## The same line with a second enemy standing inside the player's sight.
const NEAR_AND_FAR := "[terrain]\n.........\n[units]\n1 i 0 0\n2 i 2 0\n2 i 8 0"


func before_each() -> void:
	unit_db = Fixture.unit_db()


func _state(map_text: String, fog: bool) -> GameState:
	var state := Fixture.state(map_text)
	state.fog_enabled = fog
	return state


func _enemies(state: GameState, honour_fog: bool) -> Array[Unit]:
	var context := AIPlanningContext.new(unit_db)
	context.honour_fog = honour_fog
	context.begin(state)
	return context.visible_enemies


func test_the_fog_seat_omits_an_enemy_outside_its_sight() -> void:
	var state := _state(FAR_ENEMY, true)
	assert_eq(_enemies(state, true).size(), 0, "seven cells off is past an infantry's sight")


func test_the_default_seat_still_sees_through_the_fog() -> void:
	var state := _state(FAR_ENEMY, true)
	assert_eq(_enemies(state, false), [state.units[1]], "the shipped planner is omniscient")


func test_with_fog_off_both_seats_see_the_enemy() -> void:
	var state := _state(FAR_ENEMY, false)
	assert_eq(_enemies(state, false), [state.units[1]])
	assert_eq(_enemies(state, true), [state.units[1]], "no fog to honour")


## Fog, not blindness: what stands inside the seat's sight is still an enemy.
func test_the_fog_seat_keeps_an_enemy_inside_its_sight() -> void:
	var state := _state(NEAR_AND_FAR, true)
	assert_eq(_enemies(state, true), [state.units[1]], "the near one and only the near one")


## The controller forwards the switch: a blind planner has nothing to walk
## toward and stays put, where the sighted one advances on the far infantry.
func test_the_controller_forwards_the_switch_to_its_planner() -> void:
	var sighted := AIController.new(unit_db).plan_next_command(_state(FAR_ENEMY, true))
	assert_true(sighted is MoveCommand, "sanity: the sighted seat still acts")
	var sighted_path: Array[Vector2i] = (sighted as MoveCommand).path
	assert_ne(sighted_path[sighted_path.size() - 1], Vector2i(0, 0), "and advances")
	var blind_ai := AIController.new(unit_db)
	blind_ai.honour_fog = true
	var blind := blind_ai.plan_next_command(_state(FAR_ENEMY, true))
	assert_true(blind is MoveCommand, "the blind seat still acts")
	var blind_path: Array[Vector2i] = (blind as MoveCommand).path
	assert_eq(blind_path[blind_path.size() - 1], Vector2i(0, 0), "with nothing to walk toward")
