extends GutTest
## The seat strip's grouping arithmetic (COM-48, four-players plan D6): what the
## sides seats stand on become when the board under them changes.
##
## `SeatStrip.normalised_sides` is a pure static answer over the sides in hand and
## the new roster, so the path a player actually walks — pick a four-army board,
## group it, pick a duel — is checked without a scene, on the terms `MatchRequest`
## and `TransitionInput` are (CLAUDE.md, Testing).


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
