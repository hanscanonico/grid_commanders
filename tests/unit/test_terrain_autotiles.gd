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


# --- the field's phases ------------------------------------------------------
## Plains is keyed by where it stands rather than by its neighbours, exactly as
## open water is, so what is checked is the field rather than a cell: the lattice
## a stretch of one tile repeats at is what the phases exist to break.


func test_plains_draws_a_phase_of_its_own_sheet_wherever_it_stands() -> void:
	var rows: Array[String] = ["...", ".=.", "..."]
	assert_eq(_family(rows, Vector2i(0, 0)), TerrainAutotiles.Family.PLAINS)
	assert_eq(_family(rows, Vector2i(2, 2)), TerrainAutotiles.Family.PLAINS)
	var map := _map(rows)
	# A cell whose phase is not 0: plains masks to 0, so a phase-0 cell would read
	# the same whether or not `variant` routes the family to its phases.
	var cell := Vector2i(1, 0)
	var phase := TerrainAutotiles.phase(cell, TerrainAutotiles.PLAINS_PHASES)
	assert_ne(phase, 0)
	assert_eq(TerrainAutotiles.variant(map, cell), phase)


func test_a_field_of_plains_wears_every_phase_and_no_periodic_line() -> void:
	var seen := {}
	var column_phases := {}
	for y in 16:
		var row_phases := {}
		for x in 16:
			var phase := TerrainAutotiles.phase(Vector2i(x, y), TerrainAutotiles.PLAINS_PHASES)
			assert_between(phase, 0, TerrainAutotiles.PLAINS_PHASES - 1)
			seen[phase] = true
			row_phases[phase] = true
			if not column_phases.has(x):
				column_phases[x] = {}
			column_phases[x][phase] = true
		assert_gt(row_phases.size(), 1, "row %d is one phase wall to wall" % y)
	for x: int in column_phases:
		assert_gt(column_phases[x].size(), 1, "column %d is one phase top to bottom" % x)
	assert_eq(seen.size(), TerrainAutotiles.PLAINS_PHASES)


func test_the_plains_sheet_is_cut_as_one_row_of_phases() -> void:
	var cells := TerrainAutotiles.sheet_cells(TerrainAutotiles.Family.PLAINS)
	var row: Array[Vector2i] = []
	for index in TerrainAutotiles.PLAINS_PHASES:
		row.append(Vector2i(index, 0))
	assert_eq(cells, row)
	var rows: Array[String] = ["...", "...", "..."]
	var cell := Vector2i(1, 1)
	var variant := TerrainAutotiles.variant(_map(rows), cell)
	assert_eq(variant, TerrainAutotiles.phase(cell, TerrainAutotiles.PLAINS_PHASES))
	assert_has(cells, TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.PLAINS, variant))


## PHASE_COUNTS is what tells the three readers which families are keyed by
## position, so every family it names has a sheet and holds exactly that many
## cells, and a connection family is never in it.
func test_every_phase_keyed_family_has_a_sheet_of_that_many_cells() -> void:
	for p_family: int in TerrainAutotiles.PHASE_COUNTS:
		var count: int = TerrainAutotiles.PHASE_COUNTS[p_family]
		assert_true(TerrainAutotiles.SHEET_PATHS.has(p_family))
		assert_eq(TerrainAutotiles.sheet_cells(p_family).size(), count)
	assert_false(TerrainAutotiles.PHASE_COUNTS.has(TerrainAutotiles.Family.ROADS))
	assert_false(TerrainAutotiles.PHASE_COUNTS.has(TerrainAutotiles.Family.BRIDGES))


## The count and the art are one fact, and the count is the half that goes quiet
## when it breaks: a phase the sheet does not hold is registered as a tile that
## is not there, and a field would draw it as a hole with nothing else failing.
## The sheet's own width is what settles it, read through the cut every painter
## indexes with.
func test_the_constant_names_exactly_the_phases_the_sheet_holds() -> void:
	var sheet := load(TerrainAutotiles.SHEET_PATHS[TerrainAutotiles.Family.PLAINS]) as Texture2D
	assert_not_null(sheet, "the plains sheet did not load")
	var step := BattleView.TERRAIN_PX + TerrainAutotiles.SHEET_SEPARATION
	var span := (
		sheet.get_width() - 2 * TerrainAutotiles.SHEET_MARGIN + TerrainAutotiles.SHEET_SEPARATION
	)
	assert_eq(span % step, 0, "the sheet is not a whole number of cells wide")
	assert_eq(span / step, TerrainAutotiles.PLAINS_PHASES, "the sheet holds a different count")
	assert_eq(
		sheet.get_height(),
		BattleView.TERRAIN_PX + 2 * TerrainAutotiles.SHEET_MARGIN,
		"the phases are not one row"
	)


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
