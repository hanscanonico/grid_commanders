extends GutTest
## What a viewer may be told about a seat's economy, asked of the one adapter
## that answers it.
##
## The commander info sheet prints every seat's properties, income and bank, and
## only these two rules keep it from printing what the board is hiding: a bank is
## the viewer's own seat's alone, and a holding is public only while there is no
## fog to hide a capture behind. Node-free like the rest of BattlePerspective, so
## the policy is checked without staging a battle (docs/testing_exceptions.md).

## Four armies on a row of plains, one infantry each, so every seat is real.
const FOUR_ARMIES := "[terrain]\n....\n[units]\n1 i 0 0\n2 i 1 0\n3 i 2 0\n4 i 3 0"


## A board where 1 and 3 stand together and 2 and 4 each stand alone.
func _state(fog := false) -> GameState:
	var state := Fixture.state(FOUR_ARMIES)
	state.sides[1] = 0
	state.sides[3] = 0
	state.fog_enabled = fog
	return state


func _viewed_by(state: GameState, team: int, blacked_out := false) -> BattlePerspective:
	var perspective := BattlePerspective.new(state)
	perspective.refresh(team, blacked_out)
	return perspective


func test_a_bank_is_its_own_seats_and_no_others() -> void:
	var perspective := _viewed_by(_state(), 1)
	assert_true(perspective.can_see_funds(1), "your own bank")
	assert_false(perspective.can_see_funds(3), "an ally's: a side never shares infrastructure")
	assert_false(perspective.can_see_funds(2), "an enemy's is not on the board")
	assert_false(perspective.can_see_funds(4), "nor the other enemy's")


func test_a_seat_the_board_never_dealt_is_nobodys_ally() -> void:
	var perspective := _viewed_by(_state(true), 1)
	assert_false(perspective.can_see_funds(9), "an unseated team banks nothing you may read")
	assert_false(perspective.can_see_holdings(9), "and holds nothing you may count under fog")


func test_holdings_are_public_with_no_fog_to_hide_a_capture_behind() -> void:
	var perspective := _viewed_by(_state(), 1)
	for team in [1, 2, 3, 4]:
		assert_true(perspective.can_see_holdings(team), "team %d's flags are all drawn" % team)


func test_fog_leaves_holdings_to_the_viewers_own_side() -> void:
	var perspective := _viewed_by(_state(true), 1)
	assert_true(perspective.can_see_holdings(1), "your own")
	assert_true(perspective.can_see_holdings(3), "an ally's, whose flags your side already sees")
	assert_false(perspective.can_see_holdings(2), "an enemy capture inside your fog stays hidden")
	assert_false(perspective.can_see_holdings(4), "and so does the other enemy's")


## A replay is over, so there is nobody left to hide it from — the same
## short-circuit every other query here takes (replay plan D5).
func test_a_replay_reads_every_seat() -> void:
	var perspective := BattlePerspective.new(_state(true), true)
	perspective.refresh(1, false)
	for team in [1, 2, 3, 4]:
		assert_true(perspective.can_see_funds(team), "team %d's bank over a playback" % team)
		assert_true(perspective.can_see_holdings(team), "team %d's holdings over a playback" % team)


## The device is changing hands: the outgoing player must not leave their own
## economy on screen for the incoming one to read.
func test_a_hot_seat_blackout_hides_even_your_own() -> void:
	var perspective := _viewed_by(_state(), 1, true)
	assert_false(perspective.can_see_funds(1), "your own bank, while the device is in the air")
	assert_false(perspective.can_see_holdings(1), "and what you hold with it")
	assert_false(perspective.can_see_holdings(3), "and your ally's")
