extends GutTest
## The face crop the surfaces smaller than a bust draw (`CommanderVisuals.face_for`).
##
## The region is one rectangle over twenty-two per-general poses, so what is
## pinned here is that it stays inside a portrait and that every general gets
## that same square back. The measurement it was chosen from — that its bottom
## edge clears every jaw — is held per bust, per run, by the generator that
## draws them: generators/portraits/tests/test_face_region.py, which reads this
## file for the rectangle and has the skin ramps to measure a chin against.

var db: CommanderDB


func before_all() -> void:
	db = Fixture.commander_db()


func test_face_region_fits_inside_a_portrait() -> void:
	var region := CommanderVisuals.FACE_REGION
	assert_gte(region.position.x, 0)
	assert_gte(region.position.y, 0)
	assert_lte(region.end.x, CommanderVisuals.PORTRAIT_SIZE.x)
	assert_lte(region.end.y, CommanderVisuals.PORTRAIT_SIZE.y)
	assert_eq(region.size.x, region.size.y, "the small surfaces are squares")


func test_every_general_hands_back_that_square() -> void:
	var roster := db.playable()
	assert_gt(roster.size(), 0, "the roster loaded")
	for commander: CommanderType in roster:
		var face := CommanderVisuals.face_for(commander)
		assert_not_null(face)
		assert_eq(
			face.get_size(),
			Vector2(CommanderVisuals.FACE_REGION.size),
			"face crop for %s" % commander.id
		)


## The empty seat keeps its whole bust: the neutral art is featureless, so its
## head crop is a dark blob and only head-and-shoulders reads as an empty seat.
func test_the_empty_seat_is_never_cropped() -> void:
	assert_true(db.has(CommanderType.NEUTRAL_ID), "the neutral commander is on the roster")
	for commander: CommanderType in [db.by_id(CommanderType.NEUTRAL_ID), null]:
		var face := CommanderVisuals.face_for(commander)
		assert_eq(
			face.get_size(),
			Vector2(CommanderVisuals.PORTRAIT_SIZE),
			"the empty seat draws its bust whole"
		)


func test_a_face_is_cached_and_shares_its_portrait() -> void:
	var commander := db.playable()[0]
	var face := CommanderVisuals.face_for(commander)
	assert_same(face, CommanderVisuals.face_for(commander))
	assert_same((face as AtlasTexture).atlas, CommanderVisuals.portrait_for(commander))
