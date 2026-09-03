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


## Every band ever asked for, keyed by its bounds. A band belongs to the weapon
## and not to the cell it is fired from, so the threat map asks for the same
## handful of them once per firing cell per enemy — thousands of times over one
## large board.
static var _bands: Dictionary[Vector2i, Array] = {}


## The offsets of the [low, high] Manhattan diamond around the origin — the shape
## every ring in the game is cut to, handed over as offsets so a caller adds its
## own centre and applies its own filter.
##
## The emission order is part of the answer: dx ascending outermost, dy ascending
## within each column. A threat overlay is painted in the order its cells are
## first seen, so a reordering here would repaint the board.
##
## One array is handed to every ask for the same bounds, so it is frozen rather
## than copied per call — sharing it is the point. A caller that needs to write
## duplicates first.
static func ring_offsets(low: int, high: int) -> Array[Vector2i]:
	var bounds := Vector2i(low, high)
	if not _bands.has(bounds):
		var built := _build_band(low, high)
		built.make_read_only()
		_bands[bounds] = built
	var band: Array[Vector2i] = _bands[bounds]
	return band


## Walks the diamond that bounds the band and drops the cells inside `low`. Runs
## once per distinct pair of bounds in a process; ring_offsets() remembers it.
static func _build_band(low: int, high: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	for dx in range(-high, high + 1):
		var span := high - absi(dx)
		for dy in range(-span, span + 1):
			if absi(dx) + absi(dy) < low:
				continue
			offsets.append(Vector2i(dx, dy))
	return offsets
