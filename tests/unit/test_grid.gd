extends GutTest
## The board's geometry: the Manhattan diamond every ring in the game is cut to.
## Pure and static, so the shape is checked with no board under it.
##
## Worth pinning because the *order* is part of the answer. A threat overlay is
## painted in the order its cells are first seen, so a walk that emitted the same
## set differently would repaint the board without changing a single cell of it.


func test_a_radius_of_zero_is_the_origin_alone() -> void:
	assert_eq(Grid.ring_offsets(0, 0), [Vector2i.ZERO] as Array[Vector2i])


## A low bound of 0 keeps the centre: a unit that can shoot the cell it stands on
## is inside its own ring.
func test_a_ring_from_zero_includes_the_origin() -> void:
	assert_has(Grid.ring_offsets(0, 2), Vector2i.ZERO)
	assert_has(Grid.ring_offsets(0, 1), Vector2i.ZERO)


## Columns west to east, and each column north to south.
func test_a_full_diamond_is_emitted_column_by_column() -> void:
	var expected: Array[Vector2i] = [
		Vector2i(-2, 0),
		Vector2i(-1, -1),
		Vector2i(-1, 0),
		Vector2i(-1, 1),
		Vector2i(0, -2),
		Vector2i(0, -1),
		Vector2i(0, 0),
		Vector2i(0, 1),
		Vector2i(0, 2),
		Vector2i(1, -1),
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(2, 0),
	]
	assert_eq(Grid.ring_offsets(0, 2), expected)


## An indirect weapon's band: the low bound punches the middle out, and the cells
## that survive keep the order they were emitted in.
func test_a_low_bound_drops_the_cells_inside_it() -> void:
	var expected: Array[Vector2i] = [
		Vector2i(-3, 0),
		Vector2i(-2, -1),
		Vector2i(-2, 0),
		Vector2i(-2, 1),
		Vector2i(-1, -2),
		Vector2i(-1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, 2),
		Vector2i(0, -3),
		Vector2i(0, -2),
		Vector2i(0, 2),
		Vector2i(0, 3),
		Vector2i(1, -2),
		Vector2i(1, -1),
		Vector2i(1, 1),
		Vector2i(1, 2),
		Vector2i(2, -1),
		Vector2i(2, 0),
		Vector2i(2, 1),
		Vector2i(3, 0),
	]
	assert_eq(Grid.ring_offsets(2, 3), expected)


## Every offset is inside the band it was asked for, on the one distance this
## board measures.
func test_every_offset_lies_in_the_band() -> void:
	for offset in Grid.ring_offsets(2, 4):
		var distance := Grid.manhattan(Vector2i.ZERO, offset)
		assert_between(distance, 2, 4)


## A band with nothing in it is empty rather than wrong: an unarmed unit asks for
## one every time the threat map is built.
func test_a_low_bound_above_the_high_bound_reaches_nothing() -> void:
	assert_eq(Grid.ring_offsets(3, 2).size(), 0)


## The band is a property of the weapon, not of the cell it fires from, so the
## same one is handed back rather than rebuilt: a threat map asks for it once per
## firing cell per enemy. What comes back is shared, which is why no caller may
## write to it.
func test_the_same_band_is_handed_back_rather_than_rebuilt() -> void:
	var band := Grid.ring_offsets(1, 3)
	assert_true(is_same(Grid.ring_offsets(1, 3), band), "the band was rebuilt per ask")


## Handing the same array back must not change which cell comes first, since a
## threat overlay is painted in the order its cells are first seen.
func test_a_remembered_band_keeps_its_emission_order() -> void:
	var first_ask := Grid.ring_offsets(0, 2).duplicate()
	Grid.ring_offsets(2, 3)
	assert_eq(Grid.ring_offsets(0, 2), first_ask)
