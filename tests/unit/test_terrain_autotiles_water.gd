extends GutTest
## The water families' side of the same arithmetic: which shoreline a sea,
## river or shoal cell wears. Split from test_terrain_autotiles.gd so neither
## suite sits over the public-method ceiling; the rules are one authority's,
## TerrainAutotiles, and both files ask only its statics.

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


# --- rivers ------------------------------------------------------------------


func test_a_river_meeting_the_sea_flows_into_it() -> void:
	var rows: Array[String] = [".S.", ".~.", ".=."]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.RIVERS)
	# North is sea; the road to the south is not a river join without a bridge.
	assert_eq(_mask(rows, Vector2i(1, 1)), N)


func test_a_river_flows_into_a_port() -> void:
	var rows: Array[String] = ["...", "P~.", "..."]
	assert_eq(_mask(rows, Vector2i(1, 1)), W)


## A run of river with land all round it — first_steps' pond — is still river,
## so it wears the river sheet's banked channel and never the coast's sand.
## Its squared end caps are the rivers sheet's, not a mask this file picks
## wrongly: giving a landlocked run a shore is a generator change.
func test_a_landlocked_river_run_stays_on_the_river_sheet() -> void:
	var rows: Array[String] = [".....", ".~~~.", "....."]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.RIVERS)
	assert_eq(_mask(rows, Vector2i(1, 1)), E)
	assert_eq(_mask(rows, Vector2i(2, 1)), E | W)
	assert_eq(_mask(rows, Vector2i(3, 1)), W)


# --- sea and its coastline ---------------------------------------------------


func test_the_sea_coasts_against_land_and_not_against_water() -> void:
	var rows: Array[String] = [".F.", "~S=", ".S."]
	assert_eq(_family(rows, Vector2i(1, 1)), TerrainAutotiles.Family.COAST)
	# Woods north and road east are land; the river west and sea south are not.
	assert_eq(_mask(rows, Vector2i(1, 1)), N | E)


## A one-cell inland lake is coasted on all four sides, exactly as the map's
## sea edge is on the sides that face land — the same sheet, the same rule.
func test_a_one_cell_inland_lake_wears_the_shore_on_every_side() -> void:
	var rows: Array[String] = ["...", ".S.", "..."]
	var lake := Vector2i(1, 1)
	assert_eq(_family(rows, lake), TerrainAutotiles.Family.COAST)
	var edges := _mask(rows, lake)
	assert_eq(edges, N | E | S | W)
	assert_eq(TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.COAST, edges), Vector2i(3, 3))


func test_a_two_cell_lake_shores_against_the_land_and_not_its_own_water() -> void:
	var rows: Array[String] = ["....", ".SS.", "...."]
	assert_eq(_mask(rows, Vector2i(1, 1)), N | S | W)
	assert_eq(_mask(rows, Vector2i(2, 1)), N | E | S)


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
