extends GutTest
## The seat strip's shrink arithmetic (COM-48, four-players plan D6; COM-126,
## open-seats D4): what the sides seats stand on — and the seating itself —
## become when the board under them changes.
##
## `SeatStrip.normalised_sides` and `SeatStrip.reopened_seats` are pure static
## answers over what is in hand and the new roster, so the path a player actually
## walks — pick a four-army board, close a seat, pick a duel — is checked without
## a scene, on the terms `MatchRequest` and `TransitionInput` are (CLAUDE.md,
## Testing).

const HUMAN := SeatStrip.Seat.HUMAN
const CPU := SeatStrip.Seat.CPU
const EMPTY := SeatStrip.Seat.EMPTY


## A roster that grows deals the new seats their own side, which is the default
## the strip opens on: every army for itself.
func test_a_growing_roster_gives_each_new_seat_its_own_side() -> void:
	assert_eq(SeatStrip.normalised_sides([0, 1] as Array[int], 4), [0, 1, 2, 3] as Array[int])
	assert_eq(SeatStrip.normalised_sides([] as Array[int], 2), [0, 1] as Array[int])


## A grouping that survives the shrink is kept, only re-packed: two seats of a 2v2
## stood on different sides and still do.
func test_a_shrinking_roster_keeps_a_grouping_that_still_makes_sense() -> void:
	assert_eq(SeatStrip.normalised_sides([0, 1, 0, 1] as Array[int], 2), [0, 1] as Array[int])
	assert_eq(SeatStrip.normalised_sides([0, 0, 1, 1] as Array[int], 3), [0, 0, 1] as Array[int])


## The 3v1 case: the seats left over all stood on side A, so the duel that remains
## has nobody to fight. It falls back to the default rather than greying Start on
## an ordinary two-army board that used to be one click.
func test_a_shrink_that_leaves_nobody_to_fight_falls_back_to_the_default() -> void:
	assert_eq(SeatStrip.normalised_sides([0, 0, 0, 1] as Array[int], 2), [0, 1] as Array[int])
	assert_eq(SeatStrip.normalised_sides([2, 2, 2, 2] as Array[int], 3), [0, 1, 2] as Array[int])


## Every surviving side is re-packed into 0..n-1, because a row draws as many
## badges as the board seats: a seat left on side C on a two-seat board would have
## been a badge row with nothing selected at all.
func test_surviving_sides_are_packed_into_the_badges_a_row_draws() -> void:
	for count in [2, 3, 4]:
		var settled := SeatStrip.normalised_sides([2, 1, 3, 0] as Array[int], count)
		for side in settled:
			assert_between(side, 0, count - 1, "a seat stands on a side its row can draw")


## Sides are re-packed, never re-assigned: who stands with whom survives the shrink
## even when the labels they wore do not.
func test_packing_preserves_who_stands_with_whom() -> void:
	var settled := SeatStrip.normalised_sides([3, 1, 3, 1] as Array[int], 4)
	assert_eq(settled[0], settled[2], "the seats that stood together still do")
	assert_eq(settled[1], settled[3])
	assert_ne(settled[0], settled[1], "and the pairs are still opposed")


## Every Empty button on a board below the closable threshold is dead, so a closed
## seat surviving the shrink would be state nothing on screen could undo: every one
## reopens, to the computer, matching the strip's own seat defaults.
func test_a_shrink_to_an_unclosable_board_reopens_every_closed_seat() -> void:
	assert_eq(
		SeatStrip.reopened_seats([HUMAN, EMPTY] as Array[int], false), [HUMAN, CPU] as Array[int]
	)
	assert_eq(
		SeatStrip.reopened_seats([EMPTY, EMPTY] as Array[int], false), [CPU, CPU] as Array[int]
	)


## A closable board keeps a closed seat the player chose, but never fewer filled
## seats than a match: the Duel seating truncated to three seats is still a duel,
## and one truncated below the minimum reopens in seat order until it is one.
func test_a_closable_shrink_reopens_only_until_the_table_is_a_match() -> void:
	assert_eq(
		SeatStrip.reopened_seats([HUMAN, EMPTY, CPU] as Array[int], true),
		[HUMAN, EMPTY, CPU] as Array[int]
	)
	assert_eq(
		SeatStrip.reopened_seats([HUMAN, EMPTY, EMPTY] as Array[int], true),
		[HUMAN, CPU, EMPTY] as Array[int]
	)


## A seating that already fills every seat passes through untouched, whatever the
## board offers — reopening is a repair, not a re-deal.
func test_a_full_seating_is_left_alone() -> void:
	for closable in [true, false]:
		assert_eq(
			SeatStrip.reopened_seats([HUMAN, CPU, CPU] as Array[int], closable),
			[HUMAN, CPU, CPU] as Array[int]
		)


