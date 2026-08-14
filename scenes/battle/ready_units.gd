class_name ReadyUnits
extends RefCounted
## Who on the side in hand can still act, and which of them the cursor visits
## next. One authority for both, because they are one order: the End Turn guard
## names the units it is about to waste and N walks them, so a second opinion
## about "next" would walk a different list from the one the guard just printed.
##
## Node-free and pure — statics over a GameState, no scene and no cursor state —
## so the walk is checked without booting the battle, on the same terms
## `PathArrow.segments` and `SeatStrip.normalised_sides` are.


## The side on turn's units that have not acted, in reading order. A carried
## unit is none of them: it cannot act until it is dropped, and it is standing
## in its carrier's cell rather than its own.
static func of(game: GameState) -> Array[Unit]:
	var ready: Array[Unit] = []
	for unit in game.units:
		if unit.team == game.current_team and not unit.acted and unit.carrier == null:
			ready.append(unit)
	ready.sort_custom(func(a: Unit, b: Unit) -> bool: return precedes(a.cell, b.cell))
	return ready


## The first ready unit strictly after `cell`, wrapping to the first — so a
## repeated press walks every one of them and comes back round. `null` means
## nothing is ready, which is the caller's cue to say so out loud.
static func after(game: GameState, cell: Vector2i) -> Unit:
	var ready := of(game)
	if ready.is_empty():
		return null
	for unit in ready:
		if precedes(cell, unit.cell):
			return unit
	return ready[0]


## Reading order, top-left to bottom-right, stated once: the list and the walk
## through it are the same order or the walk skips somebody.
static func precedes(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
