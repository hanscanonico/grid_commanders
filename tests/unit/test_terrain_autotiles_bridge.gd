extends GutTest
## What a bridge stands over (playtest ED-21): every deck was drawn across a
## river, so a causeway showed grass and banks between its spans and a deck on a
## field showed blue stubs. Split from test_terrain_autotiles.gd so neither suite
## sits over the public-method ceiling; both files ask only TerrainAutotiles'
## statics.

const RIVER := TerrainAutotiles.BridgeBed.RIVER
const SEA := TerrainAutotiles.BridgeBed.SEA
const DRY := TerrainAutotiles.BridgeBed.DRY


func _map(rows: Array[String]) -> MapData:
	return MapData.parse("[terrain]\n" + "\n".join(rows), Fixture.terrain_db())


func _bed(rows: Array[String], cell: Vector2i) -> TerrainAutotiles.BridgeBed:
	return TerrainAutotiles.bridge_bed(_map(rows), cell)


func _coords(rows: Array[String], cell: Vector2i) -> Vector2i:
	var map := _map(rows)
	var family := TerrainAutotiles.family(map, cell)
	return TerrainAutotiles.atlas_coords(family, TerrainAutotiles.variant(map, cell))


func test_a_bridge_across_a_river_keeps_the_river_deck() -> void:
	var rows: Array[String] = [".~.", "=+=", ".~."]
	assert_eq(_bed(rows, Vector2i(1, 1)), RIVER)
	assert_eq(_coords(rows, Vector2i(1, 1)), Vector2i(0, 0))


func test_a_causeway_across_the_sea_stands_over_open_water() -> void:
	# Causeway's own shape: two decks abreast, sea above and below the pair.
	var rows: Array[String] = ["SSSS", "=++=", "=++=", "SSSS"]
	for cell: Vector2i in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		assert_eq(_bed(rows, cell), SEA)
		assert_eq(_coords(rows, cell), Vector2i(0, SEA))


func test_a_deck_beside_a_shoal_or_a_reef_is_over_the_sea() -> void:
	assert_eq(_bed([".__.", "=++=", ".__."] as Array[String], Vector2i(1, 1)), SEA)
	assert_eq(_bed([".*.", "=+=", "..."] as Array[String], Vector2i(1, 1)), SEA)


func test_a_lone_bridge_on_a_field_draws_no_water() -> void:
	var rows: Array[String] = ["...", ".+.", "..."]
	assert_eq(_bed(rows, Vector2i(1, 1)), DRY)
	assert_eq(_coords(rows, Vector2i(1, 1)), Vector2i(1, DRY))


func test_a_field_of_nothing_but_bridges_keeps_the_river_deck() -> void:
	var rows: Array[String] = ["+++", "+++", "+++"]
	assert_eq(_bed(rows, Vector2i(1, 1)), RIVER)


func test_the_middle_of_a_wide_causeway_stays_over_the_sea() -> void:
	# Three decks abreast: the middle row meets only bridges and road.
	var rows: Array[String] = ["SSSSS", "=+++=", "=+++=", "=+++=", "SSSSS"]
	for y in range(1, 4):
		for x in range(1, 4):
			assert_eq(_bed(rows, Vector2i(x, y)), SEA, "bed at %s" % Vector2i(x, y))


func test_the_middle_of_a_wide_bridge_stays_over_the_river() -> void:
	var rows: Array[String] = [".~~~.", "=+++=", "=+++=", "=+++=", ".~~~."]
	assert_eq(_bed(rows, Vector2i(1, 2)), RIVER)
	assert_eq(_bed(rows, Vector2i(2, 2)), RIVER)


func test_a_block_of_bridges_on_a_field_draws_no_water() -> void:
	var rows: Array[String] = ["....", ".++.", ".++.", "...."]
	assert_eq(_bed(rows, Vector2i(1, 1)), DRY)
	var walled: Array[String] = [".....", ".+++.", ".+++.", ".+++.", "....."]
	assert_eq(_bed(walled, Vector2i(2, 2)), DRY)


func test_a_block_of_bridges_decks_along_the_road_it_carries() -> void:
	# Tideflats' crossing: a two-wide block carrying a north-south road.
	var rows: Array[String] = ["S==S", "S++S", "S++S", "S==S"]
	var north_south := TerrainAutotiles.BIT_N | TerrainAutotiles.BIT_S
	for cell: Vector2i in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		assert_eq(TerrainAutotiles.mask(_map(rows), cell), north_south)
	var east_west := TerrainAutotiles.BIT_E | TerrainAutotiles.BIT_W
	var across: Array[String] = ["SSSS", "=++=", "=++=", "SSSS"]
	assert_eq(TerrainAutotiles.mask(_map(across), Vector2i(1, 1)), east_west)


func test_the_bridge_sheet_holds_both_decks_over_every_bed() -> void:
	var cells := TerrainAutotiles.sheet_cells(TerrainAutotiles.Family.BRIDGES)
	assert_eq(cells.size(), TerrainAutotiles.BRIDGE_DECKS * TerrainAutotiles.BridgeBed.size())
	var sheet := load(TerrainAutotiles.SHEET_PATHS[TerrainAutotiles.Family.BRIDGES]) as Texture2D
	var stride := MapThumbnail.CELL + TerrainAutotiles.SHEET_SEPARATION
	for coords in cells:
		var far := Vector2i.ONE * TerrainAutotiles.SHEET_MARGIN + (coords + Vector2i.ONE) * stride
		assert_true(far.x <= sheet.get_width() + TerrainAutotiles.SHEET_SEPARATION)
		assert_true(far.y <= sheet.get_height() + TerrainAutotiles.SHEET_SEPARATION)
