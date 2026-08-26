extends GutTest
## The touch build's hit rectangle: how far a control drawn smaller than a finger
## may grow, and where it must stop. Pure and static, like PathArrow.segments and
## SeatStrip.normalised_sides, so the rule is checked without standing up a scene.
##
## Worth its own suite because the failure it guards against is silent: two chips
## that both claim the pixel between them still *look* right, and the one drawn
## last simply eats its neighbour's taps.

const MIN := 44.0


func _chip(x: float, y: float) -> Rect2:
	return Rect2(x, y, 8, 7)


func test_a_lone_control_reaches_the_minimum_in_both_axes() -> void:
	var grown := TouchTarget.inflation(_chip(100, 100), [] as Array[Rect2], MIN)
	assert_almost_eq(grown.size.x, MIN, 0.01)
	assert_almost_eq(grown.size.y, MIN, 0.01)


func test_it_grows_around_the_control_it_was_drawn_for() -> void:
	var host := _chip(100, 100)
	var grown := TouchTarget.inflation(host, [] as Array[Rect2], MIN)
	assert_almost_eq(grown.get_center().x, host.get_center().x, 0.01)
	assert_almost_eq(grown.get_center().y, host.get_center().y, 0.01)


func test_a_control_already_big_enough_is_left_alone() -> void:
	var host := Rect2(0, 0, 60, 50)
	assert_eq(TouchTarget.inflation(host, [] as Array[Rect2], MIN), host)


## The HUD's chip row: four of them 4 px apart. Each takes half that gap and no
## more, so the pixel between two chips belongs to exactly one of them.
func test_a_neighbour_in_the_row_is_never_crossed() -> void:
	var host := _chip(100, 10)
	var right := _chip(112, 10)
	var grown := TouchTarget.inflation(host, [right] as Array[Rect2], MIN)
	assert_almost_eq(grown.end.x, 110.0, 0.01)
	assert_true(grown.end.x <= right.position.x, "a chip may not reach its neighbour")


## A row of chips still has the whole height of the screen to grow into, which is
## where a 7 px chip gets its finger from.
func test_a_horizontal_neighbour_does_not_block_the_other_axis() -> void:
	var grown := TouchTarget.inflation(_chip(100, 10), [_chip(112, 10)] as Array[Rect2], MIN)
	assert_almost_eq(grown.size.y, MIN, 0.01)


## The seat strip: four rows of segments stacked 20 px apart. The row above is not
## a sibling of the segment, which is why `_blockers` walks the ancestors too — it
## takes half the gap to that row and no more, and the rest of what it wanted goes
## downward, where in this fixture nothing is standing.
func test_a_row_above_stops_the_growth_upward() -> void:
	var host := Rect2(10, 100, 40, 16)
	var above := Rect2(10, 80, 40, 16)
	var grown := TouchTarget.inflation(host, [above] as Array[Rect2], MIN)
	assert_almost_eq(grown.position.y, 98.0, 0.01)
	assert_almost_eq(grown.size.y, MIN, 0.01)


## Rows above and below: neither may be crossed, so the segment keeps only the
## halves of the two gaps and stays well short of the minimum. The honest reading
## of a dense panel — the rest would have to come out of the drawn layout.
func test_a_row_either_side_bounds_the_growth_both_ways() -> void:
	var host := Rect2(10, 100, 40, 16)
	var rows := [Rect2(10, 80, 40, 16), Rect2(10, 120, 40, 16)] as Array[Rect2]
	var grown := TouchTarget.inflation(host, rows, MIN)
	assert_almost_eq(grown.position.y, 98.0, 0.01)
	assert_almost_eq(grown.end.y, 118.0, 0.01)


## Buttons packed edge to edge — an action menu's rows — have no free space to
## claim, and the honest answer is that they gain nothing rather than that they
## steal a neighbour's row.
func test_a_gapless_list_gains_nothing_in_that_axis() -> void:
	var host := Rect2(0, 22, 90, 22)
	var neighbours := [Rect2(0, 0, 90, 22), Rect2(0, 44, 90, 22)] as Array[Rect2]
	var grown := TouchTarget.inflation(host, neighbours, MIN)
	assert_almost_eq(grown.position.y, 22.0, 0.01)
	assert_almost_eq(grown.size.y, 22.0, 0.01)


## A chip on the top bar has nothing above it but the edge of the canvas, so all
## of its growth goes down over the board rather than half of it off screen.
func test_growth_the_screen_refuses_goes_to_the_other_side() -> void:
	var host := Rect2(300, 6, 12, 11)
	var grown := TouchTarget.inflation(host, [] as Array[Rect2], MIN, Rect2(0, 0, 640, 360))
	assert_almost_eq(grown.position.y, 0.0, 0.01)
	assert_almost_eq(grown.size.y, MIN, 0.01)


## A container the control sits inside overlaps it in both axes and is not a
## neighbour at all: clamping to it would leave every control in a panel unable
## to grow.
func test_an_enclosing_rect_is_not_a_neighbour() -> void:
	var grown := TouchTarget.inflation(
		_chip(100, 100), [Rect2(0, 0, 640, 360)] as Array[Rect2], MIN
	)
	assert_almost_eq(grown.size.x, MIN, 0.01)
	assert_almost_eq(grown.size.y, MIN, 0.01)


## Growing both axes at once can reach a control neither axis' own gap measured —
## one sitting diagonally away. Fuzzed rather than reasoned about, because that is
## how it was found: 105 of 20,000 random boards crossed a diagonal neighbour before
## `_retreat` existed.
func test_no_board_lets_a_hit_rectangle_cross_a_neighbour() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260826
	var crossings := 0
	var lost := 0
	for _case in 20000:
		var host := Rect2(
			rng.randi_range(0, 120),
			rng.randi_range(0, 120),
			rng.randi_range(4, 30),
			rng.randi_range(4, 30)
		)
		var neighbours: Array[Rect2] = []
		for _other in rng.randi_range(1, 4):
			var other := Rect2(
				rng.randi_range(0, 160),
				rng.randi_range(0, 160),
				rng.randi_range(4, 30),
				rng.randi_range(4, 30)
			)
			if not other.intersects(host):
				neighbours.append(other)
		var grown := TouchTarget.inflation(host, neighbours, MIN)
		if not grown.encloses(host):
			lost += 1
		for other: Rect2 in neighbours:
			if grown.intersects(other):
				crossings += 1
	assert_eq(crossings, 0, "a hit rectangle never reaches into a neighbour")
	assert_eq(lost, 0, "and never retreats inside the control it was drawn for")
