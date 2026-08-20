extends GutTest
## The range's side of the phase arithmetic: mountain is phase-keyed for the
## reason plains is, read at its loudest — a range drawn from one tile is a wall
## of the same peak, and Bulwark's rampart is three rows of exactly that. Split
## from test_terrain_autotiles.gd so neither suite sits over the public-method
## ceiling; both files ask only TerrainAutotiles' statics.


func _map(rows: Array[String]) -> MapData:
	return MapData.parse("[terrain]\n" + "\n".join(rows), Fixture.terrain_db())


func _family(rows: Array[String], cell: Vector2i) -> TerrainAutotiles.Family:
	return TerrainAutotiles.family(_map(rows), cell)


func test_a_mountain_draws_a_phase_of_its_own_sheet_wherever_it_stands() -> void:
	var rows: Array[String] = ["MMM", "M=M", "MMM"]
	assert_eq(_family(rows, Vector2i(0, 0)), TerrainAutotiles.Family.MOUNTAIN)
	assert_eq(_family(rows, Vector2i(2, 2)), TerrainAutotiles.Family.MOUNTAIN)
	var map := _map(rows)
	# A cell whose phase is not 0: a mountain masks to 0, so a phase-0 cell would
	# read the same whether or not `variant` routes the family to its phases.
	var cell := Vector2i(1, 0)
	var phase := TerrainAutotiles.phase(cell, TerrainAutotiles.MOUNTAIN_PHASES)
	assert_ne(phase, 0)
	assert_eq(TerrainAutotiles.variant(map, cell), phase)


func test_a_rampart_of_mountains_wears_more_than_one_phase_along_its_row() -> void:
	var seen := {}
	for x in 49:
		seen[TerrainAutotiles.phase(Vector2i(x, 17), TerrainAutotiles.MOUNTAIN_PHASES)] = true
	assert_eq(seen.size(), TerrainAutotiles.MOUNTAIN_PHASES)


func test_the_mountain_sheet_is_cut_as_one_row_of_phases() -> void:
	var cells := TerrainAutotiles.sheet_cells(TerrainAutotiles.Family.MOUNTAIN)
	assert_eq(cells, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])
	var rows: Array[String] = ["MMM", "MMM", "MMM"]
	var cell := Vector2i(2, 1)
	var variant := TerrainAutotiles.variant(_map(rows), cell)
	assert_eq(variant, TerrainAutotiles.phase(cell, TerrainAutotiles.MOUNTAIN_PHASES))
	assert_has(cells, TerrainAutotiles.atlas_coords(TerrainAutotiles.Family.MOUNTAIN, variant))
