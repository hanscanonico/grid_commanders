extends GutTest
## The autotile mask arithmetic: which sheet a terrain cell draws from and
## which connection variant it wears. Pure statics over MapData, like
## PathArrow.segments, so the connected look the board paints is checked
## without a scene — BattleView only indexes what these return.

const N := TerrainAutotiles.BIT_N
const E := TerrainAutotiles.BIT_E
const S := TerrainAutotiles.BIT_S
const W := TerrainAutotiles.BIT_W


func _map(rows: Array[String]) -> MapData:
	return MapData.parse("[terrain]\n" + "\n".join(rows), Fixture.terrain_db())


func _family(rows: Array[String], cell: Vector2i) -> TerrainAutotiles.Family:
	return TerrainAutotiles.family(_map(rows), cell)


func _mask(rows: Array[String], cell: Vector2i) -> int:
	return TerrainAutotiles.mask(_map(rows), cell)


# --- roads -------------------------------------------------------------------


func test_a_road_corner_joins_its_two_neighbours() -> void:
	var rows: Array[String] = ["....", ".==.", "..=.", "...."]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.ROADS)
	assert_eq(_mask(rows, Vector2i(1, 1)), E)
	assert_eq(_mask(rows, Vector2i(2, 1)), W | S)
	assert_eq(_mask(rows, Vector2i(2, 2)), N)


func test_a_road_junction_wears_every_connected_bit() -> void:
	var rows: Array[String] = ["..=..", ".===.", "..=.."]
	assert_eq(_mask(rows, Vector2i(2, 1)), N | E | S | W)


func test_a_road_connects_into_a_bridge() -> void:
	var rows: Array[String] = [".....", ".=+~.", "....."]
	assert_eq(_mask(rows, Vector2i(1, 1)), E)


func test_an_isolated_road_keeps_the_east_west_fallback_variant() -> void:
	var rows: Array[String] = ["...", ".=.", "..."]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.ROADS)
	assert_eq(_mask(rows, Vector2i(1, 1)), 0)
	assert_eq(TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.ROADS, 0), Vector2i.ZERO)


## Off-board counts as the cell's own terrain, so an edge road runs off the
## map the way the backdrop's darkened continuation implies.
func test_an_edge_road_counts_the_off_board_side_as_more_road() -> void:
	var rows: Array[String] = ["==.", "..."]
	assert_eq(_mask(rows, Vector2i(0, 0)), N | E | W)


# --- bridges -----------------------------------------------------------------


func test_a_bridge_between_roads_lies_east_west() -> void:
	var rows: Array[String] = [".....", ".=+=.", "....."]
	assert_eq(_family(rows, Vector2i(2, 1)), TerrainAutotiles.Family.BRIDGES)
	assert_eq(_mask(rows, Vector2i(2, 1)), E | W)
	assert_eq(TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.BRIDGES, E | W), Vector2i(0, 0))


func test_a_bridge_with_no_road_beside_lies_north_south() -> void:
	var rows: Array[String] = [".~.", ".+.", ".~."]
	assert_eq(_mask(rows, Vector2i(1, 1)), N | S)
	assert_eq(TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.BRIDGES, N | S), Vector2i(1, 0))


# --- woods -------------------------------------------------------------------


func test_a_wood_joins_only_more_wood() -> void:
	var rows: Array[String] = [".F.", "=FF", ".M."]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.WOODS)
	# The road west and the mountain south are ground the tree line ends against.
	assert_eq(_mask(rows, Vector2i(1, 1)), N | E)


func test_a_lone_wood_wears_the_variant_with_no_side_continued() -> void:
	var rows: Array[String] = ["...", ".F.", "..."]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.WOODS)
	assert_eq(_mask(rows, Vector2i(1, 1)), 0)


func test_a_wood_walled_in_by_wood_keeps_the_base_atlas_tile() -> void:
	var rows: Array[String] = [".F.", "FFF", ".F."]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.NONE)
	assert_eq(_mask(rows, Vector2i(1, 1)), N | E | S | W)


## Off-board reads as the cell's own terrain, so a wood on the rim grows no
## tree line against the backdrop — the same rule the roads and the sea obey.
func test_a_wood_on_the_board_rim_reads_the_off_board_side_as_more_wood() -> void:
	var rows: Array[String] = ["FF", "F."]
	assert_eq(_family(rows, Vector2i(0, 0)), TerrainAutotiles.Family.NONE)
	assert_eq(_mask(rows, Vector2i(0, 0)), N | E | S | W)


# --- the sheet grid ----------------------------------------------------------


func test_atlas_coords_walk_the_four_by_four_grid_row_major() -> void:
	assert_eq(TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.ROADS, 7), Vector2i(3, 1))
	assert_eq(TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.COAST, 12), Vector2i(0, 3))
	assert_eq(TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.RIVERS, 15), Vector2i(3, 3))


# --- off the board -----------------------------------------------------------
## BattleView's backdrop paints a ring of cells beyond the edges, so the same
## statics are asked about cells the board does not hold. Every read is clamped
## to the rim, which is the rim rule stated once: the ring continues the edge.


func test_an_off_board_cell_reads_the_nearest_edge_terrain() -> void:
	var rows: Array[String] = ["=..", "...", "..."]
	assert_eq(TerrainAutotiles.terrain_id(_map(rows), Vector2i(-3, -2)), &"road")


func test_the_ring_beyond_an_edge_road_keeps_the_road_running_off_the_map() -> void:
	var rows: Array[String] = ["==.", "...", "..."]
	assert_eq(_family(rows, Vector2i(-2, 0)), TerrainAutotiles.Family.ROADS)
	assert_eq(_mask(rows, Vector2i(-2, 0)), N | E | W)


## A sea rim cell wears its coast, but the ring outside it is open water: the
## land is inland, so nothing off the board breaks surf against it.
func test_the_ring_beyond_a_coastal_edge_is_open_water() -> void:
	var rows: Array[String] = ["S..", "S..", "S.."]
	assert_eq(_family(rows, Vector2i(0, 1)), TerrainAutotiles.Family.COAST)
	assert_eq(_family(rows, Vector2i(-1, 1)), TerrainAutotiles.Family.SEA)
