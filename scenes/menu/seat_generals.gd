class_name SeatGenerals
extends RefCounted
## Who commands each seat the board deals — the seat strip's general column, held
## apart from its widgets so the bookkeeping reads, and is checked, without a
## scene. seat -> commander id; a seat missing here commands nobody.
##
## Every seat the board deals keeps its pick, a closed one included: closing a
## seat takes its army off the table, not its general off the row, so reopening it
## brings the same general back — and counting it in `besides` is what keeps two
## seats from ever sharing one.

var _by_seat: Dictionary = {}


## The general `seat` holds, or `CommanderType.NEUTRAL_ID`.
func of(seat: int) -> StringName:
	return _by_seat.get(seat, CommanderType.NEUTRAL_ID)


## Every other seat's general, seat-keyed — the ones `seat` may not take.
func besides(seat: int) -> Dictionary:
	var others := _by_seat.duplicate()
	others.erase(seat)
	return others


## The generals of `seats`, seat-keyed — over the seats that play, what a match
## request's commanders take.
func over(seats: Array[int]) -> Dictionary:
	var picked: Dictionary = {}
	for seat in seats:
		if _by_seat.has(seat):
			picked[seat] = _by_seat[seat]
	return picked


## Takes `picks` on, over seats 1..`count`; a pick for a seat the board does not
## deal is nobody's.
func assign(picks: Dictionary, count: int) -> void:
	for seat: int in picks:
		if seat >= 1 and seat <= count:
			_by_seat[seat] = picks[seat]


## Drops the generals of seats past `count`, when a smaller board is picked.
func keep(count: int) -> void:
	for seat: int in _by_seat.keys():
		if seat < 1 or seat > count:
			_by_seat.erase(seat)
