extends GutTest
## BoardSpace3D: where the flat board's coordinates land on the 3D one, how high
## a unit stands, and which way an arrow key walks once the camera has turned.
## Pure arithmetic over MapData, so every answer is checked without a scene.

## Plains, a mountain, sea: one row read west to east.
const ROW := "[terrain]\n.MS"


func _map(text: String) -> MapData:
	return MapData.parse(text, Fixture.terrain_db())


func test_a_sprite_position_lands_on_its_cell_centre() -> void:
	var centre := BattleView.cell_center(Vector2i(3, 5))
	assert_eq(BoardSpace3D.plane_of(centre), BoardSpace3D.cell_centre(Vector2i(3, 5)))
	assert_eq(BoardSpace3D.cell_at(BoardSpace3D.cell_centre(Vector2i(3, 5))), Vector2i(3, 5))


func test_the_board_units_are_one_cell_each() -> void:
	assert_eq(BoardSpace3D.PX_PER_CELL, float(BattleView.TILE), "one world unit is one flat cell")


func test_ground_ships_and_peaks_stand_at_their_own_heights() -> void:
	var map := _map(ROW)
	assert_eq(BoardSpace3D.stand_at(map, Vector2(0.5, 0.5)), BoardSpace3D.LAND_TOP)
	assert_eq(BoardSpace3D.stand_at(map, Vector2(1.5, 0.5)), BoardSpace3D.MOUNTAIN_SHOULDER)
	assert_eq(BoardSpace3D.stand_at(map, Vector2(2.5, 0.5)), BoardSpace3D.SEA_TOP)


## A unit walking off a mountain rolls down its flank: every height between two
## centres lies between theirs, and it rises the whole way.
func test_a_walk_between_cells_eases_rather_than_steps() -> void:
	var map := _map(ROW)
	var last := BoardSpace3D.stand_at(map, Vector2(0.5, 0.5))
	for i in range(1, 11):
		var h := BoardSpace3D.stand_at(map, Vector2(0.5 + i / 10.0, 0.5))
		assert_true(h >= last, "the climb never dips at x=%.1f" % (0.5 + i / 10.0))
		last = h
	assert_almost_eq(last, BoardSpace3D.MOUNTAIN_SHOULDER, 0.0001)


func test_off_board_heights_read_the_nearest_edge_cell() -> void:
	var map := _map(ROW)
	assert_eq(BoardSpace3D.stand_at(map, Vector2(-3.0, 0.5)), BoardSpace3D.LAND_TOP)
	assert_eq(BoardSpace3D.stand_at(map, Vector2(9.0, 0.5)), BoardSpace3D.SEA_TOP)


## A peak stands well above the shoulder a unit is posed on, and a click on it
## must pick the mountain rather than the cell behind.
func test_a_pointer_meets_a_mountain_high_on_its_peaks() -> void:
	var map := _map(ROW)
	assert_eq(BoardSpace3D.pick_top(map, Vector2i(1, 0)), BoardSpace3D.MOUNTAIN_PICK)
	assert_true(BoardSpace3D.MOUNTAIN_PICK > BoardSpace3D.MOUNTAIN_SHOULDER)
	assert_eq(BoardSpace3D.pick_top(map, Vector2i(2, 0)), BoardSpace3D.SEA_TOP)
	assert_eq(BoardSpace3D.pick_top(map, Vector2i(7, 7)), BoardSpace3D.LAND_TOP, "off the board")


func test_the_arrow_keys_keep_their_sense_as_the_camera_turns() -> void:
	var up := Vector2i(0, -1)
	var right := Vector2i(1, 0)
	assert_eq(BoardSpace3D.turned(up, 0), up, "looking north, up walks north")
	assert_eq(BoardSpace3D.turned(up, 1), Vector2i(-1, 0), "looking west, up walks west")
	assert_eq(BoardSpace3D.turned(up, 2), Vector2i(0, 1), "looking south, up walks south")
	assert_eq(BoardSpace3D.turned(up, 3), Vector2i(1, 0), "looking east, up walks east")
	assert_eq(BoardSpace3D.turned(right, 1), Vector2i(0, -1), "and right is a quarter clockwise")


func test_turns_wrap_both_ways() -> void:
	var up := Vector2i(0, -1)
	assert_eq(BoardSpace3D.turned(up, 4), up)
	assert_eq(BoardSpace3D.turned(up, -1), BoardSpace3D.turned(up, 3))


## Every terrain the data ships stands somewhere between the sea and the peaks,
## so the pointer's ray march — which starts above the shoulder and ends below
## the sea — can meet any cell.
func test_every_terrain_stands_inside_the_pointer_march() -> void:
	var map := _map("[terrain]\n.MS_~+=F*")
	for x in map.width:
		var top := BoardSpace3D.pick_top(map, Vector2i(x, 0))
		assert_between(top, BoardSpace3D.SEA_TOP, BoardSpace3D.PICK_CEILING, "pick top at %d" % x)
	for terrain: TerrainType in Fixture.terrain_db().all():
		var top := BoardSpace3D.stand_top(terrain.id)
		assert_between(
			top, BoardSpace3D.SEA_TOP, BoardSpace3D.MOUNTAIN_SHOULDER, String(terrain.id)
		)
		assert_true(BoardSpace3D.ground_top(terrain.id) > BoardSpace3D.SLAB_BOTTOM)
