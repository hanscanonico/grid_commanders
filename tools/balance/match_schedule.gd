class_name BalanceMatchSchedule
extends RefCounted
## Which matches one matchup plays: the seeds, and from which seat each is
## played.
##
## Shared by every preset over the one match loop — the Balance Lab and the AI
## Arena — because "the same spec plays the same matches" is what makes their
## rows comparable at all, and a seed formula written twice is one that
## eventually disagrees. The Lab's shards already depend on it: `--seed-offset=`
## exists so a split run asks for a slice of this range instead of deriving it
## again (arena plan AR2).
##
## Node-free, like the rest of the harness.

const SEED_BASE := 1000


## One match to play: which seeded board, and which way round the two sides sit.
class Slot:
	var seed_val := 0
	## 0 seats the matchup as written, 1 swaps it.
	var seat := 0


## Every match of one matchup, in play order.
##
## Paired seeds: both seatings meet on identical luck, and the seed varies by
## board so two maps in one sweep are not correlated. `offset` walks the same
## range further along, so the shards of a split run play exactly the seeds the
## whole run would have.
##
## A mirror — two identical sides — is played from one seat only: swapping the
## seats of one replays the identical match, seed and all. That is not a lost
## measurement, since with both sides the same the first seat's win rate *is*
## what the seat is worth.
##
## `pinned` replaces the range with the single seed a suspicious row is replayed
## at; -1 plays the range.
static func slots(
	map_name: String, count: int, offset: int, mirror: bool, pinned: int = -1
) -> Array[Slot]:
	var result: Array[Slot] = []
	for step in 1 if pinned >= 0 else count:
		var seed_val := pinned if pinned >= 0 else seed_at(map_name, offset + step)
		for seat in 1 if mirror else 2:
			var slot := Slot.new()
			slot.seed_val = seed_val
			slot.seat = seat
			result.append(slot)
	return result


## The seed at one index of a board's range.
static func seed_at(map_name: String, index: int) -> int:
	return SEED_BASE + index + hash(map_name) % 1000
