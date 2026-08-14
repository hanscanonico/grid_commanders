extends GutTest
## Who can still act, and which of them N walks to next. Pure and static like
## PathArrow.segments, so the walk the board performs is checked without a scene.
##
## The list and the walk have to be one order or the walk skips a unit — which is
## exactly the failure a player cannot see, since the cursor lands somewhere
## plausible either way. So every case here asks both authorities about the same
## board.

## Three of team 1's units on one row, plus one on the row below and an enemy.
const BOARD := "[terrain]\n.....\n.....\n[units]\n1 i 0 0\n1 i 4 0\n1 i 2 0\n1 i 1 1\n2 i 3 1"


func _cells(units: Array[Unit]) -> Array:
	var cells := []
	for unit in units:
		cells.append(unit.cell)
	return cells


func test_the_list_is_the_side_on_turn_in_reading_order() -> void:
	var state := Fixture.state(BOARD)
	assert_eq(
		_cells(ReadyUnits.of(state)),
		[Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0), Vector2i(1, 1)]
	)


func test_a_unit_that_has_acted_leaves_the_list() -> void:
	var state := Fixture.state(BOARD)
	state.unit_at(Vector2i(2, 0)).acted = true
	assert_eq(_cells(ReadyUnits.of(state)), [Vector2i(0, 0), Vector2i(4, 0), Vector2i(1, 1)])


func test_the_walk_takes_the_next_unit_after_the_cursor() -> void:
	var state := Fixture.state(BOARD)
	assert_eq(ReadyUnits.after(state, Vector2i(0, 0)).cell, Vector2i(2, 0))
	assert_eq(ReadyUnits.after(state, Vector2i(3, 0)).cell, Vector2i(4, 0))


## A cursor past the last ready unit comes back round, so a repeated press walks
## the whole list rather than stopping at the bottom-right corner.
func test_the_walk_wraps_to_the_first() -> void:
	var state := Fixture.state(BOARD)
	assert_eq(ReadyUnits.after(state, Vector2i(4, 1)).cell, Vector2i(0, 0))


## Every press moves, so pressing N four times visits all four and returns.
func test_a_repeated_press_visits_every_ready_unit() -> void:
	var state := Fixture.state(BOARD)
	var visited := []
	var cell := Vector2i(0, 0)
	for i in 4:
		cell = ReadyUnits.after(state, cell).cell
		visited.append(cell)
	assert_eq(visited, [Vector2i(2, 0), Vector2i(4, 0), Vector2i(1, 1), Vector2i(0, 0)])


## Nothing ready is the cue for the board's refusal line rather than a silent
## press, so it has to be distinguishable from a unit.
func test_nothing_ready_answers_null() -> void:
	var state := Fixture.state(BOARD)
	for unit in state.units:
		unit.acted = true
	assert_null(ReadyUnits.after(state, Vector2i(0, 0)))
	assert_true(ReadyUnits.of(state).is_empty())
