extends GutTest
## The face crop the surfaces smaller than a bust draw (`CommanderVisuals.face_for`).
## The region is a hand-measured rectangle over generated art, so what is pinned
## here is that it stays inside a portrait and that every general — the neutral
## silhouette and a commander-less side included — gets that same square back.


func test_face_region_fits_inside_a_portrait() -> void:
	var region := CommanderVisuals.FACE_REGION
	assert_gte(region.position.x, 0)
	assert_gte(region.position.y, 0)
	assert_lte(region.end.x, CommanderVisuals.PORTRAIT_SIZE.x)
	assert_lte(region.end.y, CommanderVisuals.PORTRAIT_SIZE.y)
	assert_eq(region.size.x, region.size.y, "the small surfaces are squares")


func test_every_commander_hands_back_that_square() -> void:
	var roster: Array[CommanderType] = Fixture.commander_db().all()
	assert_gt(roster.size(), 0, "the roster loaded")
	roster.append(null)
	for commander: CommanderType in roster:
		var face := CommanderVisuals.face_for(commander)
		assert_not_null(face)
		assert_eq(
			face.get_size(),
			Vector2(CommanderVisuals.FACE_REGION.size),
			"face crop for %s" % (commander.id if commander != null else &"<none>")
		)


func test_a_face_is_cached_and_shares_its_portrait() -> void:
	var commander := Fixture.commander_db().all()[0]
	var face := CommanderVisuals.face_for(commander)
	assert_same(face, CommanderVisuals.face_for(commander))
	assert_same((face as AtlasTexture).atlas, CommanderVisuals.portrait_for(commander))
