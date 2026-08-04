extends GutTest
## Which matches a matchup plays, which every preset over the one match loop
## reads instead of deriving.
##
## Worth its own suite because two of the toolchain's guarantees rest on it and
## neither is visible at a call site: the Lab's shards only merge into the run
## they split up while `--seed-offset=` walks the same range the whole run would
## have, and the arena's rows are only comparable with the Lab's while both play
## the same seeds from the same seats.

const MAP := "ironworks"


func _seeds(slots: Array) -> Array[int]:
	var out: Array[int] = []
	for slot: BalanceMatchSchedule.Slot in slots:
		if not (slot.seed_val in out):
			out.append(slot.seed_val)
	return out


func test_every_seed_is_played_from_both_seats() -> void:
	var slots: Array = BalanceMatchSchedule.slots(MAP, 2, 0, false)
	assert_eq(slots.size(), 4, "two seeds, two seatings each")
	var seats: Array[int] = []
	for slot: BalanceMatchSchedule.Slot in slots:
		seats.append(slot.seat)
	assert_eq(seats, [0, 1, 0, 1] as Array[int], "the pair of seatings meets on one seed")


func test_a_mirror_is_played_from_one_seat() -> void:
	# Swapping the seats of two identical sides replays the identical match, so
	# the second seating is not a measurement — it is the same row twice.
	var slots: Array = BalanceMatchSchedule.slots(MAP, 3, 0, true)
	assert_eq(slots.size(), 3, "one seating per seed")
	for slot: BalanceMatchSchedule.Slot in slots:
		assert_eq(slot.seat, 0)


func test_an_offset_walks_the_same_range_further_along() -> void:
	var whole := _seeds(BalanceMatchSchedule.slots(MAP, 4, 0, false))
	var tail := _seeds(BalanceMatchSchedule.slots(MAP, 2, 2, false))
	assert_eq(tail, whole.slice(2), "a shard plays the seeds the whole run would have")


func test_the_board_moves_the_range() -> void:
	# Two boards in one sweep must not be correlated, or a finding about one is
	# partly a finding about the other.
	var here := _seeds(BalanceMatchSchedule.slots(MAP, 4, 0, false))
	var there := _seeds(BalanceMatchSchedule.slots("clash", 4, 0, false))
	assert_ne(here, there)


func test_a_pinned_seed_is_the_whole_range() -> void:
	var slots: Array = BalanceMatchSchedule.slots(MAP, 8, 0, false, 4242)
	assert_eq(_seeds(slots), [4242] as Array[int], "the row being replayed, and nothing else")
	assert_eq(slots.size(), 2, "still from both seats")
