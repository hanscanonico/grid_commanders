extends GutTest
## The boards where the planner's own lists come back empty.
##
## `test_ai_controller.gd` plays healthy boards: there is always an enemy to walk
## at, a property to take and a base to build from. Four first-element and
## null-return paths in `ai/` only ever run when one of those is missing —
## `AIAdvance.enemy_goal` answering null, `_worth_walking_to` / `_nearest`
## indexing `cells[0]`, `AIProductionPlanner.plan` returning null — and a board
## that reaches them is a legal board a match can produce.
##
## The bar here is not "does not crash": every case asserts the planner hands
## back a command the rules accept, and which *kind* of command it is, because a
## planner that answers the degenerate board with the wrong command is as broken
## as one that answers it with an error.

var ai: AIController


func before_each() -> void:
	ai = AIController.new(Fixture.unit_db())


## Nothing left for the units to do, so the decision falls through to production.
func _spent_board(map_text: String) -> GameState:
	var state := Fixture.state(map_text)
	for unit in state.units:
		unit.acted = true
	return state


## Pins `AIProductionPlanner.plan`'s `best_choice == null` return. A city is a
## property that builds nothing, so the facility loop appends nothing and there
## is no choice to wrap in a BuildCommand — with the guard gone the planner hands
## the rules a build of no unit type onto a cell that produces none.
func test_a_team_with_property_but_no_facility_does_not_build() -> void:
	var state := _spent_board("[terrain]\n.C\n[owners]\n1 1 0\n[units]\n1 i 0 0")
	state.funds[1] = 999999
	var command := ai.plan_next_command(state)
	assert_not_null(command)
	assert_false(command is BuildCommand, "a city builds nothing, got %s" % command)
	assert_true(command is EndTurnCommand, "nothing else is left, got %s" % command)
	assert_eq(command.validate(state), "")


## Pins the facility loop's `choice == null` skip. The facility is real and
## every price is out of reach, so `_pick_build` answers null for it and the
## cell has to be passed over rather than ranked. An army that cannot afford a
## rifleman ends its turn rather than buying on credit.
func test_a_facility_with_no_money_does_not_build() -> void:
	var state := _spent_board("[terrain]\n.B\n[owners]\n1 1 0\n[units]\n1 i 0 0")
	state.funds[1] = 0
	var command := ai.plan_next_command(state)
	assert_not_null(command)
	assert_false(command is BuildCommand, "nothing on the list is affordable, got %s" % command)
	assert_true(command is EndTurnCommand, "got %s" % command)
	assert_eq(command.validate(state), "")


## Pins `AIAdvance.goal_for`'s null-goal fallback. With nobody visible
## `enemy_goal` answers null, and without the fallback the advance dereferences
## it. The goal it substitutes is the unit's own cell, which MoveCommand
## documents as a wait.
func test_a_unit_with_no_enemy_anywhere_waits_in_place() -> void:
	var state := Fixture.state("[terrain]\n....\n[units]\n1 t 0 0")
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand, "expected a wait, got %s" % command)
	assert_eq((command as MoveCommand).path, [Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(command.validate(state), "")


## The smallest board there is. The same fallback, with nowhere at all to walk:
## the path is the one cell the unit stands on, never the empty array — a
## MoveCommand with no path names no destination and the rules refuse it.
func test_a_one_cell_board_waits_rather_than_moving_nowhere() -> void:
	var state := Fixture.state("[terrain]\n.\n[units]\n1 i 0 0")
	var command := ai.plan_next_command(state)
	assert_true(command is MoveCommand, "expected a wait, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_eq(path, [Vector2i(0, 0)] as Array[Vector2i], "stay put, with a path that says so")
	assert_eq(command.validate(state), "")


## Pins `goal_for`'s `capturable.is_empty()` guard. The one property on the board
## is an ally's, so `capturable_properties` comes back empty and the capture
## clause has to be skipped rather than entered — entered, `_worth_walking_to`
## indexes `cells[0]` of an empty list.
func test_a_capturer_whose_only_property_is_an_allys_advances_instead() -> void:
	var state := Fixture.state("[terrain]\n.C\n[owners]\n2 1 0\n[units]\n1 i 0 0")
	state.sides = {1: 1, 2: 1}
	assert_true(state.allied(1, 2), "the grouping is what makes the city unavailable")
	var command := ai.plan_next_command(state)
	assert_false(command is CaptureCommand, "an ally's city is not a target, got %s" % command)
	assert_true(command is MoveCommand, "expected a wait, got %s" % command)
	assert_eq((command as MoveCommand).path, [Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(command.validate(state), "")
