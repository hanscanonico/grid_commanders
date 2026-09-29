extends GutTest
## StagePlot3D.layout: the ground one side of the 3D cut-in stage is built from —
## the squad stands on the cell's own ground (or the surface a standing terrain
## names), and what stands rises behind it. Pure, so every terrain is checked
## without a scene.


func _layout(id: StringName) -> PackedStringArray:
	var db := Fixture.terrain_db()
	var terrain := db.by_id(id)
	var ground := db.by_id(terrain.cutin_ground) if terrain.stands_in_cutin() else terrain
	return StagePlot3D.layout(terrain, ground)


func _squad_row(id: StringName) -> String:
	return _layout(id)[StagePlot3D.SQUAD_ROW]


func test_every_terrain_lays_out_a_board_the_mesher_can_read() -> void:
	for terrain in Fixture.terrain_db().all():
		var rows := _layout(terrain.id)
		assert_eq(rows.size(), StagePlot3D.ROWS, String(terrain.id))
		var map := MapData.parse("[terrain]\n" + "\n".join(rows), Fixture.terrain_db())
		assert_not_null(map, "%s parses" % terrain.id)
		assert_eq(map.width, StagePlot3D.COLUMNS, String(terrain.id))


func test_a_squad_stands_on_its_own_ground() -> void:
	assert_eq(_squad_row(&"plains"), ".".repeat(StagePlot3D.COLUMNS))
	assert_eq(_squad_row(&"sea"), "S".repeat(StagePlot3D.COLUMNS))
	assert_eq(_squad_row(&"road"), "=".repeat(StagePlot3D.COLUMNS))
	assert_eq(_squad_row(&"river"), "~".repeat(StagePlot3D.COLUMNS))
	assert_eq(_squad_row(&"bridge"), "+".repeat(StagePlot3D.COLUMNS), "on the deck")


func test_what_stands_rises_behind_and_beside_the_squad_not_under_it() -> void:
	for id: StringName in [&"woods", &"mountain"]:
		var rows := _layout(id)
		var symbol := Fixture.terrain_db().by_id(id).symbol
		assert_eq(rows[0], symbol.repeat(StagePlot3D.COLUMNS), "%s behind" % id)
		var row := rows[StagePlot3D.SQUAD_ROW]
		assert_eq(
			row.left(StagePlot3D.FLANK_COLUMN), ".".repeat(StagePlot3D.FLANK_COLUMN), String(id)
		)
		assert_true(row.ends_with(symbol), "%s flanks it" % id)


func test_a_property_stands_on_a_lot_with_its_paving_in_front() -> void:
	var city := _layout(&"city")
	assert_eq(city[0], ".".repeat(StagePlot3D.COLUMNS), "the building's lot")
	assert_eq(city[StagePlot3D.SQUAD_ROW], "=".repeat(StagePlot3D.COLUMNS), "the road")
	var port := _layout(&"port")
	assert_eq(port[0], ".".repeat(StagePlot3D.COLUMNS), "a port's lot is dry")
	assert_eq(port[StagePlot3D.SQUAD_ROW], "S".repeat(StagePlot3D.COLUMNS), "its berth is not")
