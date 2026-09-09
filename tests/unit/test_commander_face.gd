extends GutTest
## The face chip the surfaces smaller than a bust draw (`CommanderVisuals.face_for`).
##
## `FACE_REGION` is one rectangle over twenty-two per-general poses, so what is
## pinned here is that it stays inside a portrait and that every general gets a
## chip of that shape back. The measurement it was chosen from — that its bottom
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
			face.get_size(), Vector2(CommanderVisuals.FACE_SIZE), "face chip for %s" % commander.id
		)


## The empty seat has a chip like everyone else, and an absent commander falls
## through to it: a chip is a drawing of its own rather than a crop, so the seat
## nobody holds is a blank face rather than a dark blob.
func test_the_empty_seat_has_a_chip_of_its_own() -> void:
	assert_true(db.has(CommanderType.NEUTRAL_ID), "the neutral commander is on the roster")
	for commander: CommanderType in [db.by_id(CommanderType.NEUTRAL_ID), null]:
		var face := CommanderVisuals.face_for(commander)
		assert_eq(
			face.get_size(),
			Vector2(CommanderVisuals.FACE_SIZE),
			"the empty seat draws the chip every seat draws"
		)


## Cached like the bust beside it, and its own file rather than a window onto
## one: a head three times the chip's size, sampled down, is the softness this
## art was rebaked to be rid of.
func test_a_face_is_cached_and_is_its_own_texture() -> void:
	var commander := db.playable()[0]
	var face := CommanderVisuals.face_for(commander)
	assert_same(face, CommanderVisuals.face_for(commander))
	var bust := CommanderVisuals.portrait_for(commander)
	assert_eq(face.get_size(), Vector2(CommanderVisuals.FACE_SIZE), "the chip is chip-sized")
	assert_eq(bust.get_size(), Vector2(CommanderVisuals.PORTRAIT_SIZE), "the bust is bust-sized")
	assert_ne(
		face.resource_path,
		bust.resource_path,
		"the chip is its own baked file, not a window onto the bust"
	)
