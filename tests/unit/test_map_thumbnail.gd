extends GutTest
## The miniature's region choice, which is the whole of its terrain opinion:
## which sheet a cell draws from and where on it. Pure statics over MapData,
## like PathArrow.segments, so the parity with the board is checked without a
## Control — a thumbnail that answered differently from TerrainAutotiles would
## be the second opinion the class exists not to be.


func _map(rows: Array[String]) -> MapData:
	return MapData.parse("[terrain]\n" + "\n".join(rows), Fixture.terrain_db())


## Where TerrainAutotiles' answer sits on the family's contact sheet.
func _sheet_cell(family: int, mask: int) -> Rect2:
	var coords := TerrainAutotiles.atlas_coords(family, mask)
	var step := MapThumbnail.CELL + TerrainAutotiles.SHEET_SEPARATION
	var margin := TerrainAutotiles.SHEET_MARGIN
	return Rect2(
		margin + coords.x * step, margin + coords.y * step, MapThumbnail.CELL, MapThumbnail.CELL
	)


func test_a_one_cell_lake_draws_the_coast_variant_the_board_draws() -> void:
	var map := _map(["...", ".S.", "..."])
	var cell := Vector2i(1, 1)
	var family := TerrainAutotiles.family(map, cell)
	assert_eq(family, TerrainAutotiles.Family.COAST)
	assert_eq(MapThumbnail.sheet_path(map, cell), TerrainAutotiles.SHEET_PATHS[family])
	assert_eq(
		MapThumbnail.sheet_region(map, null, cell),
		_sheet_cell(family, TerrainAutotiles.mask(map, cell))
	)


func test_a_road_draws_its_connection_variant() -> void:
	var map := _map(["...", ".==", "..."])
	var cell := Vector2i(1, 1)
	assert_eq(
		MapThumbnail.sheet_path(map, cell),
		TerrainAutotiles.SHEET_PATHS[TerrainAutotiles.Family.ROADS]
	)
	assert_eq(
		MapThumbnail.sheet_region(map, null, cell),
		_sheet_cell(TerrainAutotiles.Family.ROADS, TerrainAutotiles.BIT_E)
	)


## The miniature phases its open water off the same cell the board does, so a
## sea a player picked out of the picker is the sea they are dropped onto.
func test_open_water_draws_the_phase_the_board_draws() -> void:
	var map := _map(["SSSS", "SSSS", "SSSS", "SSSS"])
	var cell := Vector2i(1, 1)
	var family := TerrainAutotiles.family(map, cell)
	assert_eq(family, TerrainAutotiles.Family.SEA)
	assert_eq(MapThumbnail.sheet_path(map, cell), TerrainAutotiles.SHEET_PATHS[family])
	assert_eq(
		MapThumbnail.sheet_region(map, null, cell),
		_sheet_cell(family, TerrainAutotiles.phase(cell, TerrainAutotiles.SEA_PHASES))
	)


## The field is phased off the same cell the board phases it off, for the reason
## the sea is: the miniature can never be a second opinion.
func test_plains_draws_the_phase_the_board_draws() -> void:
	var map := _map(["...", "...", "..."])
	var cell := Vector2i(1, 1)
	var family := TerrainAutotiles.family(map, cell)
	assert_eq(family, TerrainAutotiles.Family.PLAINS)
	assert_eq(MapThumbnail.sheet_path(map, cell), TerrainAutotiles.SHEET_PATHS[family])
	assert_eq(
		MapThumbnail.sheet_region(map, null, cell),
		_sheet_cell(family, TerrainAutotiles.phase(cell, TerrainAutotiles.PLAINS_PHASES))
	)


## The range is phased off the same cell too, and off a cell whose phase is not
## 0, so a miniature reading the atlas column would fail here.
func test_mountains_draw_the_phase_the_board_draws() -> void:
	var map := _map(["MMM", "MMM", "MMM"])
	var cell := Vector2i(1, 0)
	var family := TerrainAutotiles.family(map, cell)
	var phase := TerrainAutotiles.phase(cell, TerrainAutotiles.MOUNTAIN_PHASES)
	assert_eq(family, TerrainAutotiles.Family.MOUNTAIN)
	assert_ne(phase, 0)
	assert_eq(MapThumbnail.sheet_path(map, cell), TerrainAutotiles.SHEET_PATHS[family])
	assert_eq(MapThumbnail.sheet_region(map, null, cell), _sheet_cell(family, phase))


## A terrain with no family keeps the base atlas column.
func test_a_reef_keeps_its_atlas_column() -> void:
	var map := _map(["***", "***", "***"])
	var cell := Vector2i(1, 1)
	var col := map.terrain_at(cell).atlas_col
	assert_eq(MapThumbnail.sheet_path(map, cell), MapThumbnail.ATLAS_PATH)
	assert_eq(
		MapThumbnail.sheet_region(map, null, cell),
		Rect2(col * MapThumbnail.CELL, 0, MapThumbnail.CELL, MapThumbnail.CELL)
	)


## The property columns are transparent overlays, so the miniature paints the
## board's own ground under one and nothing under anything else.
func test_a_property_is_drawn_over_the_default_ground() -> void:
	var db := Fixture.terrain_db()
	var map := _map(["...", ".C.", "..."])
	var ground := db.ground().atlas_col
	assert_eq(
		MapThumbnail.ground_region(map, Vector2i(1, 1)),
		Rect2(ground * MapThumbnail.CELL, 0, MapThumbnail.CELL, MapThumbnail.CELL)
	)
	assert_false(MapThumbnail.ground_region(map, Vector2i(0, 0)).has_area())