## How many ways a table can group is the board's answer: a duel has one, so it
## offers no Mode row at all, and three armies can only be all apart or two on one.
func test_a_board_offers_the_modes_its_seats_can_hold() -> void:
	assert_eq(SeatStrip.presets_for(2).size(), 0)
	assert_eq(SeatStrip.presets_for(3).size(), 2)
	assert_eq(SeatStrip.presets_for(4).size(), 5)


## SK-22: the preset row lights the table in hand. Each preset, applied as it is
## written, is itself.
func test_every_preset_matches_its_own_table() -> void:
	for seats_dealt in [3, 4]:
		var presets := SeatStrip.presets_for(seats_dealt)
		for i in presets.size():
			var who: Array[int] = []
			who.assign(presets[i]["seats"])
			var sides: Array[int] = []
			sides.assign(presets[i]["sides"])
			assert_eq(SeatStrip.preset_matching(who, sides), i, presets[i]["label"])


## A table is its seating and grouping, not who plays each seat or which letters
## the sides wear: two people in a 2v2, on sides C and D, is still the 2v2. A closed
## seat's leftover side is not part of the table.
func test_a_preset_matches_by_grouping_not_by_who_plays_or_which_letter() -> void:
	var two_v_two := SeatStrip.preset_matching(
		[HUMAN, HUMAN, CPU, CPU] as Array[int], [2, 3, 2, 3] as Array[int]
	)
	assert_eq(SeatStrip.PRESETS[two_v_two]["label"], "2v2")
	var duel := SeatStrip.preset_matching(
		[CPU, EMPTY, HUMAN, EMPTY] as Array[int], [0, 0, 1, 0] as Array[int]
	)
	assert_eq(SeatStrip.PRESETS[duel]["label"], "Duel")


## A grouping no preset writes lights none, and neither does a board that is not
## four seats.
func test_a_table_no_preset_writes_lights_none() -> void:
	assert_eq(
		SeatStrip.preset_matching([HUMAN, CPU, CPU, CPU] as Array[int], [0, 1, 1, 0] as Array[int]),
		-1
	)
	assert_eq(SeatStrip.preset_matching([HUMAN, CPU] as Array[int], [0, 1] as Array[int]), -1)


## The side letters are out of the way until the player asks for them, and a table
## no Mode describes shows them, since nothing else on screen would say who is allied.
func test_the_side_letters_show_for_custom_or_a_table_no_mode_describes() -> void:
	var free_for_all: Array[int] = [HUMAN, CPU, CPU, CPU]
	assert_false(SeatStrip.shows_sides(free_for_all, [0, 1, 2, 3] as Array[int], false))
	assert_true(SeatStrip.shows_sides(free_for_all, [0, 1, 2, 3] as Array[int], true))
	assert_true(SeatStrip.shows_sides(free_for_all, [0, 1, 1, 0] as Array[int], false))


## A duel's two armies are always opposed, so there is nothing to letter, whatever
## was asked for on a bigger board before.
func test_a_duel_never_shows_the_side_letters() -> void:
	assert_false(SeatStrip.shows_sides([HUMAN, CPU] as Array[int], [0, 1] as Array[int], true))


## One selector walks every answer to "who plays this seat": a person, each tier of
## the computer gentlest first, then nobody, then round again.
func test_the_player_selector_walks_human_every_tier_then_empty() -> void:
	assert_eq(SeatStrip.next_player(HUMAN, 2, 3, true), [CPU, 0] as Array[int])
	assert_eq(SeatStrip.next_player(CPU, 0, 3, true), [CPU, 1] as Array[int])
	assert_eq(SeatStrip.next_player(CPU, 2, 3, true), [EMPTY, 2] as Array[int])
	assert_eq(SeatStrip.next_player(EMPTY, 2, 3, true), [HUMAN, 2] as Array[int])


## The last two seats of a table never close, so the walk steps over Empty there.
func test_the_player_selector_skips_empty_when_the_seat_may_not_close() -> void:
	assert_eq(SeatStrip.next_player(CPU, 2, 3, false), [HUMAN, 2] as Array[int])


func test_the_player_selector_says_who_plays_in_words() -> void:
	assert_string_contains(SeatStrip.player_label(HUMAN, "Normal"), "Human")
	assert_string_contains(SeatStrip.player_label(CPU, "Brutal"), "CPU Brutal")
	assert_string_contains(SeatStrip.player_label(EMPTY, "Brutal"), "Empty")


## Two armies left at any table are simply opposed, so no letters come up unasked:
## a duel's seats, a three-seat board with a seat closed, or a four-seat board with two.
func test_two_armies_raise_no_letters_unasked() -> void:
	assert_false(
		SeatStrip.shows_sides([HUMAN, EMPTY, CPU] as Array[int], [0, 0, 1] as Array[int], false)
	)
	assert_false(
		SeatStrip.shows_sides(
			[HUMAN, CPU, EMPTY, EMPTY] as Array[int], [0, 1, 2, 3] as Array[int], false
		)
	)
