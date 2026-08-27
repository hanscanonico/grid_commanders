extends GutTest
## The face crop the surfaces smaller than a bust draw (`CommanderVisuals.face_for`).
##
## The region is one rectangle over twenty-two per-general poses, so what is
## pinned here is the measurement it was chosen from: that it stays inside a
## portrait, that every general gets that same square back, and — the thing that
## goes quiet when it breaks — that it clears every jaw. A crop whose bottom edge
## crosses a chin cuts a beard off the HUD chip, the speech bust and the campaign
## brief at once, and nothing in the suite could see it.

const FaceSvg := preload("res://tools/commander_face_svg.gd")
## The column the crop is measured on: the region's own middle, which is the one
## the neck, chin and mouth are drawn on for every pose. Deliberately a column
## rather than the whole bottom row — a signature prop is drawn in its owner's
## skin (Morn's haft, Voss's orb), so a row-wide skin scan measures the props.
## The clearance is the gap from the last skin pixel down to the bottom edge; the
## shipped busts measure 12 (Quill) to 21 (Morn).
const CHIN_CLEARANCE_PX := 8
## A pixel is this general's skin when it is that colour under the flat black
## shades the bust is drawn with — the form shade, the neck's cast and the
## window wash all scale a fill toward black rather than tinting it.
const SKIN_SHADE_FLOOR := 0.6
const SKIN_TOLERANCE := 14.0

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


## The pin the crop exists to keep: on every shipped bust the region's bottom
## edge sits below the chin, so no surface that shows a face cuts a jaw or a
## beard off it.
func test_the_crop_clears_every_jaw() -> void:
	var region := CommanderVisuals.FACE_REGION
	var column := region.position.x + region.size.x / 2
	for commander: CommanderType in db.playable():
		var image := _portrait_image(commander)
		if image == null:
			continue
		var skin := Color(FaceSvg.SKIN[FaceSvg.FACES[commander.id]["skin"]])
		var chin := -1
		for y: int in range(region.position.y, region.end.y):
			if _is_skin(image.get_pixel(column, y), skin):
				chin = y
		assert_gt(chin, 0, "%s: the crop's middle column crosses no face" % commander.id)
		assert_gte(
			region.end.y - 1 - chin,
			CHIN_CLEARANCE_PX,
			"%s: the crop's bottom edge cuts the jaw" % commander.id
		)


func _portrait_image(commander: CommanderType) -> Image:
	var texture := CommanderVisuals.portrait_for(commander)
	assert_not_null(texture, "%s has no portrait to read" % commander.id)
	return texture.get_image() if texture != null else null


func _is_skin(pixel: Color, skin: Color) -> bool:
	if pixel.a < 0.8:
		return false
	var square := skin.r * skin.r + skin.g * skin.g + skin.b * skin.b
	var shade := (pixel.r * skin.r + pixel.g * skin.g + pixel.b * skin.b) / square
	shade = clampf(shade, SKIN_SHADE_FLOOR, 1.0)
	var off := maxf(
		maxf(absf(pixel.r - shade * skin.r), absf(pixel.g - shade * skin.g)),
		absf(pixel.b - shade * skin.b)
	)
	return off * 255.0 <= SKIN_TOLERANCE


func test_a_face_is_cached_and_shares_its_portrait() -> void:
	var commander := db.playable()[0]
	var face := CommanderVisuals.face_for(commander)
	assert_same(face, CommanderVisuals.face_for(commander))
	assert_same((face as AtlasTexture).atlas, CommanderVisuals.portrait_for(commander))
