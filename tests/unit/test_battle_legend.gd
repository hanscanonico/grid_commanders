extends GutTest
## Which legend context wins when a state's own is overridden — a recording being
## watched, or a menu whose rows answer to left and right. Pure and Node-free, so
## the overrides are checked without booting the battle scene (the same terms
## ReadyUnits and TransitionInput are tested on).


func test_a_state_keeps_its_own_context_by_default() -> void:
	assert_eq(ControlHints.IDLE, BattleLegend.context_for(ControlHints.IDLE, false, false))
	assert_eq(ControlHints.MENU, BattleLegend.context_for(ControlHints.MENU, false, false))


func test_a_recording_relabels_the_two_contexts_it_borrows() -> void:
	assert_eq(ControlHints.REPLAY, BattleLegend.context_for(ControlHints.AI_TURN, true, false))
	assert_eq(
		ControlHints.REPLAY_PAUSED, BattleLegend.context_for(ControlHints.PAUSED, true, false)
	)
	assert_eq(ControlHints.IDLE, BattleLegend.context_for(ControlHints.IDLE, true, false))


func test_value_rows_relabel_only_the_menu() -> void:
	# The board's action menus carry no value row, so they must keep printing the
	# legend they always did; only a menu that answers to left and right says so.
	assert_eq(ControlHints.VALUE_MENU, BattleLegend.context_for(ControlHints.MENU, false, true))
	assert_eq(ControlHints.MENU, BattleLegend.context_for(ControlHints.MENU, false, false))
	assert_eq(ControlHints.IDLE, BattleLegend.context_for(ControlHints.IDLE, false, true))
