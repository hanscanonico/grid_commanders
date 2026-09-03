extends GutTest
## What a turn says as it opens, and the viewer rule behind its second line.
##
## Node-free on both sides: `TurnOpening.lines` and
## `BattlePerspective.reportable_losses` are pure reads of a `GameState`, a
## `SideIdentity` and a viewer, so the words a turn opens with are checked without
## a board on screen (docs/testing_exceptions.md carries the entry).
##
## The board is one long row so a plane can run dry out of everybody's sight: the
## infantry at either end see their own neighbourhoods and nothing reaches column
## ten, which is the case the loss banner exists for and the one a
## "can the viewer see that cell" gate silently drops.

const LONE_PLANE := "[terrain]\n...........\n[units]\n1 i 0 0\n1 b 10 0\n2 i 5 0"
const WATCHED_PLANE := "[terrain]\n...........\n[units]\n1 i 0 0\n1 b 10 0\n2 i 9 0"


## Runs the board on to the turn that takes the plane, and hands back that turn.
func _turn_that_starves(state: GameState) -> EndTurnCommand:
	state.fog_enabled = true
	var plane := state.units[1]
	plane.fuel = plane.type.fuel_upkeep  # exactly enough for one more day
	EndTurnCommand.new().apply(state)
	var opens := EndTurnCommand.new()
	opens.apply(state)
	assert_false(plane in state.units, "the plane should have gone down as the turn opened")
	return opens


func _viewer(state: GameState, team: int) -> BattlePerspective:
	var perspective := BattlePerspective.new(state)
	perspective.refresh(team, false)
	return perspective


func _lines(state: GameState, perspective: BattlePerspective, opens: EndTurnCommand) -> Array:
	return TurnOpening.lines(state, SideIdentity.resolve({}), perspective, opens.starved, false)


func test_your_own_plane_is_named_even_where_nobody_could_watch_it_fall() -> void:
	var state := Fixture.state(LONE_PLANE)
	var plane := state.units[1]
	var opens := _turn_that_starves(state)
	var perspective := _viewer(state, 1)
	assert_false(perspective.can_see_cell(plane.cell), "nothing of team 1's is left watching it")
	var said := _lines(state, perspective, opens)
	assert_eq(said.size(), 2, "the turn opens on its day card and then on the loss")
	assert_true(said[0].begins_with("Day "), "the day card still comes first")
	assert_eq(said[1], "%s lost - out of fuel" % plane.type.display_name)


func test_another_sides_plane_is_named_only_where_the_viewer_can_see_the_ground() -> void:
	var hidden := Fixture.state(LONE_PLANE)
	var opens := _turn_that_starves(hidden)
	assert_eq(
		_lines(hidden, _viewer(hidden, 2), opens).size(),
		1,
		"team 2 learns nothing about a plane it never saw"
	)

	var watched := Fixture.state(WATCHED_PLANE)
	var seen := _turn_that_starves(watched)
	assert_eq(
		_lines(watched, _viewer(watched, 2), seen).size(), 2, "a plane down in plain view is said"
	)


func test_a_posed_frame_gains_no_card_nothing_staged_it() -> void:
	var state := Fixture.state(LONE_PLANE)
	var opens := _turn_that_starves(state)
	var said := TurnOpening.lines(
		state, SideIdentity.resolve({}), _viewer(state, 1), opens.starved, true
	)
	assert_eq(said.size(), 1, "a capture run opens on the day card alone")


func test_several_losses_are_counted_rather_than_listed() -> void:
	var state := Fixture.state(LONE_PLANE)
	var perspective := _viewer(state, 1)
	var lost: Array[Unit] = [state.units[1], state.units[1]]
	var said := TurnOpening.lines(state, SideIdentity.resolve({}), perspective, lost, false)
	assert_eq(said[1], "2 units lost - out of fuel")
