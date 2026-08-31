class_name CommanderPicks
extends RefCounted
## The one rule over a match's `seat -> commander id` picks: a general takes the
## field for at most one army. Two seats commanding the same person is a board
## the story cannot mean, and — since a side wears its commander's faction
## (`SideIdentity`) — one the player reads as two armies in one livery.
##
## "No Commander" is the absence of a general rather than one of them, so every
## seat may hold it at once: a no-CO match stays the pre-commander game exactly.
##
## Node-free and database-free, like `MatchRequest` beside it: the picker, the
## menu and the flag grammar all ask here, and nothing re-derives the rule.
##
## The Balance Lab's `--red=` / `--blue=` grammar is deliberately outside it. A
## mirror — one commander against themself — is a row of its own in every report
## (`MatchSchedule`), so a duplicate there is the measurement and not a mistake.


## Whether `id` names a general at all — the database-free half of
## `CommanderDB.is_playable`, which additionally answers whether the id ships,
## a question no flag and no pick list can see without a database.
static func is_general(id: StringName) -> bool:
	return id != &"" and id != CommanderType.NEUTRAL_ID


## Which seat `picks` has already given `id` to, or 0 for nobody. Ignores the
## seat at `besides`, which is never in its own way. A seat rather than a bare
## yes/no because a refusal that names the army holding the general is the
## difference between a dead portrait and an answered one.
static func holder(picks: Dictionary, id: StringName, besides: int = 0) -> int:
	if is_general(id):
		for seat: int in picks:
			if seat != besides and picks[seat] == id:
				return seat
	return 0


## Whether the seat at `seat` may command `id`.
static func available(picks: Dictionary, seat: int, id: StringName) -> bool:
	return holder(picks, id, seat) == 0


## `picks` with every repeat after the first dropped, walked in `order` so the
## seat that keeps a contested general is the earlier one rather than whichever
## the dictionary happens to list first. A dropped seat is *absent* rather than
## neutral, which is already how a seat with no entry plays without a commander.
##
## Says so out loud: a match nobody meant is worth a line, and silently seating
## two armies under one general is what this exists to prevent.
static func deduplicated(picks: Dictionary, order: Array[int]) -> Dictionary:
	var settled: Dictionary = {}
	var walk: Array[int] = order.duplicate()
	for seat: int in picks:
		if not walk.has(seat):
			walk.append(seat)
	for seat: int in walk:
		if not picks.has(seat):
			continue
		var id: StringName = picks[seat]
		if available(settled, seat, id):
			settled[seat] = id
		else:
			push_error(
				(
					"match: %s can command only one army; seat %d plays without a commander"
					% [id, seat]
				)
			)
	return settled
