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


func test_only_the_two_rest_states_command_the_board() -> void:
	assert_true(BattleLegend.commands_board(ControlHints.IDLE))
	assert_true(BattleLegend.commands_board(ControlHints.PREVIEW))
	for context: StringName in [
		ControlHints.UNIT_SELECTED,
		ControlHints.MENU,
		ControlHints.TARGETING,
		ControlHints.ANIMATING,
		ControlHints.AI_TURN,
		ControlHints.REPLAY,
		ControlHints.REPLAY_PAUSED,
		ControlHints.PAUSED,
		ControlHints.HANDOFF,
		ControlHints.VICTORY,
		ControlHints.END_TURN_GUARD,
	]:
		assert_false(BattleLegend.commands_board(context), String(context))


## The dock is disabled exactly where the board already refuses input, and live in
## the two contexts it exists for — a computer turn and a paused one. Battle's own
## `_unhandled_input` reads the same answer, so this is the one statement of which
## contexts a key press and a finger tap are both refused in.
func test_the_dock_is_dead_only_where_another_surface_owns_the_input() -> void:
	for context: StringName in [
		ControlHints.ANIMATING,
		ControlHints.HANDOFF,
		ControlHints.VICTORY,
		ControlHints.MENU,
		ControlHints.VALUE_MENU,
		ControlHints.INFO,
		ControlHints.END_TURN_GUARD,
	]:
		assert_false(BattleLegend.dock_live(context), String(context))
	for context: StringName in [
		ControlHints.IDLE,
		ControlHints.PREVIEW,
		ControlHints.UNIT_SELECTED,
		ControlHints.TARGETING,
		ControlHints.DROP_TARGETING,
		ControlHints.POWER_TARGETING,
		ControlHints.AI_TURN,
		ControlHints.REPLAY,
		ControlHints.PAUSED,
		ControlHints.REPLAY_PAUSED,
	]:
		assert_true(BattleLegend.dock_live(context), String(context))


## Resume dispatches `confirm`, which at rest selects whatever is under the cursor,
## so it may only be pressed where the keyboard's own key resumes.
func test_only_a_parked_turn_may_be_resumed() -> void:
	assert_true(BattleLegend.paused_in(ControlHints.PAUSED))
	assert_true(BattleLegend.paused_in(ControlHints.REPLAY_PAUSED))
	assert_false(BattleLegend.paused_in(ControlHints.IDLE))
	assert_false(BattleLegend.paused_in(ControlHints.AI_TURN))


func test_only_a_paused_replay_steps() -> void:
	assert_true(BattleLegend.steppable(ControlHints.REPLAY_PAUSED))
	assert_false(BattleLegend.steppable(ControlHints.PAUSED))


## The word on the leading chip is the thing it is about to do. A context with no
## word of its own rests at MENU, which is what `cancel` does there.
func test_the_back_chip_names_what_cancel_does_here() -> void:
	assert_eq(ControlHints.DOCK_BACK, ControlHints.dock_back_for(ControlHints.POWER_TARGETING))
	assert_eq(ControlHints.DOCK_BACK, ControlHints.dock_back_for(ControlHints.UNIT_SELECTED))
	assert_eq(ControlHints.DOCK_PAUSE, ControlHints.dock_back_for(ControlHints.AI_TURN))
	assert_eq(ControlHints.DOCK_PAUSE, ControlHints.dock_back_for(ControlHints.REPLAY))
	assert_eq(ControlHints.DOCK_MENU, ControlHints.dock_back_for(ControlHints.IDLE))
	assert_eq(ControlHints.DOCK_MENU, ControlHints.dock_back_for(ControlHints.PAUSED))


## The dock's words are held to ASCII for the reason the lens chips are — they are
## printed in the same Silkscreen — and to a width, since eight of them share one
## 640 px row with nothing to give.
func test_the_dock_chips_are_ascii_and_short() -> void:
	for chip in ControlHints.DOCK_CHIPS:
		assert_lt(chip.length(), ControlHints.MAX_CHARS / 4, "dock chip too wide: %s" % chip)
		for i in chip.length():
			assert_true(chip.unicode_at(i) < 128, "non-ASCII: %s" % chip)


## Every word the dock may print, so one it prints and the array never heard of is
## a word nothing holds to the rules above.
func test_every_dock_word_is_in_the_set() -> void:
	var printed: Array[String] = [ControlHints.dock_back_for(ControlHints.IDLE)]
	for context: StringName in ControlHints.DOCK_BACK_WORDS:
		printed.append(ControlHints.dock_back_for(context))
	for word in printed:
		assert_true(word in ControlHints.DOCK_CHIPS, "dock word missing from DOCK_CHIPS: %s" % word)
