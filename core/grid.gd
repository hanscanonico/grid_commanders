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
