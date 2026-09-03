extends GutTest
## Who may read a seat's bank, asked of the one adapter that answers it.
##
## The commander info sheet prints every seat's economy, and only this rule keeps
## it from printing an enemy's treasury: properties and income are counted off
## flags the board already draws, funds are not. Node-free like the rest of
## BattlePerspective, so the policy is checked without staging a battle
## (docs/testing_exceptions.md).

## Four armies on a row of plains, one infantry each, so every seat is real.
const FOUR_ARMIES := "[terrain]\n....\n[units]\n1 i 0 0\n2 i 1 0\n3 i 2 0\n4 i 3 0"


## A board where 1 and 3 stand together and 2 and 4 each stand alone.
func _state() -> GameState:
	var state := Fixture.state(FOUR_ARMIES)
	state.sides[1] = 0
	state.sides[3] = 0
	return state


func _viewed_by(state: GameState, team: int, blacked_out := false) -> BattlePerspective:
	var perspective := BattlePerspective.new(state)
	perspective.refresh(team, blacked_out)
	return perspective


func test_a_viewer_reads_its_own_side_and_no_other() -> void:
	var perspective := _viewed_by(_state(), 1)
	assert_true(perspective.can_see_funds(1), "your own bank")
	assert_true(perspective.can_see_funds(3), "an ally's, which you spend beside")
	assert_false(perspective.can_see_funds(2), "an enemy's is not on the board")
	assert_false(perspective.can_see_funds(4), "nor the other enemy's")


func test_a_seat_the_board_never_dealt_is_not_readable() -> void:
	var perspective := _viewed_by(_state(), 1)
	assert_false(perspective.can_see_funds(9), "an unseated team is nobody's ally")


func test_a_free_for_all_leaves_every_army_its_own() -> void:
	var perspective := _viewed_by(Fixture.state(FOUR_ARMIES), 2)
	assert_true(perspective.can_see_funds(2))
	for team in [1, 3, 4]:
		assert_false(perspective.can_see_funds(team), "team %d is ungrouped" % team)


## A replay is over, so there is nobody left to hide it from — the same
## short-circuit every other query here takes (replay plan D5).
func test_a_replay_reads_every_seat() -> void:
	var perspective := BattlePerspective.new(_state(), true)
	perspective.refresh(1, false)
	for team in [1, 2, 3, 4]:
		assert_true(perspective.can_see_funds(team), "team %d over a playback" % team)


## The device is changing hands: the outgoing player must not leave their own
## treasury on screen for the incoming one to read.
func test_a_hot_seat_blackout_hides_even_your_own() -> void:
	var perspective := _viewed_by(_state(), 1, true)
	assert_false(perspective.can_see_funds(1), "your own bank, while the device is in the air")
	assert_false(perspective.can_see_funds(3), "and your ally's with it")
