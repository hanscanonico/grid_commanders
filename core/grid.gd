class_name Grid
extends RefCounted
## The board's geometry, with no board in it.
##
## This game measures distance one way: four-directionally, so a diagonal is two
## steps to everything that counts — movement, every firing ring, sight, supply
## reach and the planner's goals. Ask here rather than spelling the arithmetic
## again, so a distance can never mean two things in two layers.


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## The offsets of the [low, high] Manhattan diamond around the origin — the shape
## every ring in the game is cut to, handed over as offsets so a caller adds its
## own centre and applies its own filter.
##
## The emission order is part of the answer: dx ascending outermost, dy ascending
## within each column. A threat overlay is painted in the order its cells are
## first seen, so a reordering here would repaint the board.
##
## absi(dx) + absi(dy) is manhattan(Vector2i.ZERO, Vector2i(dx, dy)), inlined:
## this walk is per-cell in the board's hottest fill and a call here is not free.
static func ring_offsets(low: int, high: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	for dx in range(-high, high + 1):
		var span := high - absi(dx)
		for dy in range(-span, span + 1):
			if absi(dx) + absi(dy) < low:
				continue
			offsets.append(Vector2i(dx, dy))
	return offsets
