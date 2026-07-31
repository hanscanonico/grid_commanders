extends GutTest
## The movement path's geometry: a route turned into per-cell bars, joints and a
## head. Pure and static, like TransitionInput and SeatStrip.normalised_sides, so
## the shape the board draws is checked without standing up a scene.
##
## Worth its own suite because the arrow is the one overlay whose meaning is in
## its *shape* rather than in which cells it covers. A head on the wrong cell
## points the unit back where it came from, and an arm dropped at a corner leaves
## a route with a hole in it — neither of which any cell-set check would notice.

const RIGHT := Vector2i.RIGHT
const LEFT := Vector2i.LEFT
const DOWN := Vector2i.DOWN
const UP := Vector2i.UP


func _straight() -> Array[Vector2i]:
	return [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i]


## An L: two steps east, then one south.
func _corner() -> Array[Vector2i]:
	return [Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)] as Array[Vector2i]


## A unit that has been picked up but not pointed anywhere yet: `planned_path` is
## the cell it stands on, and a lone joint block drawn under it would read as a
## marker rather than a route.
func test_a_path_of_one_cell_draws_nothing() -> void:
	assert_eq(PathArrow.segments([Vector2i(1, 1)] as Array[Vector2i]).size(), 0)


func test_an_empty_path_draws_nothing() -> void:
	assert_eq(PathArrow.segments([] as Array[Vector2i]).size(), 0)


func test_every_cell_of_the_route_gets_a_segment() -> void:
	var segments := PathArrow.segments(_straight())
	assert_eq(segments.size(), 3)
	assert_eq(segments[0].cell, Vector2i(1, 1))
	assert_eq(segments[2].cell, Vector2i(3, 1))


## The origin reaches forward only. It has nowhere behind it to join to, and an
## arm drawn there would run the route out of the cell the unit is standing in.
func test_the_origin_has_one_arm_pointing_along_the_route() -> void:
	assert_eq(PathArrow.segments(_straight())[0].arms, [RIGHT] as Array[Vector2i])


## A cell in the middle joins both ways, which is what makes the bars meet rather
## than leaving a gap at each cell boundary.
func test_a_middle_cell_joins_both_neighbours() -> void:
	assert_eq(PathArrow.segments(_straight())[1].arms, [LEFT, RIGHT] as Array[Vector2i])


func test_the_last_cell_reaches_only_backwards() -> void:
	assert_eq(PathArrow.segments(_straight())[2].arms, [LEFT] as Array[Vector2i])


## The turn: the corner cell's two arms are perpendicular, which is the square
## joint the polyline could not draw.
func test_a_corner_joins_perpendicular_neighbours() -> void:
	assert_eq(PathArrow.segments(_corner())[1].arms, [LEFT, DOWN] as Array[Vector2i])


## The head points the way the unit is travelling — the reverse of the arm that
## reaches back — so a route ending southward ends in a southward arrowhead.
func test_the_head_points_the_way_the_unit_travels() -> void:
	assert_eq(PathArrow.segments(_corner())[2].head, DOWN)
	assert_eq(PathArrow.segments(_straight())[2].head, RIGHT)


func test_only_the_last_cell_carries_a_head() -> void:
	for segment in PathArrow.segments(_straight()).slice(0, 2):
		assert_eq(segment.head, Vector2i.ZERO)


## A route that doubles back: the head still names the final step, not the net
## displacement, which is zero here.
func test_a_route_that_doubles_back_still_heads_along_its_last_step() -> void:
	var path := [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 1)] as Array[Vector2i]
	assert_eq(PathArrow.segments(path)[2].head, LEFT)


## The bar runs from the cell's centre to the edge it shares with that neighbour,
## and is BAR wide across. Checked on both axes and in both directions, because
## half the arms run negative and a position-and-size rect would come out inside
## out for those.
func test_a_bar_runs_from_the_centre_to_the_shared_edge() -> void:
	var centre := Vector2(8, 8)  # cell (0, 0)
	var half := PathArrow.TILE / 2.0
	var thick := PathArrow.BAR / 2.0
	assert_eq(PathArrow.bar_rect(centre, RIGHT), Rect2(8, 8 - thick, half, PathArrow.BAR))
	assert_eq(PathArrow.bar_rect(centre, LEFT), Rect2(8 - half, 8 - thick, half, PathArrow.BAR))
	assert_eq(PathArrow.bar_rect(centre, DOWN), Rect2(8 - thick, 8, PathArrow.BAR, half))
	assert_eq(PathArrow.bar_rect(centre, UP), Rect2(8 - thick, 8 - half, PathArrow.BAR, half))


## The arrowhead is a triangle whose tip leads and whose base straddles the
## centre, so it always sits inside the destination cell rather than spilling
## into the one beyond it.
func test_the_arrowhead_leads_from_the_centre_and_stays_in_the_cell() -> void:
	var centre := Vector2(8, 8)
	var points := PathArrow.head_points(centre, DOWN)
	assert_eq(points.size(), 3)
	assert_eq(points[0], centre + Vector2(0, PathArrow.HEAD_LEN))
	assert_lt(PathArrow.HEAD_LEN, PathArrow.TILE / 2.0)
	assert_eq(points[1].y, centre.y)
	assert_eq(points[2].y, centre.y)
	assert_eq(absf(points[1].x - points[2].x), PathArrow.HEAD_HALF * 2.0)
