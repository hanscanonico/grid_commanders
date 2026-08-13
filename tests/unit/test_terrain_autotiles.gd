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


# --- rivers ------------------------------------------------------------------


func test_a_river_meeting_the_sea_flows_into_it() -> void:
	var rows: Array[String] = [".S.", ".~.", ".=."]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.RIVERS)
	# North is sea; the road to the south is not a river join without a bridge.
	assert_eq(_mask(rows, Vector2i(1, 1)), N)


func test_a_river_flows_into_a_port() -> void:
	var rows: Array[String] = ["...", "P~.", "..."]
	assert_eq(_mask(rows, Vector2i(1, 1)), W)


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


# --- sea and its coastline ---------------------------------------------------


func test_the_sea_coasts_against_land_and_not_against_water() -> void:
	var rows: Array[String] = [".F.", "~S=", ".S."]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.COAST)
	# Woods north and road east are land; the river west and sea south are not.
	assert_eq(_mask(rows, Vector2i(1, 1)), N | E)


func test_open_water_keeps_the_base_atlas_tile() -> void:
	var rows: Array[String] = ["SSS", "SSS", "SSS"]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.NONE)


func test_the_board_rim_grows_no_shoreline() -> void:
	var rows: Array[String] = ["SSS", "S.S", "SSS"]
	# The rim cell coasts only against the land beside it, never the board edge.
	assert_eq(_mask(rows, Vector2i(1, 0)), S)
	assert_eq(_family(rows, Vector2i(0, 0)), TerrainAutotiles.Family.NONE)
	assert_eq(_mask(rows, Vector2i(0, 0)), 0)


func test_a_reef_keeps_its_base_tile_and_breaks_no_coastline() -> void:
	var rows: Array[String] = ["SSS", "S*S", "SSS"]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.NONE)
	assert_eq(_family(rows, Vector2i(0, 1)), TerrainAutotiles.Family.NONE)


# --- shoals ------------------------------------------------------------------


func test_a_shoal_surfs_against_the_sea_but_not_its_own_run() -> void:
	var rows: Array[String] = ["SSS", "__.", "..."]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.SHOALS)
	# Surf on the seaward edge only: the neighbouring shoal and the land are dry.
	assert_eq(_mask(rows, Vector2i(0, 1)), N)
	assert_eq(_mask(rows, Vector2i(1, 1)), N)


# --- the sheet grid ----------------------------------------------------------


func test_atlas_coords_walk_the_four_by_four_grid_row_major() -> void:
	assert_eq(TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.ROADS, 7), Vector2i(3, 1))
	assert_eq(TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.COAST, 12), Vector2i(0, 3))
	assert_eq(TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.RIVERS, 15), Vector2i(3, 3))
